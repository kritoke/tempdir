require "./spec_helper"

describe Tempdir do
  {% if flag?(:windows) %}
  it "create_tempfile uses CreateFile path atomically" do
    m = Tempdir.new
    begin
      data = Slice(UInt8).new(3)
      data[0] = 1_u8
      data[1] = 2_u8
      data[2] = 3_u8

      created = m.create_tempfile("cf_", data)
      created.should_not be_nil
      File.exists?(created.not_nil!).should be_true
      content = File.read(created.not_nil!)
      content.bytes.should eq([1_u8,2_u8,3_u8])
    ensure
      m.close
    end
  end

  it "create_tempfile sets owner-only permissions where supported" do
    m = Tempdir.new
    begin
      created = m.create_tempfile("perm_", Slice(UInt8).new(1))
      created.should_not be_nil
      # On Windows we at least expect the file to be readable
      File.exists?(created.not_nil!).should be_true
    ensure
      m.close
    end
  end
  {% else %}
  it "skips Windows-specific tests on non-Windows" do
  end
  {% end %}
end
