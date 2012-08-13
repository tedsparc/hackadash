require 'github_api'

# to get an oauth token:   curl -u tedsparc -d '{"scopes": ["repo", "user"], "note":"dev test for hackadash, 2"}' https://api.github.com/authorizations
github = Github.new oauth_token: '24ce7b9d6c039ea6210cf754ef40295f702baf81'

github.orgs.list do |org|
  next unless org.login == 'ted-hackathon-test'
  puts org.login
  
  github.repos.list(user: org.login, per_page: 100) do |repo|
    puts "  " + repo.name
    
    github.repos.commits.list(org.login, repo.name) do |commit|
      puts "    " + commit.sha
      details = github.repos.commits.get(org.login, repo.name, commit.sha)
      puts "      author date: " + details.commit.author['date']
      puts "      net added: " + (details.stats.additions - details.stats.deletions).to_s
    end
  end
end
