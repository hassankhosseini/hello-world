require 'sinatra'

get '/' do
  puts 'Hello world requested...'
  @hello = Hello.new("Welcom to AbarCloud.", "Hello World!")
  erb :index
end

class Hello
  attr_accessor :title, :message, :env
  def initialize(title, message)
    @title = title
    @message = message
    @env = ENV['DEPLOYMENT_ENV']
  end
end
