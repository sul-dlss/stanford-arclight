# frozen_string_literal: true

set :application, 'stanford-arclight'
set :repo_url, 'https://github.com/sul-dlss/stanford-arclight.git'

# Default branch is :master so we need to update to main
if ENV['DEPLOY']
  set :branch, 'main'
else
  ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }.call
end

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, '/opt/app/arclight/arclight'
# set :deploy_to, '/var/www/my_app_name'

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: 'log/capistrano.log', color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
set :linked_files, %w[config/database.yml config/blacklight.yml config/honeybadger.yml]

# Default value for linked_dirs is []
set :linked_dirs, %w[config/settings log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system]

set :honeybadger_env, fetch(:stage)
# Default value for default_env is {}
# set :default_env, { path: '/opt/ruby/bin:$PATH' }

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5

# Uncomment the following to require manually verifying the host key before first deploy.
# set :ssh_options, verify_host_key: :secure

# Allow dlss-capistrano to manage sidekiq via systemd
set :sidekiq_systemd_use_hooks, true

namespace :deploy do
  after :restart, :clear_cache do
    on roles(:web), in: :groups, limit: 3, wait: 10 do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, 'tmp:cache:clear'
        end
      end
    end
  end
end

# update shared_configs before restarting app
before 'deploy:restart', 'shared_configs:update'
