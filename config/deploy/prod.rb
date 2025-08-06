# frozen_string_literal: true

server 'sul-arclight-prod-a.stanford.edu', user: 'arclight', roles: %w[web db app]
server 'sul-arclight-prod-b.stanford.edu', user: 'arclight', roles: %w[web app]
server 'sul-arclight-worker-prod-a.stanford.edu', user: 'arclight', roles: %w[background]
server 'sul-arclight-worker-prod-b.stanford.edu', user: 'arclight', roles: %w[background]

Capistrano::OneTimeKey.generate_one_time_key!
set :rails_env, 'production'
set :sidekiq_roles, :background
