defmodule X12TranslatorWeb.Router do
  use X12TranslatorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {X12TranslatorWeb.Layouts, :root}
    plug :put_layout, html: {X12TranslatorWeb.Layouts, :app}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", X12TranslatorWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/converter", BatchLiveEnhanced
  end

  # Other scopes may use custom stacks.
  # scope "/api", X12TranslatorWeb do
  #   pipe_through :api
  # end
end
