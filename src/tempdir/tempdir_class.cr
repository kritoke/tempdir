require "file_utils"
require "./platform"
require "./exceptions"

class Tempdir < Dir
  VERSION = "1.1.2"

  @closed : Bool = false

  private def buf_to_string(buf : Bytes) : String
    idx = 0
    String.build do |s|
      while buf[idx] != 0
        s << buf[idx].chr
        idx += 1
      end
    end
  end

  private def copy_slice_to_buf(src : Slice(UInt8), buf : Bytes)
    raise ArgumentError.new("Buffer too small") if buf.size <= src.size
    src.copy_to(buf.to_unsafe, src.size)
    buf[src.size] = 0_u8
  end

  private def validate_parent_directory(parent_path : String)
    {% unless flag?(:windows) %}
      info = File.info(parent_path)
      if info.permissions.other_write? && !info.flags.sticky?
        raise PermissionError.new(parent_path, "parent directory is other writable but not sticky")
      end
    {% end %}
  end

  def initialize(**args)
    path = nil
    fallback_created = false
    fallback_path = ""

    {% if flag?(:windows) %}
      base_dir = args[:dir]? || TempdirWindows.get_temp_path
      prefix = args[:prefix]? || "tmp"

      temp_dir_result = TempdirWindows.create_temp_directory(base_dir.to_s, prefix.to_s)

      if temp_dir_result
        fallback_path = temp_dir_result
        fallback_created = true
      else
        fallback_path = File.join(base_dir.to_s, "#{prefix}_#{Random.new.rand(0_u32..0xFFFF_FFFF_u32)}")
        begin
          Dir.mkdir(fallback_path)
          fallback_created = true
        rescue ex : Exception
          raise CreationError.new(fallback_path, ex)
        end
      end
      path = fallback_path
    {% else %}
      parent_path = File.dirname(File.tempname(**args))
      validate_parent_directory(parent_path)

      if MKDTEMP_AVAILABLE
        begin
          base = File.tempname(**args)
          tmpl = "#{base}XXXXXX"
          buf = Bytes.new(tmpl.size + 1)
          copy_slice_to_buf(tmpl.to_slice, buf)

          result = TempdirLib::LibC.mkdtemp(buf.to_unsafe)
          if result != Pointer(UInt8).null
            path = buf_to_string(buf)
          end
        rescue ex : Exception
          STDERR.puts "Tempdir#initialize: mkdtemp failed: #{ex.message}" if ENV["PRISMATIQ_DEBUG"]?
          path = nil
        end
      end

      unless path
        fallback_path = File.tempname(**args)
        begin
          Dir.mkdir(fallback_path, 0o700)
          fallback_created = true
          path = fallback_path
        rescue ex : Exception
          raise CreationError.new(fallback_path, ex)
        end
      end
    {% end %}

    begin
      super(path)
    rescue ex : Exception
      if fallback_created
        FileUtils.rm_rf(fallback_path) rescue nil
      end
      raise CreationError.new(path, ex)
    end
  end

  def create_tempfile(prefix : String, data : Slice(UInt8)? = nil, raise_on_failure : Bool = false) : String?
    {% if flag?(:windows) %}
      create_tempfile_windows(prefix, data, raise_on_failure)
    {% else %}
      create_tempfile_unix(prefix, data, raise_on_failure)
    {% end %}
  end

  {% if flag?(:windows) %}
    private def create_tempfile_windows(prefix : String, data : Slice(UInt8)?, raise_on_failure : Bool) : String?
      safe_prefix = prefix.size > 3 ? prefix[0, 3] : prefix

      result_path = TempdirWindows.create_unique_tempfile(self.path, safe_prefix)

      unless result_path
        result_path = File.join(self.path, "#{safe_prefix}_#{Random.new.rand(0_u32..0xFFFF_FFFF_u32)}")
        tries = 0
        created = false

        while tries < 16 && !created
          begin
            File.open(result_path, "wx") do |f|
              if data
                f.write(data)
                f.flush
              end
            end
            created = true
          rescue ex : File::AlreadyExistsError
            result_path = File.join(self.path, "#{safe_prefix}_#{Random.new.rand(0_u32..0xFFFF_FFFF_u32)}")
          rescue ex : Exception
            STDERR.puts "Tempdir#create_tempfile windows fallback failed: #{ex.message}" if ENV["PRISMATIQ_DEBUG"]?
            return handle_failure(prefix, raise_on_failure, TempfileError.new(prefix, ex))
          end
          tries += 1
        end

        unless created
          return handle_failure(prefix, raise_on_failure, TempfileError.new(prefix))
        end
      else
        if data
          begin
            File.open(result_path, "w") do |f|
              f.write(data)
              f.flush
            end
          rescue ex : Exception
            File.delete(result_path) rescue nil
            return handle_failure(prefix, raise_on_failure, WriteError.new(result_path, ex))
          end
        end
      end

      result_path
    end
  {% end %}

  private def create_tempfile_unix(prefix : String, data : Slice(UInt8)?, raise_on_failure : Bool) : String?
    safe_prefix = prefix.size > 100 ? prefix[0, 100] : prefix
    tmpl = File.join(self.path, "#{safe_prefix}XXXXXX")
    buf = Bytes.new(tmpl.to_slice.size + 1)
    copy_slice_to_buf(tmpl.to_slice, buf)

    fd = -1
    result_path : String? = nil

    if MKDTEMP_AVAILABLE
      fd = TempdirLib::LibC.mkstemp(buf.to_unsafe)
      if fd < 0
        return handle_failure(prefix, raise_on_failure, TempfileError.new(prefix))
      end

      if data
        total = data.size
        written = 0
        while written < total
          ptr = data.to_unsafe + written
          left = (total - written).to_u64
          w = TempdirLib::LibC.write(fd, ptr.as(Pointer(Void)), left)
          if w <= 0
            TempdirLib::LibC.close(fd)
            cleanup_tempfile(buf)
            return handle_failure(prefix, raise_on_failure, WriteError.new(buf_to_string(buf)))
          end
          written += w.to_i
        end
      end

      TempdirLib::LibC.close(fd)
      result_path = buf_to_string(buf)
    else
      begin
        path = buf_to_string(buf)
        tries = 0
        opened = false

        while tries < 16 && !opened
          begin
            File.open(path, "wx") do |f|
              if data
                f.write(data)
                f.flush
              end
            end
            opened = true
          rescue ex : File::AlreadyExistsError
            path = "#{path}_#{Random.new.rand(0_u32..0xFFFF_FFFF_u32)}"
          end
          tries += 1
        end

        unless opened
          return handle_failure(prefix, raise_on_failure, TempfileError.new(prefix))
        end
        result_path = path
      rescue ex : Exception
        STDERR.puts "Tempdir#create_tempfile fallback failed: #{ex.message}" if ENV["PRISMATIQ_DEBUG"]?
        return handle_failure(prefix, raise_on_failure, TempfileError.new(prefix, ex))
      end
    end

    begin
      File.chmod(result_path, 0o600)
    rescue ex : Exception
      STDERR.puts "Tempdir#create_tempfile: chmod failed: #{ex.message}" if ENV["PRISMATIQ_DEBUG"]?
    end

    result_path
  end

  private def handle_failure(prefix : String, raise_on_failure : Bool, error : Error)
    if raise_on_failure
      raise error
    else
      nil
    end
  end

  private def cleanup_tempfile(buf : Bytes)
    path = buf_to_string(buf)
    File.delete(path) rescue nil
  end

  private def cleanup_created_paths(paths : Array(String))
    paths.each do |p|
      File.delete(p) rescue nil
    end
  end

  def close
    return if @closed
    @closed = true
    super
    FileUtils.rm_rf(self.path)
  end

  def finalize
    close unless @closed
  end
end
