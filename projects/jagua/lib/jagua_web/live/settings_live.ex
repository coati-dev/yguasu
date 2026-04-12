defmodule JaguaWeb.Live.SettingsLive do
  use JaguaWeb, :live_view

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Account settings")}
  end

  @impl true
  def handle_event("delete_account", _params, socket) do
    user = socket.assigns.current_user

    Ash.destroy!(user, domain: Jagua.Accounts)

    {:noreply,
     socket
     |> put_flash(:info, "Your account has been deleted.")
     |> push_navigate(to: ~p"/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold text-gray-900 mb-8">Account settings</h1>

      <div class="bg-white rounded-xl border border-gray-200 p-6 mb-4">
        <h2 class="text-sm font-semibold text-gray-900 mb-3">Your account</h2>
        <p class="text-sm text-gray-600"><%= @current_user.email %></p>
      </div>

      <div class="bg-white rounded-xl border border-red-200 p-6">
        <h2 class="text-sm font-semibold text-red-700 mb-2">Danger zone</h2>
        <p class="text-sm text-gray-500 mb-4">
          Permanently delete your account. All projects, sentinels, and data will be removed. This cannot be undone.
        </p>
        <button
          phx-click="delete_account"
          data-confirm="Delete your account and all your data? This cannot be undone."
          class="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700"
        >
          Delete account
        </button>
      </div>
    </div>
    """
  end
end
