defmodule JaguaWeb.Live.ProjectLive.Settings do
  use JaguaWeb, :live_view

  require Ash.Query

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case load_project(slug) do
      {:ok, project} ->
        channels = load_channels(project.id)

        {:ok,
         assign(socket,
           project: project,
           status_url: status_url(slug),
           channels: channels,
           # nil | :email | :telegram | :webhook
           adding_channel: nil,
           new_channel_name: "",
           new_channel_config: %{}
         )}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  defp load_project(slug) do
    query =
      Jagua.Projects.Project
      |> Ash.Query.for_read(:by_slug, %{slug: slug})

    case Ash.read_one(query, domain: Jagua.Projects) do
      {:ok, nil} -> :error
      {:ok, p} -> {:ok, p}
      _ -> :error
    end
  end

  defp load_channels(project_id) do
    Jagua.Alerts.AlertChannel
    |> Ash.Query.for_read(:all_for_project, %{project_id: project_id})
    |> Ash.read!(domain: Jagua.Alerts)
  end

  defp status_url(slug), do: JaguaWeb.Endpoint.url() <> "/status/#{slug}"

  @impl true
  def handle_event("toggle_status_page", _params, socket) do
    project = socket.assigns.project
    new_val = !project.public_status_page

    updated =
      project
      |> Ash.Changeset.for_update(:update, %{public_status_page: new_val})
      |> Ash.update!(domain: Jagua.Projects)

    {:noreply, assign(socket, project: updated)}
  end

  @impl true
  def handle_event("delete_project", _params, socket) do
    Ash.destroy!(socket.assigns.project, domain: Jagua.Projects)

    {:noreply,
     socket
     |> put_flash(:info, "Project deleted.")
     |> push_navigate(to: ~p"/dashboard")}
  end

  @impl true
  def handle_event("show_add_channel", %{"type" => type}, socket) do
    {:noreply,
     assign(socket,
       adding_channel: String.to_existing_atom(type),
       new_channel_name: "",
       new_channel_config: %{}
     )}
  end

  @impl true
  def handle_event("cancel_add_channel", _params, socket) do
    {:noreply, assign(socket, adding_channel: nil)}
  end

  @impl true
  def handle_event("save_channel", params, socket) do
    type = socket.assigns.adding_channel
    name = Map.get(params, "name", "")
    config = build_config(type, params)

    case Jagua.Alerts.AlertChannel
         |> Ash.Changeset.for_create(:create, %{
           name: name,
           type: type,
           config: config,
           project_id: socket.assigns.project.id
         })
         |> Ash.create(domain: Jagua.Alerts) do
      {:ok, _channel} ->
        channels = load_channels(socket.assigns.project.id)

        {:noreply,
         socket
         |> put_flash(:info, "Alert channel added.")
         |> assign(channels: channels, adding_channel: nil)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save channel. Check your inputs.")}
    end
  end

  @impl true
  def handle_event("toggle_channel", %{"id" => id}, socket) do
    channel = Enum.find(socket.assigns.channels, &(to_string(&1.id) == id))

    if channel do
      channel
      |> Ash.Changeset.for_update(:update, %{enabled: !channel.enabled})
      |> Ash.update!(domain: Jagua.Alerts)

      channels = load_channels(socket.assigns.project.id)
      {:noreply, assign(socket, channels: channels)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_channel", %{"id" => id}, socket) do
    channel = Enum.find(socket.assigns.channels, &(to_string(&1.id) == id))

    if channel do
      Ash.destroy!(channel, domain: Jagua.Alerts)
      channels = load_channels(socket.assigns.project.id)
      {:noreply, assign(socket, channels: channels)}
    else
      {:noreply, socket}
    end
  end

  defp build_config(:email, params) do
    emails =
      params
      |> Map.get("emails", "")
      |> String.split([",", "\n"], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{"emails" => emails}
  end

  defp build_config(:telegram, params) do
    %{
      "bot_token" => String.trim(Map.get(params, "bot_token", "")),
      "chat_id" => String.trim(Map.get(params, "chat_id", ""))
    }
  end

  defp build_config(:webhook, params) do
    %{
      "url" => String.trim(Map.get(params, "url", "")),
      "format" => Map.get(params, "format", "json")
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <.link navigate={~p"/projects/#{@project.slug}"}
        class="text-sm text-gray-400 hover:text-gray-600 mb-6 inline-block">
        ← <%= @project.name %>
      </.link>

      <h1 class="text-2xl font-bold text-gray-900 mb-8">Project settings</h1>

      <%!-- Status page --%>
      <div class="bg-white rounded-xl border border-gray-200 p-6 mb-4">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="text-sm font-semibold text-gray-900">Public status page</h2>
            <p class="text-sm text-gray-400 mt-1">
              Allow anyone to view the health of your sentinels without logging in.
            </p>
            <%= if @project.public_status_page do %>
              <a href={@status_url} target="_blank"
                class="text-xs text-blue-600 hover:underline mt-2 inline-block">
                <%= @status_url %> ↗
              </a>
            <% end %>
          </div>
          <button
            phx-click="toggle_status_page"
            class={[
              "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none",
              if(@project.public_status_page, do: "bg-gray-900", else: "bg-gray-200")
            ]}
            role="switch"
            aria-checked={to_string(@project.public_status_page)}
          >
            <span class={[
              "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow transition duration-200",
              if(@project.public_status_page, do: "translate-x-5", else: "translate-x-0")
            ]} />
          </button>
        </div>
      </div>

      <%!-- Alert channels --%>
      <div class="bg-white rounded-xl border border-gray-200 p-6 mb-4">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-sm font-semibold text-gray-900">Alert channels</h2>
        </div>

        <%= if @channels == [] do %>
          <p class="text-sm text-gray-400 mb-4">No alert channels configured. Add one to receive notifications.</p>
        <% else %>
          <div class="space-y-2 mb-4">
            <%= for channel <- @channels do %>
              <div class="flex items-center justify-between rounded-lg border border-gray-100 px-4 py-3">
                <div class="flex items-center gap-3">
                  <span class="text-xs font-medium uppercase tracking-wide px-2 py-0.5 rounded-full bg-gray-100 text-gray-500">
                    <%= channel.type %>
                  </span>
                  <span class="text-sm text-gray-900"><%= channel.name %></span>
                </div>
                <div class="flex items-center gap-3">
                  <button
                    phx-click="toggle_channel"
                    phx-value-id={channel.id}
                    class={[
                      "relative inline-flex h-5 w-9 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors",
                      if(channel.enabled, do: "bg-gray-900", else: "bg-gray-200")
                    ]}
                  >
                    <span class={[
                      "pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow transition",
                      if(channel.enabled, do: "translate-x-4", else: "translate-x-0")
                    ]} />
                  </button>
                  <button
                    phx-click="delete_channel"
                    phx-value-id={channel.id}
                    data-confirm={"Remove channel "#{channel.name}"?"}
                    class="text-gray-300 hover:text-red-500 transition-colors text-lg leading-none"
                  >
                    ×
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @adding_channel do %>
          <.channel_form type={@adding_channel} />
        <% else %>
          <div class="flex gap-2 flex-wrap">
            <button phx-click="show_add_channel" phx-value-type="email"
              class="text-sm rounded-lg border border-gray-200 px-3 py-1.5 text-gray-600 hover:bg-gray-50">
              + Email
            </button>
            <button phx-click="show_add_channel" phx-value-type="telegram"
              class="text-sm rounded-lg border border-gray-200 px-3 py-1.5 text-gray-600 hover:bg-gray-50">
              + Telegram
            </button>
            <button phx-click="show_add_channel" phx-value-type="webhook"
              class="text-sm rounded-lg border border-gray-200 px-3 py-1.5 text-gray-600 hover:bg-gray-50">
              + Webhook
            </button>
          </div>
        <% end %>
      </div>

      <%!-- Danger zone --%>
      <div class="bg-white rounded-xl border border-red-200 p-6">
        <h2 class="text-sm font-semibold text-red-700 mb-2">Danger zone</h2>
        <p class="text-sm text-gray-500 mb-4">
          Permanently delete this project and all its sentinels. This cannot be undone.
        </p>
        <button
          phx-click="delete_project"
          data-confirm={"Delete project \"#{@project.name}\" and all its sentinels? This cannot be undone."}
          class="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700"
        >
          Delete project
        </button>
      </div>
    </div>
    """
  end

  defp channel_form(%{type: :email} = assigns) do
    ~H"""
    <form phx-submit="save_channel" class="rounded-lg border border-gray-200 p-4 space-y-3">
      <h3 class="text-sm font-medium text-gray-900">New email channel</h3>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Channel name</label>
        <input type="text" name="name" required placeholder="e.g. On-call team"
          class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-400" />
      </div>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Email addresses (comma or newline separated)</label>
        <textarea name="emails" rows="3" required placeholder="alice@example.com, bob@example.com"
          class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-1 focus:ring-gray-400"></textarea>
      </div>
      <div class="flex gap-2">
        <button type="submit" class="rounded-lg bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-700">
          Save
        </button>
        <button type="button" phx-click="cancel_add_channel"
          class="rounded-lg border border-gray-200 px-4 py-2 text-sm font-medium text-gray-600 hover:bg-gray-50">
          Cancel
        </button>
      </div>
    </form>
    """
  end

  defp channel_form(%{type: :telegram} = assigns) do
    ~H"""
    <form phx-submit="save_channel" class="rounded-lg border border-gray-200 p-4 space-y-3">
      <h3 class="text-sm font-medium text-gray-900">New Telegram channel</h3>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Channel name</label>
        <input type="text" name="name" required placeholder="e.g. Ops alerts"
          class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-400" />
      </div>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Bot token</label>
        <input type="text" name="bot_token" required placeholder="123456:ABCdef..."
          class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-1 focus:ring-gray-400" />
      </div>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Chat ID</label>
        <input type="text" name="chat_id" required placeholder="-100123456789"
          class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-1 focus:ring-gray-400" />
        <p class="text-xs text-gray-400 mt-1">Use a negative number for group chats, positive for DMs.</p>
      </div>
      <div class="flex gap-2">
        <button type="submit" class="rounded-lg bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-700">
          Save
        </button>
        <button type="button" phx-click="cancel_add_channel"
          class="rounded-lg border border-gray-200 px-4 py-2 text-sm font-medium text-gray-600 hover:bg-gray-50">
          Cancel
        </button>
      </div>
    </form>
    """
  end

  defp channel_form(%{type: :webhook} = assigns) do
    ~H"""
    <form phx-submit="save_channel" class="rounded-lg border border-gray-200 p-4 space-y-3">
      <h3 class="text-sm font-medium text-gray-900">New webhook channel</h3>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Channel name</label>
        <input type="text" name="name" required placeholder="e.g. Slack #alerts"
          class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-400" />
      </div>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Webhook URL</label>
        <input type="url" name="url" required placeholder="https://hooks.slack.com/..."
          class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-1 focus:ring-gray-400" />
      </div>
      <div>
        <label class="block text-xs text-gray-500 mb-1">Payload format</label>
        <select name="format"
          class="rounded-lg border border-gray-200 px-3 py-2 text-sm text-gray-700 focus:outline-none focus:ring-1 focus:ring-gray-400">
          <option value="json">Generic JSON</option>
          <option value="slack">Slack-compatible</option>
        </select>
      </div>
      <div class="flex gap-2">
        <button type="submit" class="rounded-lg bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-700">
          Save
        </button>
        <button type="button" phx-click="cancel_add_channel"
          class="rounded-lg border border-gray-200 px-4 py-2 text-sm font-medium text-gray-600 hover:bg-gray-50">
          Cancel
        </button>
      </div>
    </form>
    """
  end
end
