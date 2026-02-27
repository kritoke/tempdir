require "file_utils"
require "./tempdir_class"

module FunctionalTempdir
  # Value-like wrapper around the existing Tempdir class that
  # exposes a small, composable API: create, with_tempdir, remove,
  # and create_tempfile. This keeps side effects in one place while
  # presenting a simpler functional usage pattern.
  struct Info
    # Keep the underlying Tempdir instance; expose path via method
    getter tempdir : ::Tempdir

    def initialize(@tempdir : ::Tempdir)
    end

    def path : String
      @tempdir.path
    end

    # Delegate create_tempfile to the underlying Tempdir instance
    def create_tempfile(prefix : String, data : Slice(UInt8)? = nil, raise_on_failure : Bool = false) : String?
      @tempdir.create_tempfile(prefix, data, raise_on_failure)
    end

    # Close (remove) the underlying tempdir; idempotent via Tempdir#close
    def close
      @tempdir.close
    end
  end

  # Create a Tempdir and return an Info wrapper
  def self.create(**args) : Info
    t = ::Tempdir.new(**args)
    Info.new(t)
  end

  # Convenience that yields the path and guarantees cleanup
  def self.with_tempdir(**args)
    info = create(**args)
    begin
      yield info.path
    ensure
      info.close
    end
    nil
  end

  # Remove a previously created Info (idempotent)
  def self.remove(info : Info)
    info.close
  end
end
