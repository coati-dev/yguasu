defmodule JaguaWeb.Live.ApiKeysLive do
  use JaguaWeb, :live_view

  require Ash.Query

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case load_project(slug) do
      {:ok, project} ->
        keys = load_keys(project.id)

        {:ok,
         assign(socket,
           project: project,
           keys: keys,
           # %{id: key_id, raw_key: "jg_..."} — shown only once, then cleared
           revealed_key: nil,
           adding: false,
           new_key_name: ""
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

  defp load_keys(project_id) do
    Jagua.ApiKeys.ApiKey
    |> Ash.Query.for_read(:for_project, %{project_id: project_id})
    |> Ash.read!(domain: Jagua.ApiKeys)
  end

  @impl true
  def handle_event("show_add", _params, socket) do
    {:noreply, assign(socket, adding: true, new_key_name: "")}
  end

  @impl true
  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, adding: false)}
  end

  @impl true
  def handle_event("generate_key", %{"name" => name}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Name is required.")}
    else
      {raw_key, prefix, key_hash} = generate_key()

      case Jagua.ApiKeys.ApiKey
           |> Ash.Changeset.for_create(:create, %{
             name: name,
             project_id: socket.assigns.project.id,
             prefix: prefix,
             key_hash: key_hash
           })
           |> Ash.create(domain: Jagua.ApiKeys) do
        {:ok, key} ->
          keys = load_keys(socket.assigns.project.id)

          {:noreply,
           assign(socket,
             keys: keys,
             adding: false,
             revealed_key: %{id: key.id, raw_key: raw_key}
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create key.")}
      end
    end
  end

  @impl true
  def handle_event("dismiss_revealed", _params, socket) do
    {:noreply, assign(socket, revealed_key: nil)}
  end

  @impl true
  def handle_event("delete_key", %{"id" => id}, socket) do
    key = Enum.find(socket.assigns.keys, &(to_string(&1.id) == id))

    if key do
      Ash.destroy!(key, domain: Jagua.ApiKeys)
      keys = load_keys(socket.assigns.project.id)

      revealed =
        if socket.assigns.revealed_key && to_string(socket.assigns.revealed_key.id) == id,
          do: nil,
          else: socket.assigns.revealed_key

      {:noreply, assign(socket, keys: keys, revealed_key: revealed)}
    else
      {:noreply, socket}
    end
  end

  defp generate_key do
    # Format: jg_<48 hex chars> = 51 chars total
    random = :crypto.strong_rand_bytes(24) |> Base.encode16(case: :lower)
    raw_key = "jg_#{random}"
    prefix = String.slice(raw_key, 0, 12)
    key_hash = :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
    {raw_key, prefix, key_hash}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <.link navigate={~p"/projects/#{@project.slug}"}
        class="text-sm text-gray-400 hover:text-gray-600 mb-6 inline-block">
        ← <%= @project.name %>
      </.link>

      <div class="flex items-center justify-between mb-8">
        <h1 class="text-2xl font-bold text-gray-900">API keys</h1>
        <%= unless @adding do %>
          <button phx-click="show_add"
            class="bg-gray-900 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-gray-700 transition-colors">
            New key
          </button>
        <% end %>
      </div>

      <%= if @revealed_key do %>
        <div class="mb-6 rounded-xl border border-green-200 bg-green-50 p-5">
          <p class="text-sm font-semibold text-green-900 mb-2">Copy your API key now — it won't be shown again.</p>
          <div class="flex items-center gap-2">
            <code class="flex-1 bg-white rounded-lg border border-green-200 px-4 py-2 text-sm font-mono text-gray-900 break-all">
              <%= @revealed_key.raw_key %>
            </code>
            <button
              phx-click={JS.dispatch("jagua:copy", detail: %{text: @revealed_key.raw_key})}
              class="flex-shrink-0 rounded-lg border border-green-200 bg-white px-3 py-2 text-xs font-medium text-gray-600 hover:bg-gray-50">
              Copy
            </button>
          </div>
          <button phx-click="dismiss_revealed"
            class="mt-3 text-xs text-green-700 hover:text-green-900 underline">
            I've saved it, dismiss
          </button>
        </div>
      <% end %>

      <%= if @adding do %>
        <form phx-submit="generate_key" class="bg-white rounded-xl border border-gray-200 p-6 mb-4">
          <h3 class="text-sm font-semibold text-gray-900 mb-4">New API key</h3>
          <div class="mb-4">
            <label class="block text-xs text-gray-500 mb-1">Key name</label>
            <input
              type="text"
              name="name"
              required
              autofocus
              placeholder="e.g. Terraform provider, CI pipeline"
              class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-400"
            />
          </div>
          <div class="flex gap-2">
            <button type="submit"
              class="rounded-lg bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-700">
              Generate
            </button>
            <button type="button" phx-click="cancel_add"
              class="rounded-lg border border-gray-200 px-4 py-2 text-sm font-medium text-gray-600 hover:bg-gray-50">
              Cancel
            </button>
          </div>
        </form>
      <% end %>

      <%= if @keys == [] and not @adding do %>
        <div class="text-center py-16 text-gray-400 bg-white rounded-xl border border-gray-200">
          <p class="text-lg mb-2">No API keys yet.</p>
          <p class="text-sm">Generate a key to manage this project via the REST API.</p>
        </div>
      <% else %>
        <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-gray-100 text-left">
                <th class="px-5 py-3 font-medium text-gray-500">Name</th>
                <th class="px-5 py-3 font-medium text-gray-500">Key</th>
                <th class="px-5 py-3 font-medium text-gray-500">Last used</th>
                <th class="px-5 py-3"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-50">
              <%= for key <- @keys do %>
                <tr>
                  <td class="px-5 py-4 font-medium text-gray-900"><%= key.name %></td>
                  <td class="px-5 py-4 font-mono text-gray-500 text-xs">
                    <%= key.prefix %>…
                  </td>
                  <td class="px-5 py-4 text-gray-400 text-xs">
                    <%= if key.last_used_at do %>
                      <%= format_ago(key.last_used_at) %>
                    <% else %>
                      Never
                    <% end %>
                  </td>
                  <td class="px-5 py-4 text-right">
                    <button
                      phx-click="delete_key"
                      phx-value-id={key.id}
                      data-confirm={"Revoke key \"#{key.name}\"? This cannot be undone."}
                      class="text-xs text-red-500 hover:text-red-700"
                    >
                      Revoke
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="mt-6 bg-gray-50 rounded-xl border border-gray-200 p-5 text-sm text-gray-600">
          <p class="font-medium text-gray-900 mb-2">Using the API</p>
          <p class="mb-3 text-gray-500">Include your key in every request:</p>
          <code class="block bg-gray-900 text-green-400 rounded-lg px-4 py-3 text-sm font-mono">
            curl -H "Authorization: Bearer &lt;key&gt;" <%= JaguaWeb.Endpoint.url() %>/api/projects
          </code>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_ago(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
