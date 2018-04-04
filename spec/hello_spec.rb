require 'spec_helper'

describe "#hello" do
  before :all do
    @hello = Hello.new("Welcome to AbarCloud", "Hello World!")
  end

  it "returns the correct title" do
    expect(@hello.title).to eq("Welcome to AbarCloud")
  end

  it "returns the correct message" do
    expect(@hello.message).to eq("Hello World!")
  end

  it "is always ok" do
    expect(2).to eq(2)
  end
end
