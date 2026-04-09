defmodule OpenDriveWeb.Router do
  use OpenDriveWeb, :router

  import OpenDriveWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug OpenDriveWeb.Locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {OpenDriveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", OpenDriveWeb do
    pipe_through :browser

    get "/up", HealthController, :show
    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", OpenDriveWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:open_drive, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OpenDriveWeb.Telemetry
    end
  end

  ## Authentication routes

  scope "/", OpenDriveWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {OpenDriveWeb.Locale, :default},
        {OpenDriveWeb.UserAuth, :require_authenticated}
      ] do
      live "/app", DriveLive.Index, :index
      live "/app/folders/:folder_id", DriveLive.Index, :index
      live "/app/trash", TrashLive.Index, :index
      live "/app/members", MembersLive.Index, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
    post "/app/switch-tenant", TenantSessionController, :update
    post "/app/folders/upload", FolderUploadController, :create
    post "/app/uploads", DirectUploadController, :create
    post "/app/uploads/proxy", DirectUploadController, :proxy
    post "/app/uploads/complete", DirectUploadController, :complete
    get "/app/files/:id/download", FileDownloadController, :show
    post "/app/files/download-zip", FileDownloadController, :zip
  end

  scope "/", OpenDriveWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [
        {OpenDriveWeb.Locale, :default},
        {OpenDriveWeb.UserAuth, :mount_current_scope}
      ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
