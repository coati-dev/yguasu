defmodule JaguaWeb.Live.ProjectLive.Show do
  use JaguaWeb, :live_view

  require Ash.Query

  import JaguaWeb.SentinelHelpers

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case load_project(slug) do
      {:ok, project} ->
        {:ok, assign(socket, project: project, sentinels: project.sentinels)}

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
      |> Ash.Query.load(:sentinels)

    case Ash.read_one(query, domain: Jagua.Projects) do
      {:ok, nil} -> :error
      {:ok, project} -> {:ok, project}
      _ -> :error
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <.link navigate={~p"/dashboard"} class="text-sm text-gray-400 hover:text-gray-600 mb-2 inline-block">
        ← Projects
      </.link>

      <div class="flex items-center justify-between mb-8 mt-2">
        <h1 class="text-2xl font-bold text-gray-900"><%= @project.name %></h1>
        <.link navigate={~p"/projects/#{@project.slug}/sentinels/new"}
          class="bg-gray-900 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-gray-700 transition-colors">
          New sentinel
        </.link>
      </div>

      <%= if @sentinels == [] do %>
        <div class="text-center py-16 text-gray-400 bg-white rounded-xl border border-gray-200">
          <p class="text-lg mb-2">No sentinels yet.</p>
          <p class="text-sm">Create a sentinel to start monitoring a scheduled job.</p>
        </div>
      <% else %>
        <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-gray-100 text-left">
                <th class="px-5 py-3 font-medium text-gray-500">Name</th>
                <th class="px-5 py-3 font-medium text-gray-500">Status</th>
                <th class="px-5 py-3 font-medium text-gray-500">Interval</th>
                <th class="px-5 py-3 font-medium text-gray-500">Last check-in</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-50">
              <%= for sentinel <- @sentinels do %>
                <tr class="hover:bg-gray-50 cursor-pointer"
                    phx-click={JS.navigate(~p"/projects/#{@project.slug}/sentinels/#{sentinel.token}")}>
                  <td class="px-5 py-4 font-medium text-gray-900"><%= sentinel.name %></td>
                  <td class="px-5 py-4">
                    <.status_badge status={sentinel.status} />
                  </td>
                  <td class="px-5 py-4 text-gray-500"><%= format_interval(sentinel.interval) %></td>
                  <td class="px-5 py-4 text-gray-400 text-xs">
                    <%= if sentinel.last_check_in_at do %>
                      <%= format_ago(sentinel.last_check_in_at) %>
                    <% else %>
                      Never
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_badge(assigns) do
    {label, classes} =
      case assigns.status do
        :healthy -> {"Healthy", "bg-green-100 text-green-700"}
        :failed -> {"Failed", "bg-red-100 text-red-700"}
        :errored -> {"Errored", "bg-orange-100 text-orange-700"}
        :paused -> {"Paused", "bg-yellow-100 text-yellow-700"}
        :pending -> {"Pending", "bg-gray-100 text-gray-500"}
      end

    assigns = assign(assigns, label: label, classes: classes)

    ~H"""
    <span class={"inline-flex items-center rounded-full text-xs font-medium px-2 py-0.5 #{@classes}"}>
      <%= @label %>
    </span>
    """
  end

end
