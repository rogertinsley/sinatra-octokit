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

      stack = Faraday::RackBuilder.new do |builder|
        builder.response :logger
        builder.use Octokit::Response::RaiseError
        builder.adapter Faraday.default_adapter
      end
      Octokit.middleware = stack
      Octokit.user 'rogertinsley'
    end

    def authenticated?
      session[:access_token]
    end

    def authenticate!
      client = Octokit::Client.new
      url = client.authorize_url CLIENT_ID, :scope => 'user:email, repo'
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
      data = Array.new
      milestones.each do |milestone|
        hash = Hash.new
        hash[:title]          = milestone.title
        hash[:description]    = milestone.description
        hash[:created_at]     = milestone.created_at
        hash[:updated_at]     = milestone.updated_at
        hash[:due_on]         = milestone.due_on
        hash[:html_url]       = milestone.html_url
        hash[:state]          = milestone.date
        hash[:open_issues]    = milestone.open_issues
        hash[:closed_issues]  = milestone.closed_issues

        data.push(hash)
      end
      content_type :json
      JSON.pretty_generate data
    end

    get '/repos/:owner/:repo/milestone/create' do
      erb :create_milestone, :locals => { :repo => params['repo'], :owner => params['owner'] }
    end

    post '/repos/:owner/:repo/milestone/create' do
      client = Octokit::Client.new(:access_token => session[:access_token])
      repo = { :repo => params['repo'], :owner => params['owner'] }
      response = client.create_milestone repo, params['title'], { :description  => params['description']  }
      headers["Location"] = response.url
      status 201 # Created
    end

    # Issues
    # https://api.github.com/repos/rogertinsley/sinatra-octokit/issues
    get '/repos/:owner/:repo/issues' do
      client = Octokit::Client.new(:access_token => session[:access_token])
      options = { :repo => params['repo'], :owner => params['owner'] }
      issues = client.list_issues options
      data = Array.new
      issues.each do |issue|
        hash = Hash.new
        hash[:html_url]   = issue.html_url
        hash[:number]     = issue.number
        hash[:title]      = issue.title
        hash[:state]      = issue.state
        hash[:assignee]   = issue.assignee
        hash[:milestone]  = issue.milestone
        hash[:comments]   = issue.comments
        hash[:created_at] = issue.created_at
        hash[:updated_at] = issue.updated_at
        hash[:body]       = issue.body

        data.push(hash)
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
