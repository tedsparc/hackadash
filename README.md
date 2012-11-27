hackadash
=========

Deploying (Amazon Linux based): -- NEEDS TESTING, might require small refinements

    sudo -i
    yum install -y rubygems19 ruby19 ruby19-devel rubygem19-rdoc rubygem19-rake rubygem19-json ruby19-irb ruby19-libs rubygem19-rdoc gcc make git nginx gcc-c++ libxml2-devel libxslt-devel 
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

    ln -s /usr/local/share/gems/gems/god-*/bin/god /usr/local/bin/god
    su - hackadash
    git clone git://example.com/hackadash.git
    cd hackadash
    bundle install
    mkdir -p cache/commits logs
    /usr/local/bin/god -c hackadash.god.rb

