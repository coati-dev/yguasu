defmodule JaguaWeb.Live.DashboardLive do
  use JaguaWeb, :live_view

  require Ash.Query

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    projects = load_projects(socket.assigns.current_user.id)
    {:ok, assign(socket, projects: projects, page_title: "Dashboard")}
  end

  @impl true
  def handle_event("delete_project", %{"id" => id}, socket) do
    project = Enum.find(socket.assigns.projects, &(&1.id == id))

    if project && project.owner_id == socket.assigns.current_user.id do
      Ash.destroy!(project, domain: Jagua.Projects)
    end

    {:noreply, assign(socket, projects: load_projects(socket.assigns.current_user.id))}
  end

  defp load_projects(user_id) do
    Jagua.Projects.Project
    |> Ash.Query.for_read(:for_user, %{user_id: user_id})
    |> Ash.Query.load(:sentinels)
    |> Ash.read!(domain: Jagua.Projects)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Projects</h1>
        <div class="flex items-center gap-3">
          <.link navigate={~p"/settings"}
            class="text-sm text-gray-400 hover:text-gray-600">
            <%= @current_user.email %>
          </.link>
          <.link href={~p"/auth/logout"} method="delete"
            class="text-sm text-gray-400 hover:text-gray-600">
            Sign out
          </.link>
          <.link navigate={~p"/projects/new"}
            class="bg-gray-900 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-gray-700 transition-colors">
            New project
          </.link>
        </div>
      </div>

      <%= if @projects == [] do %>
        <div class="text-center py-16 text-gray-400">
          <p class="text-lg mb-2">No projects yet.</p>
          <p class="text-sm">Create your first project to start monitoring jobs.</p>
        </div>
      <% else %>
        <div class="grid gap-4">
          <%= for project <- @projects do %>
            <.link navigate={~p"/projects/#{project.slug}"}
              class="block bg-white rounded-xl border border-gray-200 p-5 hover:border-gray-400 transition-colors">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="font-semibold text-gray-900"><%= project.name %></h2>
                  <p class="text-sm text-gray-400 mt-0.5">
                    <%= length(project.sentinels) %> sentinel<%= if length(project.sentinels) != 1, do: "s" %>
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <.sentinel_health_badges sentinels={project.sentinels} />
                </div>
              </div>
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp sentinel_health_badges(assigns) do
    counts = Enum.frequencies_by(assigns.sentinels, & &1.status)

    assigns = assign(assigns,
      failed: Map.get(counts, :failed, 0) + Map.get(counts, :errored, 0),
      healthy: Map.get(counts, :healthy, 0),
      pending: Map.get(counts, :pending, 0),
      paused: Map.get(counts, :paused, 0)
    )

    ~H"""
    <%= if @failed > 0 do %>
      <span class="inline-flex items-center rounded-full bg-red-100 text-red-700 text-xs font-medium px-2 py-0.5">
        <%= @failed %> failing
      </span>
    <% end %>
    <%= if @healthy > 0 do %>
      <span class="inline-flex items-center rounded-full bg-green-100 text-green-700 text-xs font-medium px-2 py-0.5">
        <%= @healthy %> healthy
      </span>
    <% end %>
    <%= if @pending > 0 do %>
      <span class="inline-flex items-center rounded-full bg-gray-100 text-gray-500 text-xs font-medium px-2 py-0.5">
        <%= @pending %> pending
      </span>
    <% end %>
    <%= if @paused > 0 do %>
      <span class="inline-flex items-center rounded-full bg-yellow-100 text-yellow-700 text-xs font-medium px-2 py-0.5">
        <%= @paused %> paused
      </span>
    <% end %>
    """
  end
end
