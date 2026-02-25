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
  MKDTEMP_AVAILABLE = false
{% end %}
