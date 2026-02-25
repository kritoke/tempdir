require "file_utils"
require "./platform"
require "./exceptions"

class Tempdir < Dir
  VERSION = "1.2.0"

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
    return if MKDTEMP_AVAILABLE == false
    info = File.info(parent_path)
    if info.permissions.other_write? && !info.flags.sticky?
      raise PermissionError.new(parent_path, "parent directory is other writable but not sticky")
    end
  end

  def initialize(**args)
    parent_path = File.dirname(File.tempname(**args))
    validate_parent_directory(parent_path)

    path = try_mkdtemp(**args)
    unless path
      fallback_path = File.tempname(**args)
      begin
        Dir.mkdir(fallback_path, 0o700)
        path = fallback_path
      rescue ex : Exception
        raise CreationError.new(fallback_path, ex)
      end
    end

    begin
      super(path)
    rescue ex : Exception
      FileUtils.rm_rf(path) rescue nil
      raise CreationError.new(path, ex)
    end
  end

  private def try_mkdtemp(**args) : String?
    {% if flag?(:windows) %}
      return nil
    {% else %}
      return nil unless MKDTEMP_AVAILABLE
      begin
        base = File.tempname(**args)
        tmpl = "#{base}XXXXXX"
        buf = Bytes.new(tmpl.size + 1)
        copy_slice_to_buf(tmpl.to_slice, buf)

        result = TempdirLib::LibC.mkdtemp(buf.to_unsafe)
        if result != Pointer(UInt8).null
          return buf_to_string(buf)
        end
      rescue ex : Exception
        STDERR.puts "Tempdir#initialize: mkdtemp failed: #{ex.message}" if ENV["PRISMATIQ_DEBUG"]?
      end
      nil
    {% end %}
  end

  def create_tempfile(prefix : String, data : Slice(UInt8)? = nil, raise_on_failure : Bool = false) : String?
    safe_prefix = prefix.size > 100 ? prefix[0, 100] : prefix
    tmpl = File.join(self.path, "#{safe_prefix}XXXXXX")
    buf = Bytes.new(tmpl.to_slice.size + 1)
    copy_slice_to_buf(tmpl.to_slice, buf)

    result = try_mkstemp(buf, prefix, data, raise_on_failure)
    return result if result

    fallback_create_tempfile(buf, prefix, data, raise_on_failure)
  end

  private def try_mkstemp(buf : Bytes, prefix : String, data : Slice(UInt8)?, raise_on_failure : Bool) : String?
    {% if flag?(:windows) %}
      return nil
    {% else %}
      return nil unless MKDTEMP_AVAILABLE

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
      buf_to_string(buf)
    {% end %}
  end

  private def fallback_create_tempfile(buf : Bytes, prefix : String, data : Slice(UInt8)?, raise_on_failure : Bool) : String?
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
