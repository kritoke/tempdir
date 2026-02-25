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
      fun CreateFileW(lpFileName : UInt16*, dwDesiredAccess : UInt32, dwShareMode : UInt32, lpSecurityAttributes : Void*, dwCreationDisposition : UInt32, dwFlagsAndAttributes : UInt32, hTemplateFile : UInt32) : Void*
      fun CloseHandle(hObject : Void*) : Int32
      fun GetTempPathW(nBufferLength : UInt32, lpBuffer : UInt16*) : UInt32
      fun GetTempFileNameW(lpPathName : UInt16*, lpPrefixString : UInt16*, uUnique : UInt32, lpTempFileName : UInt16*) : UInt32
      fun CreateDirectoryW(lpPathName : UInt16*, lpSecurityAttributes : Void*) : Int32
      fun GetLastError : UInt32
      fun DeleteFileW(lpFileName : UInt16*) : Int32
      fun RemoveDirectoryW(lpPathName : UInt16*) : Int32
      fun GetLongPathNameW(lpszShortPath : UInt16*, lpszLongPath : UInt16*, cchBuffer : UInt32) : UInt32
    end
  end

  MKDTEMP_AVAILABLE = false

  module TempdirWindows
    MAX_PATH             = 260
    UNC_PREFIX           = "\\\\?\\"
    EXTENDED_PATH_LENGTH = 32767

    def self.to_widechar(str : String) : Slice(UInt16)
      utf16 = str.to_utf16
      result = Slice(UInt16).new(utf16.size + 1, 0_u16)
      utf16.copy_to(result.to_unsafe, utf16.size)
      result
    end

    def self.from_widechar(slice : Slice(UInt16)) : String
      String.from_utf16(slice)
    end

    def self.get_temp_path : String
      buf = Slice(UInt16).new(EXTENDED_PATH_LENGTH, 0_u16)
      len = Win32::Kernel32.GetTempPathW(buf.size.to_u32, buf.to_unsafe)
      return Dir.tempdir if len == 0
      from_widechar(buf)
    end

    def self.make_extended_path(path : String) : String
      return path if path.starts_with?(UNC_PREFIX)
      return path unless path.size > MAX_PATH - 14

      if path.starts_with?("\\\\")
        "\\\\?\\UNC\\#{path[2..-1]}"
      else
        "#{UNC_PREFIX}#{File.expand_path(path)}"
      end
    end

    def self.get_temp_filename(dir : String, prefix : String) : String?
      dir_w = to_widechar(make_extended_path(dir))
      prefix_w = to_widechar(prefix)
      buf = Slice(UInt16).new(EXTENDED_PATH_LENGTH, 0_u16)

      result = Win32::Kernel32.GetTempFileNameW(
        dir_w.to_unsafe,
        prefix_w.to_unsafe,
        0_u32,
        buf.to_unsafe
      )

      return nil if result == 0
      from_widechar(buf)
    end

    def self.create_unique_tempfile(dir : String, prefix : String) : String?
      tries = 0
      while tries < 16
        temp_file = get_temp_filename(dir, prefix)
        return nil unless temp_file

        extended_path = make_extended_path(temp_file)
        path_w = to_widechar(extended_path)

        handle = Win32::Kernel32.CreateFileW(
          path_w.to_unsafe,
          0x40000000_u32,
          0_u32,
          Pointer(Void).null,
          1_u32,
          0x80_u32,
          0_u32
        )

        if !handle.null?
          Win32::Kernel32.CloseHandle(handle)
          return temp_file
        end

        error = Win32::Kernel32.GetLastError
        break if error != 80_u32

        tries += 1
      end
      nil
    end

    def self.create_temp_directory(base_dir : String, prefix : String) : String?
      tries = 0
      while tries < 16
        temp_name = get_temp_filename(base_dir, prefix)
        return nil unless temp_name

        File.delete(temp_name) rescue nil

        extended_path = make_extended_path(temp_name)
        path_w = to_widechar(extended_path)

        result = Win32::Kernel32.CreateDirectoryW(path_w.to_unsafe, Pointer(Void).null)
        if result != 0
          return temp_name
        end

        error = Win32::Kernel32.GetLastError
        break if error != 183_u32

        tries += 1
      end
      nil
    end
  end
{% end %}
