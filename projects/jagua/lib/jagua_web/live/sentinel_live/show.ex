defmodule JaguaWeb.Live.SentinelLive.Show do
  use JaguaWeb, :live_view

  require Ash.Query

  import JaguaWeb.SentinelHelpers

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(%{"slug" => slug, "token" => token}, _session, socket) do
    case load_sentinel(slug, token) do
      {:ok, project, sentinel} ->
        check_ins = load_recent_check_ins(sentinel.id)
        heatmap = Jagua.Sentinels.Heatmap.build(sentinel)

        {:ok,
         assign(socket,
           project: project,
           sentinel: sentinel,
           check_ins: check_ins,
           heatmap: heatmap,
           tab: "activity",
           check_in_url: check_in_url(token)
         )}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Sentinel not found.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  defp load_sentinel(slug, token) do
    project_query =
      Jagua.Projects.Project
      |> Ash.Query.for_read(:by_slug, %{slug: slug})

    sentinel_query =
      Jagua.Sentinels.Sentinel
      |> Ash.Query.for_read(:by_token, %{token: token})

    with {:ok, project} when not is_nil(project) <- Ash.read_one(project_query, domain: Jagua.Projects),
         {:ok, sentinel} when not is_nil(sentinel) <- Ash.read_one(sentinel_query, domain: Jagua.Sentinels),
         true <- sentinel.project_id == project.id do
      {:ok, project, sentinel}
    else
      _ -> :error
    end
  end

  defp load_recent_check_ins(sentinel_id) do
    Jagua.Sentinels.CheckIn
    |> Ash.Query.for_read(:recent_for_sentinel, %{sentinel_id: sentinel_id, limit: 20})
    |> Ash.read!(domain: Jagua.Sentinels)
  end

  defp check_in_url(token) do
    JaguaWeb.Endpoint.url() <> "/in/#{token}"
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  @impl true
  def handle_event("pause", _params, socket) do
    sentinel =
      socket.assigns.sentinel
      |> Ash.Changeset.for_update(:pause, %{})
      |> Ash.update!(domain: Jagua.Sentinels)
    Jagua.Sentinel.Timer.stop(sentinel.id)
    {:noreply, assign(socket, sentinel: sentinel)}
  end

  @impl true
  def handle_event("unpause", _params, socket) do
    sentinel =
      socket.assigns.sentinel
      |> Ash.Changeset.for_update(:unpause, %{})
      |> Ash.update!(domain: Jagua.Sentinels)
    Jagua.Sentinel.Timer.ensure_started(sentinel)
    {:noreply, assign(socket, sentinel: sentinel)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    Jagua.Sentinel.Timer.stop(socket.assigns.sentinel.id)
    Ash.destroy!(socket.assigns.sentinel, domain: Jagua.Sentinels)

    {:noreply,
     socket
     |> put_flash(:info, "Sentinel deleted.")
     |> push_navigate(to: ~p"/projects/#{socket.assigns.project.slug}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <.link navigate={~p"/projects/#{@project.slug}"}
        class="text-sm text-gray-400 hover:text-gray-600 mb-2 inline-block">
        ← <%= @project.name %>
      </.link>

      <div class="flex items-center gap-3 mb-6 mt-2">
        <.status_dot status={@sentinel.status} />
        <h1 class="text-2xl font-bold text-gray-900"><%= @sentinel.name %></h1>
        <.status_badge status={@sentinel.status} />
      </div>

      <%!-- Tabs --%>
      <div class="flex gap-1 border-b border-gray-200 mb-6">
        <%= for {id, label} <- [{"activity", "Activity"}, {"setup", "Setup"}, {"settings", "Settings"}] do %>
          <button
            phx-click="switch_tab"
            phx-value-tab={id}
            class={[
              "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@tab == id,
                do: "border-gray-900 text-gray-900",
                else: "border-transparent text-gray-400 hover:text-gray-600"
              )
            ]}
          >
            <%= label %>
          </button>
        <% end %>
      </div>

      <%= if @tab == "activity" do %>
        <.activity_tab sentinel={@sentinel} check_ins={@check_ins} heatmap={@heatmap} />
      <% end %>
      <%= if @tab == "setup" do %>
        <.setup_tab sentinel={@sentinel} check_in_url={@check_in_url} />
      <% end %>
      <%= if @tab == "settings" do %>
        <.settings_tab sentinel={@sentinel} project={@project} />
      <% end %>
    </div>
    """
  end

  defp activity_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Stats row --%>
      <div class="grid grid-cols-2 gap-4">
        <div class="bg-white rounded-xl border border-gray-200 p-5">
          <p class="text-xs text-gray-400 font-medium uppercase tracking-wide mb-1">Last check-in</p>
          <p class="text-sm font-medium text-gray-900">
            <%= if @sentinel.last_check_in_at do %>
              <%= format_ago(@sentinel.last_check_in_at) %>
            <% else %>
              Never
            <% end %>
          </p>
        </div>
        <div class="bg-white rounded-xl border border-gray-200 p-5">
          <p class="text-xs text-gray-400 font-medium uppercase tracking-wide mb-1">Interval</p>
          <p class="text-sm font-medium text-gray-900"><%= format_interval(@sentinel.interval) %></p>
        </div>
      </div>

      <%!-- Heatmap --%>
      <div class="bg-white rounded-xl border border-gray-200 p-5">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-sm font-medium text-gray-900">Activity</h3>
          <div class="flex items-center gap-3 text-xs text-gray-400">
            <span class="flex items-center gap-1">
              <span class="w-2.5 h-2.5 rounded-sm bg-green-400 inline-block"></span> Healthy
            </span>
            <span class="flex items-center gap-1">
              <span class="w-2.5 h-2.5 rounded-sm bg-orange-400 inline-block"></span> Errored
            </span>
            <span class="flex items-center gap-1">
              <span class="w-2.5 h-2.5 rounded-sm bg-red-400 inline-block"></span> Missed
            </span>
            <span class="flex items-center gap-1">
              <span class="w-2.5 h-2.5 rounded-sm bg-gray-200 inline-block"></span> No data
            </span>
          </div>
        </div>
        <.heatmap_grid cells={@heatmap.cells} interval={@heatmap.interval} />
      </div>

      <%!-- Recent check-ins log --%>
      <%= if @check_ins != [] do %>
        <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <div class="px-5 py-4 border-b border-gray-100">
            <h3 class="text-sm font-medium text-gray-900">Recent check-ins</h3>
          </div>
          <div class="divide-y divide-gray-50">
            <%= for ci <- @check_ins do %>
              <div class="px-5 py-3 flex items-center gap-3">
                <span class={[
                  "w-2 h-2 rounded-full flex-shrink-0",
                  if(ci.status == :ok, do: "bg-green-400", else: "bg-orange-400")
                ]} />
                <span class="text-xs text-gray-400 w-36 flex-shrink-0">
                  <%= Calendar.strftime(ci.inserted_at, "%b %d %H:%M UTC") %>
                </span>
                <%= if ci.message do %>
                  <span class="text-sm text-gray-600 truncate"><%= ci.message %></span>
                <% end %>
                <%= if ci.exit_code != 0 do %>
                  <span class="ml-auto text-xs text-orange-600 flex-shrink-0">
                    exit <%= ci.exit_code %>
                  </span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp heatmap_grid(%{interval: :daily} = assigns) do
    # GitHub-style: 7 rows (Mon–Sun) × N columns (weeks), newest column on right
    cells_by_week = Enum.chunk_every(assigns.cells, 7)
    assigns = assign(assigns, cells_by_week: cells_by_week)

    ~H"""
    <div class="overflow-x-auto">
      <div class="flex gap-0.5 min-w-0">
        <%= for week <- @cells_by_week do %>
          <div class="flex flex-col gap-0.5">
            <%= for cell <- week do %>
              <.heatmap_cell cell={cell} />
            <% end %>
          </div>
        <% end %>
      </div>
      <div class="flex justify-between mt-2 text-xs text-gray-400">
        <span><%= heatmap_label(List.first(List.first(@cells_by_week)), :daily) %></span>
        <span><%= heatmap_label(List.last(List.last(@cells_by_week)), :daily) %></span>
      </div>
    </div>
    """
  end

  defp heatmap_grid(assigns) do
    # Single scrollable row for sub-day and weekly/monthly intervals
    ~H"""
    <div class="overflow-x-auto">
      <div class="flex gap-0.5 pb-1">
        <%= for cell <- @cells do %>
          <.heatmap_cell cell={cell} />
        <% end %>
      </div>
      <div class="flex justify-between mt-2 text-xs text-gray-400">
        <span><%= heatmap_label(List.first(@cells), @interval) %></span>
        <span><%= heatmap_label(List.last(@cells), @interval) %></span>
      </div>
    </div>
    """
  end

  defp heatmap_cell(assigns) do
    color =
      case assigns.cell.status do
        :healthy -> "bg-green-400 hover:bg-green-500"
        :errored -> "bg-orange-400 hover:bg-orange-500"
        :missed -> "bg-red-400 hover:bg-red-500"
        :unknown -> "bg-gray-100"
        :future -> "bg-gray-50"
      end

    title = heatmap_cell_title(assigns.cell)
    assigns = assign(assigns, color: color, title: title)

    ~H"""
    <div
      class={"w-3 h-3 rounded-sm flex-shrink-0 cursor-default transition-colors #{@color}"}
      title={@title}
    />
    """
  end

  defp heatmap_cell_title(%{status: :unknown}), do: "No data"
  defp heatmap_cell_title(%{status: :future}), do: "Future"
  defp heatmap_cell_title(%{bucket_start: dt, status: status, count: count}) do
    label = Calendar.strftime(dt, "%b %d %H:%M UTC")
    case status do
      :healthy -> "#{label} — #{count} check-in(s)"
      :errored -> "#{label} — errored (#{count} check-in(s))"
      :missed -> "#{label} — missed"
    end
  end

  defp heatmap_label(nil, _), do: ""
  defp heatmap_label(%{bucket_start: dt}, :daily), do: Calendar.strftime(dt, "%b %Y")
  defp heatmap_label(%{bucket_start: dt}, :weekly), do: Calendar.strftime(dt, "%b %d")
  defp heatmap_label(%{bucket_start: dt}, :monthly), do: Calendar.strftime(dt, "%b %Y")
  defp heatmap_label(%{bucket_start: dt}, _), do: Calendar.strftime(dt, "%b %d %H:%M")

  defp setup_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white rounded-xl border border-gray-200 p-6">
        <h3 class="text-sm font-semibold text-gray-900 mb-4">Your check-in URL</h3>
        <div class="flex items-center gap-2 bg-gray-50 rounded-lg px-4 py-3 font-mono text-sm text-gray-700 break-all">
          <%= @check_in_url %>
        </div>
      </div>

      <div class="bg-white rounded-xl border border-gray-200 p-6 space-y-5">
        <h3 class="text-sm font-semibold text-gray-900">Integration guide</h3>

        <div>
          <p class="text-sm text-gray-500 mb-2">Basic check-in with curl:</p>
          <code class="block bg-gray-900 text-green-400 rounded-lg px-4 py-3 text-sm font-mono">
            curl <%= @check_in_url %>
          </code>
        </div>

        <div>
          <p class="text-sm text-gray-500 mb-2">Include a message:</p>
          <code class="block bg-gray-900 text-green-400 rounded-lg px-4 py-3 text-sm font-mono">
            curl "<%= @check_in_url %>?m=completed+in+42s"
          </code>
        </div>

        <div>
          <p class="text-sm text-gray-500 mb-2">Report exit status (non-zero marks as errored):</p>
          <code class="block bg-gray-900 text-green-400 rounded-lg px-4 py-3 text-sm font-mono">
            your_command && curl "<%= @check_in_url %>?s=0" || curl "<%= @check_in_url %>?s=1"
          </code>
        </div>

        <div>
          <p class="text-sm text-gray-500 mb-2">Capture exit code automatically:</p>
          <code class="block bg-gray-900 text-green-400 rounded-lg px-4 py-3 text-sm font-mono">
            your_command; curl "<%= @check_in_url %>?s=$?"
          </code>
        </div>

        <div>
          <p class="text-sm text-gray-500 mb-2">Cron example (add to end of cron command):</p>
          <code class="block bg-gray-900 text-green-400 rounded-lg px-4 py-3 text-sm font-mono">
            0 * * * * /path/to/job.sh && curl "<%= @check_in_url %>" &>/dev/null
          </code>
        </div>
      </div>
    </div>
    """
  end

  defp settings_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white rounded-xl border border-gray-200 p-6">
        <h3 class="text-sm font-semibold text-gray-900 mb-4">Details</h3>
        <dl class="space-y-3 text-sm">
          <div class="flex gap-4">
            <dt class="text-gray-400 w-24 flex-shrink-0">Token</dt>
            <dd class="font-mono text-gray-700"><%= @sentinel.token %></dd>
          </div>
          <div class="flex gap-4">
            <dt class="text-gray-400 w-24 flex-shrink-0">Interval</dt>
            <dd class="text-gray-700"><%= format_interval(@sentinel.interval) %></dd>
          </div>
          <div class="flex gap-4">
            <dt class="text-gray-400 w-24 flex-shrink-0">Alert type</dt>
            <dd class="text-gray-700 capitalize"><%= @sentinel.alert_type %></dd>
          </div>
          <%= if @sentinel.notes do %>
            <div class="flex gap-4">
              <dt class="text-gray-400 w-24 flex-shrink-0">Notes</dt>
              <dd class="text-gray-700"><%= @sentinel.notes %></dd>
            </div>
          <% end %>
        </dl>
      </div>

      <div class="bg-white rounded-xl border border-gray-200 p-6">
        <h3 class="text-sm font-semibold text-gray-900 mb-4">Actions</h3>
        <div class="flex gap-3">
          <%= if @sentinel.status == :paused do %>
            <button phx-click="unpause"
              class="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
              Unpause
            </button>
          <% else %>
            <button phx-click="pause"
              class="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
              Pause
            </button>
          <% end %>
        </div>
      </div>

      <div class="bg-white rounded-xl border border-red-200 p-6">
        <h3 class="text-sm font-semibold text-red-700 mb-2">Danger zone</h3>
        <p class="text-sm text-gray-500 mb-4">
          Permanently delete this sentinel and all its check-in history.
        </p>
        <button phx-click="delete"
          data-confirm={"Delete sentinel "#{@sentinel.name}"? This cannot be undone."}
          class="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700">
          Delete sentinel
        </button>
      </div>
    </div>
    """
  end

  defp status_dot(assigns) do
    color =
      case assigns.status do
        :healthy -> "bg-green-400"
        :failed -> "bg-red-500"
        :errored -> "bg-orange-400"
        :paused -> "bg-yellow-400"
        :pending -> "bg-gray-300"
      end

    assigns = assign(assigns, color: color)
    ~H(<span class={"w-3 h-3 rounded-full flex-shrink-0 #{@color}"} />)
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
