#

require 'sinatra'

set :environment, ENV['RACK_ENV'].to_sym
disable :run, :reload

require './bkget.rb'

run Sinatra::Application
