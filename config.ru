require "sinatra"
require "json"
require "Octokit"

module Spike
  class SimpleApp < Sinatra::Base

    # Provide authentication credentials
    Octokit.configure do |c|
      c.login = 'login'
      c.password = 'password'
      c.connection_options[:ssl] = { :verify => false }
    end

    get '/' do
       body JSON.dump Octokit.user.login
    end
  end

  def self.app
    @app ||= Rack::Builder.new do
      run SimpleApp
    end
  end
end

run Spike.app

__END__
