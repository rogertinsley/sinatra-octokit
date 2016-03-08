require "sinatra"
require "json"
require "Octokit"

module Spike
  class SimpleApp < Sinatra::Base
    enable  :sessions
    enable  :raise_errors
    disable :show_exceptions
    enable  :inline_templates

    CLIENT_ID = ENV['GH_APP_CLIENT_ID']
    CLIENT_SECRET = ENV['GH_APP_SECRET_ID']

    # Provide authentication credentials
    Octokit.configure do |c|
      c.connection_options[:ssl] = { :verify => false }
    end

    def authenticated?
      session[:access_token]
    end

    def authenticate!
      client = Octokit::Client.new
      url = client.authorize_url CLIENT_ID, :scope => 'user:email'
      redirect url
    end

    get '/' do
      if !authenticated?
        authenticate!
      else
        access_token = session[:access_token]
        scopes = []

        client = Octokit::Client.new \
          :client_id => CLIENT_ID,
          :client_secret => CLIENT_SECRET

        begin
          client.check_application_authorization access_token
        rescue => e
          # request didn't succeed because the token was revoked so we
          # invalidate the token stored in the session and render the
          # index page so that the user can start the OAuth flow again
          session[:access_token] = nil
          return authenticate!
        end

        client = Octokit::Client.new :access_token => access_token
        data = client.user

        if client.scopes(access_token).include? 'user:email'
          data['private_emails'] = client.emails.map { |m| m[:email] }
        end

        erb :email, {:locals => data.to_attrs}
      end
    end

    get '/callback' do
      session_code = request.env['rack.request.query_hash']['code']
      result = Octokit.exchange_code_for_token(session_code, CLIENT_ID, CLIENT_SECRET)
      session[:access_token] = result[:access_token]

      redirect '/'
    end

    get '/user' do
      client = Octokit::Client.new(:access_token => session[:access_token])
      user = client.user
      user.login.to_json
    end

    # Milestones
    # https://api.github.com/repos/rogertinsley/sinatra-octokit/milestones
    get '/repos/:owner/:repo/milestone' do
      client = Octokit::Client.new(:access_token => session[:access_token])
      options = { :repo => params['repo'], :owner => params['owner'] }
      milestones = client.list_milestones options
      data = Hash.new
      milestones.each do |milestone|

        data[:title]          = milestone.title
        data[:description]    = milestone.description
        data[:created_at]     = milestone.created_at
        data[:updated_at]     = milestone.updated_at
        data[:due_on]         = milestone.due_on
        data[:html_url]       = milestone.html_url
        data[:state]          = milestone.date
        data[:open_issues]    = milestone.open_issues
        data[:closed_issues]  = milestone.closed_issues
      end
      content_type :json
      JSON.pretty_generate data
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
