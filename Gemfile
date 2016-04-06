# Allow a comma or space-delimited list of gem servers
if simp_gem_server =  ENV.fetch( 'SIMP_GEM_SERVERS', false )
  simp_gem_server.split( / |,/ ).each{ |gem_server|
    source gem_server
  }
end
source 'https://rubygems.org'

gem 'dotenv'
gem 'rest-client'
gem 'highline'
