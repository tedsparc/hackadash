require 'github_api'
require 'em-synchrony'
require 'pp'

$ORG = 'my-hackathon-2-0'
$WEBHOOK_URL = 'http://hackadash.example.com/github'

# to get an oauth token:   curl -u MY_GITHUB_USERNAME -d '{"scopes": ["repo", "user"], "note":"dev test for hackadash, 2"}' https://api.github.com/authorizations
$github = Github.new adapter: :em_synchrony, oauth_token: ENV['GITHUB_OAUTH'] || raise(ArgumentError, "Must specify env var GITHUB_OAUTH")                     

#$team_list = ("team01".."team30")
$team_list = ['team99']

case ARGV[0]
when 'setup'
  puts "Setting up repos for #{$ORG}..."
  $team_list.each do |this_team|
    begin                    
      warn "Creating repo for #{this_team}..."
      $github.repos.create name: this_team,
                          org: $ORG,
                          description: "My Hackathon 2.0: #{this_team}",
                          private: true,
                          homepage: "http://hackathon.example.com", 
                          has_wiki: false,
                          has_downloads: false,
                          has_issues: false
       
      warn "Creating team #{this_team}..."
      $github.orgs.teams.create $ORG, name: this_team, permission: "push", repo_names: [ "#{$ORG}/#{this_team}"]
                   
      warn "Creating repo hook for #{this_team}..."
      $github.repos.hooks.create $ORG, this_team, name: "web",
                                                 active: true,
                                                 config: { url: $WEBHOOK_URL }
    rescue Github::Error::UnprocessableEntity => e
      warn "Github error for #{this_team} => #{e}"
    end
  end
else
  puts "Listing repos for #{$ORG}..."
  $github.repos.list(org: $ORG, per_page: 100) do |this_repo|
    puts "Repo: " + this_repo.name
    
    teams = $github.repos.teams($ORG, this_repo.name)
    teams.each do |this_team|
      members = $github.orgs.teams.list_members(this_team.id)
      member_list = members.map(&:login).sort.join(', ')
      member_list = '-none-' if member_list.empty?

      puts "  Team: #{this_team.name} (#{this_team.permission}); members: #{member_list}"
    end
  end
end


__END__
github.orgs.list do |org|
  next unless org.login == 
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
