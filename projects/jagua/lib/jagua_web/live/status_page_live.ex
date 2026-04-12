defmodule JaguaWeb.Live.StatusPageLive do
  use JaguaWeb, :live_view

  require Ash.Query

  import JaguaWeb.SentinelHelpers

  # No auth — this is a public page

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case load_project(slug) do
      {:ok, project} ->
        {:ok,
         assign(socket,
           project: project,
           sentinels: project.sentinels,
           page_title: "#{project.name} — Status"
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Status page not found.")
         |> push_navigate(to: ~p"/")}

      {:error, :private} ->
        {:ok,
         socket
         |> assign(project: nil, sentinels: [], page_title: "Status")}
    end
  end

  defp load_project(slug) do
    query =
      Jagua.Projects.Project
      |> Ash.Query.for_read(:by_slug, %{slug: slug})
      |> Ash.Query.load(:sentinels)

    case Ash.read_one(query, domain: Jagua.Projects) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, %{public_status_page: false}} -> {:error, :private}
      {:ok, project} -> {:ok, project}
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-12">
        <%= if @project do %>
          <div class="mb-10 text-center">
            <h1 class="text-2xl font-bold text-gray-900"><%= @project.name %></h1>
            <p class="text-sm text-gray-400 mt-1">System status</p>
          </div>

          <%!-- Overall health banner --%>
          <% {overall, banner_class} = overall_status(@sentinels) %>
          <div class={"rounded-xl px-5 py-4 mb-8 text-sm font-medium flex items-center gap-3 #{banner_class}"}>
            <span class="text-lg"><%= status_emoji(overall) %></span>
            <%= overall_label(overall) %>
          </div>

          <%!-- Sentinel list --%>
          <div class="space-y-2">
            <%= for sentinel <- Enum.sort_by(@sentinels, & &1.name) do %>
              <div class="bg-white rounded-xl border border-gray-200 px-5 py-4 flex items-center justify-between">
                <div>
                  <p class="text-sm font-medium text-gray-900"><%= sentinel.name %></p>
                  <p class="text-xs text-gray-400 mt-0.5">
                    Every <%= format_interval(sentinel.interval) %>
                    <%= if sentinel.last_check_in_at do %>
                      · last seen <%= format_ago(sentinel.last_check_in_at) %>
                    <% else %>
                      · never checked in
                    <% end %>
                  </p>
                </div>
                <.status_pill status={sentinel.status} />
              </div>
            <% end %>
          </div>

          <p class="text-center text-xs text-gray-300 mt-10">
            Powered by <a href="/" class="hover:text-gray-400">Jagua</a>
          </p>
        <% else %>
          <div class="text-center py-24">
            <p class="text-gray-400">This status page is not available.</p>
          </div>
        <% end %>
    </div>
    """
  end

  defp overall_status([]), do: {:unknown, "bg-gray-100 text-gray-500"}

  defp overall_status(sentinels) do
    cond do
      Enum.any?(sentinels, &(&1.status == :failed)) ->
        {:degraded, "bg-red-50 text-red-700 border border-red-200"}

      Enum.any?(sentinels, &(&1.status == :errored)) ->
        {:issues, "bg-orange-50 text-orange-700 border border-orange-200"}

      Enum.all?(sentinels, &(&1.status in [:healthy, :paused])) ->
        {:operational, "bg-green-50 text-green-700 border border-green-200"}

      true ->
        {:partial, "bg-yellow-50 text-yellow-700 border border-yellow-200"}
    end
  end

  defp overall_label(:operational), do: "All systems operational"
  defp overall_label(:degraded), do: "Service disruption detected"
  defp overall_label(:issues), do: "Some systems are reporting errors"
  defp overall_label(:partial), do: "Some systems are not reporting"
  defp overall_label(:unknown), do: "No sentinels configured"

  defp status_emoji(:operational), do: "✅"
  defp status_emoji(:degraded), do: "🔴"
  defp status_emoji(:issues), do: "🟠"
  defp status_emoji(:partial), do: "🟡"
  defp status_emoji(:unknown), do: "⚪"

  defp status_pill(assigns) do
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
    <span class={"inline-flex items-center rounded-full text-xs font-medium px-2.5 py-1 #{@classes}"}>
      <%= @label %>
    </span>
    """
  end
end
