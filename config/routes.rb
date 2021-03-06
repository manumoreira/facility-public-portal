Rails.application.routes.draw do
  devise_for :users

  as :user do
    get 'users/edit' => 'users/registrations#edit', :as => 'edit_user_registration'
    put 'users' => 'users/registrations#update', :as => 'user_registration'
  end

  root to: "content_view#landing"

  get 'docs', to: 'content_view#docs'

  scope :content do
    root to: "content_edition#edit"
    get  ':edit_locale/edit', to: 'content_edition#edit'
    post ':edit_locale/edit', to: 'content_edition#save'
    get  ':edit_locale/preview', to: 'content_edition#preview'
    post ':edit_locale/publish_draft', to: 'content_edition#publish_draft'
    post ':edit_locale/discard_draft', to: 'content_edition#discard_draft'
  end

  scope :datasets do
    root to: "datasets#index"
    post 'import', to: 'datasets#import'
    post 'import_ona', to: 'datasets#import_ona'
    post 'upload', to: 'datasets#upload'
    get 'download/:filename', to: 'datasets#download'
  end

  scope :api do
    get 'search', to: 'api#search'
    get 'dump', to: 'api#dump'
    get 'suggest', to: 'api#suggest'
    get 'facilities/:id', to: 'api#get_facility'
    get 'facility_types', to: 'api#facility_types'
    get 'locations', to: 'api#locations'
    get 'categories', to: 'api#categories'
  end

  post 'facilities/:id/report', to: 'application#report_facility'
  get 'map', to: 'application#map'

  get '*unmatched_route', :to => 'application#map'
end
