# frozen_string_literal: true

require 'sidekiq/web'

# rubocop:disable Metrics/BlockLength
Rails.application.routes.draw do
  concern :range_searchable, BlacklightRangeLimit::Routes::RangeSearchable.new
  mount Blacklight::Engine => '/'
  mount BlacklightDynamicSitemap::Engine => '/'

  mount Arclight::Engine => '/'
  mount Sidekiq::Web => '/sidekiq'

  root 'landing_page#index'
  concern :searchable, Blacklight::Routes::Searchable.new

  resource :catalog, only: [], as: 'catalog', path: '/catalog', controller: 'catalog' do
    concerns :searchable
    concerns :range_searchable
  end
  devise_for :users

  concern :exportable, Blacklight::Routes::Exportable.new
  concern :hierarchy, Arclight::Routes::Hierarchy.new

  resources :solr_documents, only: [:show], path: '/catalog', controller: 'catalog' do
    concerns :hierarchy
    concerns :exportable
  end

  resources :bookmarks do
    concerns :exportable

    collection do
      delete 'clear'
    end
  end

  get '/download/:id' => 'download#show'

  get '/search_tips' => 'catalog#search_tips'

  get '/using-this-site' => 'using_this_site#index'

  # Match ARKs that contain:
  # - a repository shoulder (one letter followed by one digit)
  # - a UUID (with or without hyphens)
  # In the ARK spec, strings that differ only by hyphens are considered identical
  # rubocop :disable Layout/LineLength
  get '/findingaid/*ark_id', to: 'finding_aids#resolve', as: :findingaid,
                             constraints: lambda { |req|
                               req.params[:ark_id] =~ %r{\Aark:/#{Settings.ark_naan}/[a-z]\d(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\z}i
                             }
  # rubocop :enable Layout/LineLength

  resource :feedback, only: :create

  # Cloudflare turnstile bot challenges via bot_challenge_page gem
  post '/challenge', to: 'bot_challenge_page/bot_challenge_page#verify_challenge', as: :bot_detect_challenge

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
end
# rubocop:enable Metrics/BlockLength
