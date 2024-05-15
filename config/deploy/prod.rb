# frozen_string_literal: true

server 'sul-arclight-prod-a.stanford.edu', user: 'arclight', roles: %w[web db app]
server 'sul-arclight-prod-b.stanford.edu', user: 'arclight', roles: %w[web app]

Capistrano::OneTimeKey.generate_one_time_key!
set :rails_env, 'production'
