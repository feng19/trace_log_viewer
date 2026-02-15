defmodule TraceLogViewerWeb.Router do
  use TraceLogViewerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TraceLogViewerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", TraceLogViewerWeb do
    pipe_through :browser

    live "/", TraceLogLive
  end
end
