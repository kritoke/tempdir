{% unless flag?(:windows) %}
  module TempdirLib
    lib LibC
      fun mkdtemp(template : Pointer(UInt8)) : Pointer(UInt8)
      fun mkstemp(template : Pointer(UInt8)) : Int32
      fun write(fd : Int32, buf : Pointer(Void), count : UInt64) : Int64
      fun close(fd : Int32) : Int32
    end
  end

  MKDTEMP_AVAILABLE = true
{% else %}
  MKDTEMP_AVAILABLE = false
{% end %}

module TempdirFFI
  # Convert a null-terminated C buffer into a Crystal String
  def self.buf_to_string(buf : Bytes) : String
    idx = 0
    String.build do |s|
      while buf[idx] != 0
        s << buf[idx].chr
        idx += 1
      end
    end
  end

  # Copy a Slice(UInt8) into a Bytes buffer and append a NUL
  def self.copy_slice_to_buf(src : Slice(UInt8), buf : Bytes)
    raise ArgumentError.new("Buffer too small") if buf.size <= src.size
    src.copy_to(buf.to_unsafe, src.size)
    buf[src.size] = 0_u8
  end

  # Remove tempfile pointed by a buffer
  def self.cleanup_tempfile(buf : Bytes)
    path = buf_to_string(buf)
    File.delete(path) rescue nil
  end
end
