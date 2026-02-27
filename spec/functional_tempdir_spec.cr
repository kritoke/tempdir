require "./spec_helper"
require "../src/tempdir/functional_tempdir"

describe FunctionalTempdir do
  it "create returns an Info with accessible path and can be removed" do
    info = FunctionalTempdir.create
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
end
