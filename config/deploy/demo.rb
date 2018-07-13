# frozen_string_literal: true

server 'sul-arclight-demo.stanford.edu', user: 'arclight', roles: %w[web db app]

Capistrano::OneTimeKey.generate_one_time_key!
set :rails_env, 'production'
