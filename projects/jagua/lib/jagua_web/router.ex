defmodule JaguaWeb.Router do
  use JaguaWeb, :router

  import JaguaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JaguaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug :require_authenticated_user
  end

  # --- Public routes ---
  scope "/", JaguaWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Check-in endpoint — no auth, token is the credential
    get "/in/:token", CheckInController, :check_in
    post "/in/:token", CheckInController, :check_in

    # Auth callbacks (controller-based — user follows link from email)
    get "/auth/confirm/:token", AuthController, :confirm
    delete "/auth/logout", AuthController, :logout

    # Public status page — own live_session so the socket is properly signed
    live_session :public,
      on_mount: [{JaguaWeb.UserAuth, :fetch_current_user}] do
      live "/status/:slug", Live.StatusPageLive, :show
    end

    # Login page (LiveView — redirects away if already logged in)
    live_session :auth,
      on_mount: [{JaguaWeb.UserAuth, :redirect_if_authenticated}] do
      live "/login", Live.LoginLive, :index
    end
  end

  # --- Protected LiveView routes ---
  scope "/", JaguaWeb do
    pipe_through [:browser, :require_auth]

    live_session :authenticated,
      on_mount: [{JaguaWeb.UserAuth, :ensure_authenticated}] do
      live "/dashboard", Live.DashboardLive, :index
      live "/projects/new", Live.ProjectLive.New, :new
      live "/projects/:slug", Live.ProjectLive.Show, :index
      live "/projects/:slug/sentinels/new", Live.SentinelLive.New, :new
      live "/projects/:slug/sentinels/:token", Live.SentinelLive.Show, :show
      live "/projects/:slug/settings", Live.ProjectLive.Settings, :settings
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:jagua, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JaguaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
