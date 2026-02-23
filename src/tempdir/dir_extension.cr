require "./tempdir_class"

class Dir
  def self.mktmpdir(**args, &blk : String -> Nil)
    dir = Tempdir.new(**args)
    begin
      blk.call(dir.path)
    ensure
      dir.close
    end
    nil
  end

  def self.mktmpdir(**args)
    Tempdir.new(**args)
  end
end
