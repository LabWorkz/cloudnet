require 'dotenv'
Dotenv.load

lock '3.2.1'

set :application, 'cloudnet'
set :deploy_user, 'deploy'
set :rails_env, 'production'
set :repo_url, ENV['GIT_ORIGIN']
set :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }
set :scm, :git

set :deploy_to, '/apps/cloudnet'

# Default value for :format is :pretty
set :format, :pretty

# Default value for :log_level is :debug
# set :log_level, :debug

# Default value for :pty is false
# set :pty, true

# Puma related config variables
set :puma_threads, [4, 8]
set :puma_workers, 4
set :puma_preload_app, true
set :puma_init_active_record, false

set :config_files, %w(.env)
set :linked_files, %w(.env)
set :linked_dirs, %w(bin log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system)

set :keep_releases, 10

set :whenever_roles, -> { :app }

before 'deploy:check:linked_files', 'config:push' unless ENV['CI']
before 'deploy:restart', 'puma:config'
after 'deploy', 'deploy:restart'

namespace :deploy do

  desc "Restart using Puma's Phased Restart"
  task :restart do
    'puma:phased-restart'
  end

  desc 'Seed application data'
  task :seed do
    on roles(:app), in: :sequence, wait: 5 do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, 'db:seed'
        end
      end
    end
  end

  # desc 'Delete cached minified Javascript'
  # task :remove_cached_js do
  #   on roles(:app), in: :sequence, wait: 5 do
  #     within release_path do
  #       with rails_env: fetch(:rails_env) do
  #         execute :rake, "deploy:remove_cached_js"
  #       end
  #     end
  #   end
  # end
end

# after "deploy", "deploy:remove_cached_js"

namespace :maintenance do
  desc 'Enter maintenance mode on the website'
  task :start do
    on roles(:app), in: :sequence, wait: 5 do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, 'maintenance:start'
        end
      end
    end
  end

  desc 'End maintenance mode on the website'
  task :end do
    on roles(:app), in: :sequence, wait: 5 do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, 'maintenance:end'
        end
      end
    end
  end
end
