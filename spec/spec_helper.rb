require_relative '../hello'

require 'yaml'

RSpec.configure do |config|
  config.color = true
  config.tty = true
  config.formatter = :documentation
end
