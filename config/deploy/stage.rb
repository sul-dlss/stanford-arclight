# frozen_string_literal: true

server 'sul-arclight-stage-a.stanford.edu', user: 'arclight', roles: %w[web db app]
server 'sul-arclight-stage-b.stanford.edu', user: 'arclight', roles: %w[web app]

Capistrano::OneTimeKey.generate_one_time_key!
set :rails_env, 'production'
