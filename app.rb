require 'eventmachine'
require 'em-websocket'
require 'em-http-request'
require 'sinatra/base'
require 'thin'
require 'haml'
require 'hashie'
require 'json'
require 'time'
require 'github_api'
#require 'debugger'

$config = {
  http_port: 3002,
  websocket_listen_host: '0.0.0.0',
  websocket_port: 3003,
  websocket_url_hostname: 'tedb.us',
  github_oauth_token: ENV['GITHUB_OAUTH'] || raise(ArgumentError, "Must specify env var GITHUB_OAUTH"),
#  github_org: 'ted-hackathon-test'
#  github_org: 'sparc-hackathon-2-0'
  github_org: 'sparcedge'
}

class GithubWebHook < Hashie::Mash
end

class Time
  # Convert time to milliseconds since UTC epoch, for use by Javascript
  def to_utc_ms
    self.utc.to_i * 1000
  end
end

class SeriesSet
  attr_accessor :github_org, :github_handle, :series_set
  
  def initialize(github_org, github_oauth_token)
    @series_set = []
    @github_org = github_org
    @github_handle = Github.new oauth_token: github_oauth_token
    
    fetch_repo_list.sort_by { |r| r.name }.each do |this_repo|
      @series_set << RepoDataSeries.new(self, this_repo.name)
    end
  end
  
  def fetch_repo_list
    self.github_handle.repos.list(org: self.github_org, per_page: 100)
  end
  
  def series_names
    self.series_set.map(&:name).sort
  end
  
  def [](query_repo_name)
    self.series_set.select { |repo| repo.name == query_repo_name }.first
  end
  
  # Returns data ready for injesting into Highcharts
  def all_data
    self.series_names.map do |this_name|
      [this_name, self[this_name].data_series]
    end
  end
  
  # Hand off the Github web hook data to whichever RepoDataSeries is responsible
  def handle_github_web_hook(github_post_data)
    self[github_post_data.repository.name].handle_github_web_hook(github_post_data)
  end
  
  class RepoDataSeries
    attr_accessor :parent, :name, :data_series, :latest_broadcast
    
    def initialize(parent, repo_name)
      @parent = parent
      @name = repo_name
      @data_series = data_for_series
    end
    
    def github
      self.parent.github_handle
    end
    
    def fetch_commits_for_repo
      begin
        self.github.repos.commits.list(self.parent.github_org, self.name).sort_by { |this_commit|
          # Just used for sorting
          Time.iso8601(this_commit.commit.author['date']).to_i
        }
      rescue Github::Error::ServiceError => e
        warn "Github error in RepoDataSeries#fetch_commits_for_repo: #{e}"
        return []
      end
    end
    
    # This utility class method is used in this class as well as in GithubWebHook
    def fetch_stats_for_commit(sha)
      warn "get details for repo: #{self.name} sha: #{sha}"
    
      cache_key = '%s_%s_%s' % [self.parent.github_org, self.name, sha]
      commit_details = simple_cache(cache_key) do
        self.github.repos.commits.get(self.parent.github_org, self.name, sha)
      end
    
      commit_timestamp = Time.iso8601(commit_details.commit.author['date']).utc
      warn "stats: #{commit_details.stats.to_json}"
      commit_net_lines_added = commit_details.stats.additions - commit_details.stats.deletions
    
      return commit_timestamp, commit_net_lines_added
    end
  
    # Returns the data set for one series; only used upon object initialization
    # We actually display the date in local time, but the data is provided to the browser as UTC, as milliseconds since UTC epoch
    def data_for_series
      now_ms = Time.now.to_utc_ms
      data = fetch_commits_for_repo.reduce([]) { |agg, this_commit|
        # Get the commit details
        commit_timestamp, commit_net_lines_added = fetch_stats_for_commit(this_commit.sha)

        # Do our math to calculate the net lines added in this commit
        previous_total_lines = agg[-1][1] rescue 0
        commit_total_lines = previous_total_lines + commit_net_lines_added
      
        # Emit a data point from our reduce method
        # Note: Javascript's "new Date()" call wants milliseconds since Unix epoch, in UTC
        agg << [ commit_timestamp.to_utc_ms, commit_total_lines ]
        puts agg.inspect
        agg
      }
      
      # If there are no Github commits, make a fake entry so we get something on the chart
      data = [[now_ms, 0]] if data.empty?
      
      # Make the data lie such that there is never a 0 or negative (these interfere with the logarithmic Y-axis)
      data.map! { |x| x[1] = 1 unless x[1] > 0; x }
      data
    end
    
    # injest a new Github web hook object
    # look up the commit using the Github API
    # Return data suitable for sending to Websocket clients for injest by Highcharts
    def handle_github_web_hook(github_post_data)
      self.latest_broadcast = []
      
      github_post_data.commits.each do |this_commit|
        warn "Handling Github commit notification for repo #{self.name}: #{this_commit.id}"
        commit_timestamp, commit_net_lines_added = fetch_stats_for_commit(this_commit.id)
        data_point = [ commit_timestamp.to_utc_ms, data_series[-1][1] + commit_net_lines_added ]
        
        warn "data point: #{data_point.to_json}"
        self.data_series << data_point
        self.latest_broadcast << [self.name, data_point]
      end
    
      return self.latest_broadcast
    end
      
    # useful for development
    def random_data_for_series()
      [
        [(Time.now.utc - rand(5000)).to_utc_ms, rand(100)],
        [(Time.now.utc - rand(5000)).to_utc_ms, rand(100)],
        [(Time.now.utc - rand(5000)).to_utc_ms, rand(100)],
        [(Time.now.utc - rand(5000)).to_utc_ms, rand(100)]
      ].sort_by { |x| x[0] }
    end
    
    def simple_cache(key, &block)
      raise ArgumentError.new("Must Supply Block") unless block_given?
      cache_dir = './cache/commits/'
      filename = cache_dir + key
      begin
        Marshal.load(File.read(filename))
      rescue
        result = yield block
        begin
          File.open(filename, 'w') { |f| f.write Marshal.dump(result) }
        rescue StandardError => e
          warn "Couldn't write cache file: #{e}"
        end
        result
      end
    end
  end
end

$series_set = SeriesSet.new($config[:github_org], $config[:github_oauth_token])
$sockets = []

EventMachine.run do
  class App < Sinatra::Base
    get '/' do
      haml :index
    end
    
    get '/all.json' do
      content_type 'application/json'
      $series_set.all_data.to_json
    end
    
    post '/github' do
      warn "from github: #{params[:payload]}"
      payload = $series_set.handle_github_web_hook GithubWebHook.new JSON.parse(params[:payload])
      warn "sending payload #{payload.to_json}"
      #debugger
      
      $sockets.each { |s| s.send payload.to_json }
      'OK'
    end
    
    post '/pushdebug' do
      # e.g. curl -4 -v -d 'payload=["team01", [1344823587000, 42]]' tedb.us:3002/pushdebug
      $sockets.each { |s| s.send params[:payload] }
      'OK'
    end
    
    enable :inline_templates
  end
  
  EventMachine::WebSocket.start(host: $config[:websocket_listen_host], port: $config[:websocket_port]) do |socket|
    socket.onopen do
      warn "onopen fired"
      $sockets << socket
      
      # replace with sending down all the data gathered so far
      socket.send "Hello there!"
    end
    #socket.onmessage do |mess|
    #  warn "onmessage fired with #{mess}"
    #  $sockets.each {|s| s.send mess}
    #end
    socket.onclose do
      warn "onclose"
      $sockets.delete socket
    end
  end
  
  App.run! port: $config[:http_port]
end

__END__
