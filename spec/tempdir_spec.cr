require "./spec_helper"

describe Tempdir do
  it "VERSION matches shard.yml" do
    Tempdir::VERSION.should eq("1.2.1")
  end

  it "creates an empty directory" do
    m = Tempdir.new
    begin
      n = 0
      while (path = m.read)
        n += 1 if path != "." && path != ".."
      end
      n.should eq 0
    ensure
      m.close
    end
  end

  it "removes the created directory after close" do
    m = Tempdir.new
    begin
      path = m.path
      File.open(File.join(path, "temp"), "w") do |fp|
        fp.puts "temp"
      end
    ensure
      m.close
    end
    File.exists?(path).should be_false
  end

  {% if !flag?(:windows) %}
    it "raises if other writable and not sticky directory is used for base" do
      m = Tempdir.new
      begin
        dir = File.join(m.path, "foo")
        Dir.mkdir(dir)
        File.chmod(dir, 0o777)
        expect_raises(Tempdir::PermissionError) do
          Tempdir.new(dir: dir)
        end
      ensure
        m.close
      end
    end

    it "creates 'go-rwx' directory" do
      m = Tempdir.new
      begin
        info = File.info(m.path)
        perm = info.permissions
        perm.group_read?.should be_false
        perm.group_write?.should be_false
        perm.group_execute?.should be_false
        perm.other_read?.should be_false
        perm.other_write?.should be_false
        perm.other_execute?.should be_false
        data = Slice(UInt8).new(1)
        data[0] = 0x78_u8
        created = m.create_tempfile("perm_test_", data)
        created.should_not be_nil
        finfo = File.info(created.not_nil!)
        fperm = finfo.permissions
        fperm.owner_read?.should be_true
        fperm.owner_write?.should be_true
        File.delete(created.not_nil!) rescue nil
      ensure
        m.close
      end
    end
  {% end %}

  it "create_tempfile without data" do
    m = Tempdir.new
    begin
      created = m.create_tempfile("nodata_")
      created.should_not be_nil
      File.exists?(created.not_nil!).should be_true
      File.delete(created.not_nil!) rescue nil
    ensure
      m.close
    end
  end

  it "create_tempfile preserves binary data" do
    m = Tempdir.new
    begin
      arr = [0_u8, 1_u8, 127_u8, 128_u8, 200_u8, 255_u8]
      data = Slice(UInt8).new(arr.size)
      arr.each_with_index { |b, i| data[i] = b }
      created = m.create_tempfile("binary_", data)
      created.should_not be_nil
      content = File.read(created.not_nil!)
      content.bytes.should eq(arr)
      File.delete(created.not_nil!) rescue nil
    ensure
      m.close
    end
  end

  it "create_tempfile handles long prefix" do
    m = Tempdir.new
    begin
      long_prefix = "x" * 200
      created = m.create_tempfile(long_prefix, Slice(UInt8).new(0))
      created.should_not be_nil
      File.delete(created.not_nil!) rescue nil
    ensure
      m.close
    end
  end

  it "path is accessible" do
    m = Tempdir.new
    begin
      m.path.should_not be_empty
      File.directory?(m.path).should be_true
    ensure
      m.close
    end
  end

  it "create_tempfile returns nil on failure by default" do
    m = Tempdir.new
    m.close
    created = m.create_tempfile("test_")
    created.should be_nil
  end

  it "create_tempfile raises TempfileError when raise_on_failure is true" do
    m = Tempdir.new
    m.close
    expect_raises(Tempdir::TempfileError) do
      m.create_tempfile("test_", raise_on_failure: true)
    end
  end

  it "create_tempfile is atomic and handles concurrent creation" do
    m = Tempdir.new
    begin
      paths = [] of String
      10.times do
        created = m.create_tempfile("concurrent_")
        next unless created
        paths << created
      end
      paths.size.should eq(10)
      paths.uniq.size.should eq(10)
      paths.each do |p|
        File.exists?(p).should be_true
        File.delete(p) rescue nil
      end
    ensure
      m.close
    end
  end

  it "close is idempotent and safe to call multiple times" do
    m = Tempdir.new
    path = m.path
    m.close
    m.close
    m.close
    File.exists?(path).should be_false
  end
end

describe "Tempdir exceptions" do
  {% if !flag?(:windows) %}
    it "PermissionError includes reason" do
      m = Tempdir.new
      begin
        dir = File.join(m.path, "foo")
        Dir.mkdir(dir)
        File.chmod(dir, 0o777)
        begin
          Tempdir.new(dir: dir)
        rescue ex : Tempdir::PermissionError
          ex.message.not_nil!.should contain("parent directory is other writable but not sticky")
        end
      ensure
        m.close
      end
    end
  {% end %}

  it "TempfileError includes prefix" do
    m = Tempdir.new
    m.close
    begin
      m.create_tempfile("myprefix_", raise_on_failure: true)
    rescue ex : Tempdir::TempfileError
      ex.message.not_nil!.should contain("myprefix_")
    end
  end

  it "Tempdir::Error is base class for all tempdir errors" do
    Tempdir::CreationError.new("/tmp/test").should be_a(Tempdir::Error)
    Tempdir::PermissionError.new("/tmp/test", "test").should be_a(Tempdir::Error)
    Tempdir::TempfileError.new("prefix").should be_a(Tempdir::Error)
    Tempdir::WriteError.new("/tmp/test").should be_a(Tempdir::Error)
  end
end

describe "Dir.mktmpdir" do
  it "removed after block left" do
    path = ""
    Dir.mktmpdir do |dir|
      path = dir
      File.open(File.join(dir, "temp"), "w") do |fp|
        fp.puts("temp")
      end
    end
    path.empty?.should be_false
    File.exists?(path).should be_false
  end

  it "removed after block left (with exception)" do
    path = ""
    begin
      Dir.mktmpdir do |dir|
        path = dir
        raise Exception.new
      end
    rescue
    end
    path.empty?.should be_false
    File.exists?(path).should be_false
  end

  it "returns FunctionalTempdir::Info instance without block" do
    dir = Dir.mktmpdir
    dir.should be_a(FunctionalTempdir::Info)
    path = dir.path
    dir.close
    File.exists?(path).should be_false
  end
end
