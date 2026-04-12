defmodule JaguaWeb.Live.LoginLive do
  use JaguaWeb, :live_view

  alias Jagua.Accounts.Auth

  on_mount {JaguaWeb.UserAuth, :redirect_if_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{"email" => ""}), sent: false, page_title: "Sign in")}
  end

  @impl true
  def handle_event("submit", %{"email" => email}, socket) do
    email = String.trim(email)

    if valid_email?(email) do
      Auth.request_magic_link(email)
      {:noreply, assign(socket, sent: true, email: email)}
    else
      {:noreply, put_flash(socket, :error, "Please enter a valid email address.")}
    end
  end

  defp valid_email?(email), do: String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 flex items-center justify-center px-4 py-8">
      <div class="w-full max-w-sm">
        <div class="rounded-xl border border-gray-200 shadow-sm p-8">
          <%= if @sent do %>
            <div class="text-center">
              <div class="text-3xl mb-4">📬</div>
              <h2 class="text-lg font-semibold text-gray-900 mb-2">Check your inbox</h2>
              <p class="text-sm text-gray-500">
                We sent a login link to <strong><%= @email %></strong>.
                It expires in 15 minutes.
              </p>
              <button
                phx-click="submit"
                phx-value-email={@email}
                class="mt-6 text-sm text-gray-400 hover:text-gray-600 underline"
              >
                Resend link
              </button>
            </div>
          <% else %>
            <h2 class="text-lg font-semibold text-gray-900 mb-1">Sign in</h2>
            <p class="text-sm text-gray-500 mb-6">No account? Just sign in to register.</p>
            <.form for={@form} phx-submit="submit">
              <div class="mb-4">
                <label for="email" class="block text-sm font-medium text-gray-700 mb-1">
                  Email address
                </label>
                <input
                  type="email"
                  name="email"
                  id="email"
                  placeholder="you@example.com"
                  autocomplete="email"
                  required
                  class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
                />
              </div>
              <button
                type="submit"
                class="w-full bg-gray-900 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-gray-700 transition-colors"
              >
                Send login link
              </button>
            </.form>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
