# frozen_string_literal: true

require 'sidekiq/web'

Rails.application.routes.draw do
  mount Blacklight::Engine => '/'
  mount Arclight::Engine => '/'
  mount Sidekiq::Web => '/sidekiq'

  root to: 'arclight/repositories#index'
  concern :searchable, Blacklight::Routes::Searchable.new

  resource :catalog, only: [:index], as: 'catalog', path: '/catalog', controller: 'catalog' do
    concerns :searchable
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

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
end
