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
  github_oauth_token: '24ce7b9d6c039ea6210cf754ef40295f702baf81',
  github_org: 'ted-hackathon-test'
}

class GithubWebHook < Hashie::Mash
  def nbr_added
    self.commits.reduce(0) { |sum, this_commit| sum + this_commit.added.length }
  end

  def nbr_modified
    self.commits.reduce(0) { |sum, this_commit| sum + this_commit.modified.length }
  end

  def nbr_removed
    self.commits.reduce(0) { |sum, this_commit| sum + this_commit.removed.length }
  end
  
  def nbr_total
    nbr_added + nbr_modified + nbr_removed
  end
  
  def graph_item
    [ self.repository.name, self.nbr_total ]
  end
end

class Series
  # This utility class method is used in this class as well as in GithubWebHook
  def Series.get_github_commit_stats(repo_name, sha)
    warn "get details for repo: #{repo_name} sha: #{sha}"
    
    commit_details = $github.repos.commits.get($config[:github_org], repo_name, sha)
    
    commit_timestamp = Time.iso8601(commit_details.commit.author['date']).utc
    commit_net_lines_added = commit_details.stats.additions - commit_details.stats.deletions
    
    return commit_timestamp, commit_net_lines_added
  end
  
  # Return array of strings, containing series names
  def series_names
    $github.repos.list(org: $config[:github_org], per_page: 100).map &:name
    #('team01'..'team05').to_a
  end
  
  # Returns the data set for one series.
  # We actually display the date in local time, but the data is provided to the browser as UTC, as ms since UTC epoch
  def data_for_series(repo_name)
    $github.repos.commits.list($config[:github_org], repo_name).sort_by { |this_commit|
      Time.iso8601(this_commit.commit.author['date']).to_i
    }.reduce([]) { |agg, this_commit|
      # Get the commit details
      commit_timestamp, commit_net_lines_added = Series.get_github_commit_stats(repo_name, this_commit.sha)

      # Do our math to calculate the net lines added in this commit
      previous_total_lines = agg[-1][1] rescue 0
      commit_total_lines = previous_total_lines + commit_net_lines_added
      
      # Emit a data point from our reduce method
      # Note: Javascript's "new Date()" call wants milliseconds since Unix epoch, in UTC
      agg << [ commit_timestamp.to_i * 1000, commit_total_lines ]
      puts agg.inspect
      agg
    }
  end
  
  # useful for development
  def random_data_for_series(repo_name)
    [
      [(Time.now.utc - rand(5000)).to_i * 1000, rand(100)],
      [(Time.now.utc - rand(5000)).to_i * 1000, rand(100)],
      [(Time.now.utc - rand(5000)).to_i * 1000, rand(100)],
      [(Time.now.utc - rand(5000)).to_i * 1000, rand(100)]
    ].sort_by { |x| x[0] }
  end
  
  def all_series_data
    self.series_names.map do |this_name|
      [this_name, data_for_series(this_name)]
    end
  end
end

$series = Series.new
$github = Github.new oauth_token: $config[:github_oauth_token]
$sockets = []

EventMachine.run do
  class App < Sinatra::Base
    get '/' do
      haml :websocket
    end
    
    get '/all.json' do
      content_type 'application/json'
      $series.all_series_data.to_json
    end
    
    post '/github' do
      warn "from github: #{params[:payload]}"
      payload = GithubWebHook.new JSON.parse(params[:payload])
      #debugger
      warn "+%s -%s /%s" % [ payload.nbr_added, payload.nbr_removed, payload.nbr_modified ]
      
      $sockets.each { |s| s.send payload.graph_item.to_json }
      ''
    end
    
    post '/pushdebug' do
      # e.g. curl -4 -v -d 'payload=["team01", [1344823587000, 42]]' tedb.us:3002/pushdebug
      $sockets.each { |s| s.send params[:payload] }
      ''
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

@@websocket

!!!
%head
  %title Hackadash: SPARC Hackathon 2.0!
  %script(src="https://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.min.js")
  %script(src="/highcharts.js")
  
  :javascript
    var socket = new WebSocket('ws://#{ $config[:websocket_url_hostname] }:#{ $config[:websocket_port] }');

    socket.onopen = function (e) {
      $('#notifications').append("<li>-- WebSocket onopen!</li>");
    };

    socket.onmessage = function (e) {
      $('#notifications').append("<li>From server: " + e.data + "</li>");
      server_point = JSON.parse(e.data);
      series = chart1.get('series_' + server_point[0]);
      series.addPoint(server_point[1]);
    };

    socket.onclose = function(e) {
      $('#notifications').append("<li>-- WebSocket onclose!</li>");
    };
    
    function initial_chart_data() {
      $.ajax({
        url: 'all.json',
        cache: false,
        // resulting JSON is automatically parsed
        success: function(server_series_set) {
          
          server_series_set.forEach(function(this_server_series) {
            // Add this series to the chart, without redrawing the chart
            chart1.addSeries({
              id: 'series_' + this_server_series[0],
              name: this_server_series[0],
              data: this_server_series[1]
            }, false);
          })

          chart1.redraw();
          
        }
      });
    }
    
    var chart1; // globally available
    $(document).ready(function() {
      Highcharts.setOptions({
        global: {
          useUTC: false
        }
      });
      
      chart1 = new Highcharts.Chart({
         chart: {
            renderTo: 'chart_container',
            type: 'line',
            zoomType: 'x',
            events: {
              load: initial_chart_data
            }
         },
         credits: {
           enabled: false
         },
         title: {
            text: 'Git repository code volume by team'
         },
         xAxis: {
            type: 'datetime',
            tickPanelInterval: 150,
            title: {
              text: 'Time'
            }
         },
         yAxis: {
            min: 0,
            title: {
               text: 'Total lines of code'
            }
         },
         series: []
      });
    });
%body    
  #chart_container(style="width: 100%; height: 400px")
  
  / Received Websocket messages will be inserted into this list
  %ul#notifications
  