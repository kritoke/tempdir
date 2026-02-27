require "./spec_helper"
require "../src/tempdir/functional_tempdir"

describe FunctionalTempdir do
  it "create returns a Result-wrapped Info with accessible path and can be removed" do
    res = FunctionalTempdir.create
    res.success?.should be_true
    info = res.value!
    begin
      info.path.should_not be_empty
      File.directory?(info.path).should be_true
    ensure
      FunctionalTempdir.remove(info)
    end
    File.exists?(info.path).should be_false
  end

  it "with_tempdir yields path and removes after block" do
    path = ""
    FunctionalTempdir.with_tempdir do |p|
      path = p
      File.open(File.join(p, "temp"), "w") { |f| f.puts("x") }
      File.exists?(p).should be_true
    end
    path.empty?.should be_false
    File.exists?(path).should be_false
  end

  it "create_tempfile returns Result and creates file" do
    res = FunctionalTempdir.create
    res.success?.should be_true
    info = res.value!
    begin
      r = info.create_tempfile("nodata_")
      r.success?.should be_true
      path = r.value!
      File.exists?(path).should be_true
      File.delete(path) rescue nil
    ensure
      FunctionalTempdir.remove(info)
    end
  end
end
