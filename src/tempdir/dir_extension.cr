require "./tempdir_class"
require "./functional_tempdir"

class Dir
  # Block form: use the functional helper to guarantee cleanup
  def self.mktmpdir(**args, &blk : String -> Nil)
    FunctionalTempdir.with_tempdir(**args, &blk)
  end

  # Non-block form remains compatible and returns a Tempdir instance
  def self.mktmpdir(**args)
    # Prefer the functional immutable wrapper for non-block usage so callers
    # get a value-like object and explicit cleanup via `close`.
    res = FunctionalTempdir.create(**args)
    if !res.success?
      raise res.error!
    end
    # Return the original Tempdir instance for full backward compatibility
    res.value!.tempdir
  end
end
