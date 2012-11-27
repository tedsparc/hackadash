hackadash
=========

Deploying (Amazon Linux based):

    sudo -i
    yum install -y git rubygems19 ruby19 ruby19-devel rubygem19-rdoc rubygem19-rake rubygem19-json ruby19-irb ruby19-libs rubygem19-rdoc gcc make git nginx gcc-c++ libxml2-devel libxslt-devel 
    useradd hackadash
    gem1.9 install rdoc bundler god rake json 

    cat > /etc/nginx/conf.d/hackadash.conf <<END
    server {
        listen 80;
        server_name hackadash.example.com;
        location / {
          proxy_pass   http://127.0.0.1:3002;
        }
    
        # only allow Github's public IP's to post to webhook endpoint
        location /github {
          proxy_pass   http://127.0.0.1:3002/github;
          allow 207.97.227.253;
          allow 50.57.128.197;
          allow 108.171.174.178;
          deny all;
        }
    }
    END

    # ln -s /usr/local/share/gems/gems/god-*/bin/god /usr/local/bin/god
    su - hackadash
    git clone git://example.com/hackadash.git
    cd hackadash
    bundle install
    /usr/local/bin/god -c hackadash.god.rb
    exit
    
    # back to root
    service nginx start
    chkconfig nginx on

Other things to do:

- Get a Github OAuth token: 

    curl -u MY_GITHUB_USERNAME -d '{"scopes": ["repo", "user"], "note":"dev test for hackadash, 2"}' https://api.github.com/authorizations
    
- Edit "hackadash.god.rb" to insert your Github token where it says "fixme"

- Edit "app.rb" to set your hostname and Github organization in the $config hash

- Make sure your server is reachable on port 80 (HTTP) and 3003 (Websockets)
