Rails.application.routes.draw do
  get "widgets" => "widgets#index"
  get "widgets/bare" => "widgets#bare"
  get "widgets/policy" => "widgets#show"
  get "widgets/panel" => "widgets#panel"
end
