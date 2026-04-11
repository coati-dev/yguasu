defmodule JaguaWeb.Live.ProjectLive.Settings do
  use JaguaWeb, :live_view

  require Ash.Query

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case load_project(slug) do
      {:ok, project} ->
        {:ok, assign(socket, project: project, status_url: status_url(slug))}

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

      <%!-- Danger zone --%>
      <div class="bg-white rounded-xl border border-red-200 p-6">
        <h2 class="text-sm font-semibold text-red-700 mb-2">Danger zone</h2>
        <p class="text-sm text-gray-500 mb-4">
          Permanently delete this project and all its sentinels. This cannot be undone.
        </p>
        <button
          phx-click="delete_project"
          data-confirm={"Delete project "#{@project.name}" and all its sentinels? This cannot be undone."}
          class="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700"
        >
          Delete project
        </button>
      </div>
    </div>
    """
  end
end
