# Run this with:  gem install god; god -c hackadash.god.rb

God.watch do |w|
  w.name = 'Hackadash'
  w.start = "ruby1.9 app.rb"
  w.keepalive :memory_max => 400.megabytes
  w.env = { 'GITHUB_OAUTH' => 'fixme' }
  w.dir = '/home/hackadash/hackadash'
end