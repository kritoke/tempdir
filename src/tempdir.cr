require "file_utils"

# Provide a platform-level MKDTEMP_AVAILABLE flag and bind mkdtemp where
# supported. We do this at file scope (not inside methods) to comply with
# Crystal's restrictions on lib definitions.
{% unless flag?(:windows) %}
module ::TempdirLib
  lib LibC
    fun mkdtemp(template : Pointer(UInt8)) : Pointer(UInt8)
    fun mkstemp(template : Pointer(UInt8)) : Int32
    fun write(fd : Int32, buf : Pointer(Void), count : UInt64) : Int64
    fun close(fd : Int32) : Int32
  end
end
MKDTEMP_AVAILABLE = true
{% else %}
module ::Win32
  lib Kernel32
    fun CreateFileA(lpFileName : Pointer(UInt8), dwDesiredAccess : UInt32, dwShareMode : UInt32, lpSecurityAttributes : Pointer(Void), dwCreationDisposition : UInt32, dwFlagsAndAttributes : UInt32, hTemplateFile : Int32) : Int32
    fun CloseHandle(hObject : Int32) : Int32
  end
end

# Windows will not have mkdtemp/mkstemp bindings available
MKDTEMP_AVAILABLE = false
{% end %}

# Creates a temporary directory.
class Tempdir < Dir
  VERSION = "0.1.0"

  # Creates a new temporary directory.
  #
  # The given arguments will be passed to `File.tempname` as-is.
  #
  # Directory will be created with 0o700 permission.
  #
  # This method raises ArgumentError if parent directory of created
  # directory is writable by others and not sticky bit is set.
  def initialize(**args)
    # Attempt atomic creation via mkdtemp on Unix-like systems. If mkdtemp is
    # not available or fails, fall back to the original File.tempname + mkdir
    # approach. The mkdtemp binding and call are done at file scope in order
    # to avoid defining a lib inside a method.
    path = nil
    if MKDTEMP_AVAILABLE
      begin
        base = File.tempname(**args)
        tmpl = "#{base}XXXXXX"
        buf = Bytes.new(tmpl.size + 1)
        i = 0
        while i < tmpl.size
          buf[i] = tmpl.to_slice[i]
          i += 1
        end
        buf[i] = 0

        result = TempdirLib::LibC.mkdtemp(buf.to_unsafe)
        if result != Pointer(UInt8).null
          idx = 0
          path = String.build do |s|
            while buf[idx] != 0
              s << buf[idx].chr
              idx += 1
            end
          end
        end
      rescue
        path = nil
      end
    end

    if !path
      # Fallback for Windows or if mkdtemp failed
      path = File.tempname(**args)
      # Fallback creation for platforms without mkdtemp.
      Dir.mkdir(path, 0o700)
    end

    info = File.info(File.dirname(path))
    if info.permissions.other_write? && !info.flags.sticky?
      FileUtils.rm_rf(path)
      raise ArgumentError.new("parent directory is other writable but not sticky")
    end
    super(path)
  end

  # Create a tempfile inside this Tempdir, optionally writing `data` into it.
  # Returns the created file path or nil on error.
  def create_tempfile(prefix : String, data : Slice(UInt8)? = nil) : String?
    # Truncate the prefix to avoid filename-too-long errors on some platforms
    safe_prefix = prefix.size > 100 ? prefix[0, 100] : prefix
    tmpl = File.join(self.path, "#{safe_prefix}XXXXXX")
    tmpl_bytes = tmpl.to_slice
    buf = Bytes.new(tmpl_bytes.size + 1)
    i = 0
    while i < tmpl_bytes.size
      buf[i] = tmpl_bytes[i]
      i += 1
    end
    buf[i] = 0

    # If mkstemp is available use it; on Windows we'll fallback to Crystal IO
    fd = -1
    if MKDTEMP_AVAILABLE
      fd = TempdirLib::LibC.mkstemp(buf.to_unsafe)
      return nil if fd < 0
    else
      # Attempt a Windows-specific atomic creation if compiled for Windows,
      # otherwise fall back to a non-atomic creation path.
      {% if flag?(:windows) %}
      begin
        path = String.build do |s|
          idx = 0
          while buf[idx] != 0
            s << buf[idx].chr
            idx += 1
          end
        end

        tries = 0
        created = false
        created_path = path
        while tries < 16 && !created
          ptr = created_path.to_slice.to_unsafe
          # Constants: GENERIC_WRITE=0x40000000, CREATE_NEW=1, FILE_ATTRIBUTE_NORMAL=0x80
          handle = Win32::Kernel32.CreateFileA(ptr, 0x40000000_u32, 0_u32, Pointer(Void).null, 1_u32, 0x80_u32, 0)
          if handle != -1
            # close handle and use Crystal to write data
            Win32::Kernel32.CloseHandle(handle)
            begin
            File.open(created_path, "w") do |f|
                if data
                  total = data.size
                  b = Bytes.new(total)
                  i = 0
                  while i < total
                    b[i] = data[i]
                    i += 1
                  end
                  f.write(b)
                  f.flush
                end
              end
              created = true
            rescue
              # couldn't write after creating file; remove and retry
              File.delete(created_path) rescue nil
            end
          else
            created_path = "#{path}_#{Random.new.rand(0_u32..0xFFFF_FFFF_u32)}"
          end
          tries += 1
        end
        return nil unless created
        path = created_path
      rescue ex : Exception
        STDERR.puts "Tempdir#create_tempfile windows fallback failed: #{ex.message}" if ENV["PRISMATIQ_DEBUG"]?
        return nil
      end
      {% else %}
      # Non-Windows fallback: create the file via Crystal I/O ensuring uniqueness
      begin
        path = String.build do |s|
          idx = 0
          while buf[idx] != 0
            s << buf[idx].chr
            idx += 1
          end
        end
        tries = 0
        opened = false
        while tries < 16 && !opened
          if !File.exists?(path)
            File.open(path, "w") do |f|
              if data
                total = data.size
                b = Bytes.new(total)
                i = 0
                while i < total
                  b[i] = data[i]
                  i += 1
                end
                f.write(b)
                f.flush
              end
            end
            opened = true
          else
            path = "#{path}_#{Random.new.rand(0_u32..0xFFFF_FFFF_u32)}"
          end
          tries += 1
        end
        return nil unless opened
      rescue ex : Exception
        STDERR.puts "Tempdir#create_tempfile fallback failed: #{ex.message}" if ENV["PRISMATIQ_DEBUG"]?
        return nil
      end
      {% end %}
    end

    if MKDTEMP_AVAILABLE
      if data
        total = data.size
        written = 0
        while written < total
          ptr = data.to_unsafe + written
          left = (total - written).to_u64
          w = TempdirLib::LibC.write(fd, ptr.as(Pointer(Void)), left)
          if w <= 0
            TempdirLib::LibC.close(fd)
            return nil
          end
          written += w.to_i
        end
      end

      TempdirLib::LibC.close(fd)
    end

    # convert buffer to string
    idx = 0
    path = String.build do |s|
      while buf[idx] != 0
        s << buf[idx].chr
        idx += 1
      end
    end

    # set restrictive permissions (owner rwx for dir, but file should be 600)
    begin
      # Explicitly set owner-only read/write permissions when possible.
      File.chmod(path, 0o600)
    rescue ex : Exception
      STDERR.puts "Tempdir#create_tempfile: chmod failed: #{ex.message}" if ENV["PRISMATIQ_DEBUG"]?
    end

    path
  end

  # Close temporary directory and remove its entries.
  def close
    super
    FileUtils.rm_rf(self.path)
  end
end

class Dir
  # Creates a new temporary directory
  #
  # The given arguments will be passed to `File.tempname` as-is.
  #
  # Alias for `Tempdir.new`.
  # Creates a new temporary directory. If a block is given, yields the
  # temporary directory path to the block and ensures cleanup afterwards.
  # Otherwise returns a Tempdir instance (caller must call #close).
  def self.mktmpdir(**args, &blk : String -> Nil)
    dir = Tempdir.new(**args)
    if blk
      begin
        # Keep legacy behavior: yield the directory path to the block
        blk.call(dir.path)
      ensure
        dir.close
      end
      nil
    else
      dir
    end
  end

  # Overload for no-block usage
  def self.mktmpdir(**args)
    Tempdir.new(**args)
  end
end
