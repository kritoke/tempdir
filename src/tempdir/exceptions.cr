class Tempdir < Dir
  class Error < Exception
  end

  class CreationError < Error
    def initialize(path : String, cause : Exception? = nil)
      super("Failed to create temporary directory at #{path}", cause)
    end
  end

  class PermissionError < Error
    def initialize(path : String, @reason : String)
      super("Permission error for #{path}: #{@reason}")
    end
  end

  class TempfileError < Error
    def initialize(prefix : String, cause : Exception? = nil)
      super("Failed to create temporary file with prefix '#{prefix}'", cause)
    end
  end

  class WriteError < Error
    def initialize(path : String, cause : Exception? = nil)
      super("Failed to write data to #{path}", cause)
    end
  end
end
