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

  module TempdirWindows
    def self.get_temp_path : String
      Dir.tempdir
    end

    def self.create_temp_directory(base_dir : String, prefix : String) : String?
      tries = 0
      while tries < 16
        temp_name = File.join(base_dir, "#{prefix}_#{Random.new.rand(0_u32..0xFFFF_FFFF_u32)}")
        begin
          Dir.mkdir(temp_name)
          return temp_name
        rescue File::AlreadyExistsError
        rescue File::PermissionError
          return nil
        end
        tries += 1
      end
      nil
    end
  end
{% end %}
