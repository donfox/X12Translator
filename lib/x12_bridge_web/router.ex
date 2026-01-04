defmodule X12BridgeWeb.Router do
  use X12BridgeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {X12BridgeWeb.Layouts, :root}
    plug :put_layout, html: {X12BridgeWeb.Layouts, :app}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", X12BridgeWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/converter", ConverterLive
    live "/batch", BatchLive
    live "/batch/enhanced", BatchLiveEnhanced
  end

  # Other scopes may use custom stacks.
  # scope "/api", X12BridgeWeb do
  #   pipe_through :api
  # end
end
