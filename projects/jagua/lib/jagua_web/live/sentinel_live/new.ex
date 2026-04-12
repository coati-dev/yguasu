defmodule JaguaWeb.Live.SentinelLive.New do
  use JaguaWeb, :live_view

  require Ash.Query

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @intervals [
    {"1 minute", "1_minute"},
    {"2 minutes", "2_minute"},
    {"3 minutes", "3_minute"},
    {"5 minutes", "5_minute"},
    {"10 minutes", "10_minute"},
    {"15 minutes", "15_minute"},
    {"20 minutes", "20_minute"},
    {"30 minutes", "30_minute"},
    {"Hourly", "hourly"},
    {"2 hours", "2_hour"},
    {"3 hours", "3_hour"},
    {"4 hours", "4_hour"},
    {"6 hours", "6_hour"},
    {"8 hours", "8_hour"},
    {"12 hours", "12_hour"},
    {"Daily", "daily"},
    {"Weekly", "weekly"},
    {"Monthly", "monthly"}
  ]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case load_project(slug) do
      {:ok, project} ->
        form =
          AshPhoenix.Form.for_create(Jagua.Sentinels.Sentinel, :create,
            domain: Jagua.Sentinels,
            as: "sentinel"
          )

        {:ok,
         assign(socket,
           project: project,
           form: to_form(form),
           intervals: @intervals,
           page_title: "New sentinel · #{project.name}"
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

  @impl true
  def handle_event("validate", %{"sentinel" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("save", %{"sentinel" => params}, socket) do
    project = socket.assigns.project
    params = Map.put(params, "project_id", project.id)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, sentinel} ->
        # Start the OTP timer for this new sentinel
        Jagua.Sentinel.Timer.ensure_started(sentinel)

        {:noreply,
         socket
         |> put_flash(:info, "Sentinel created.")
         |> push_navigate(to: ~p"/projects/#{project.slug}/sentinels/#{sentinel.token}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-4 py-8">
      <.link navigate={~p"/projects/#{@project.slug}"}
        class="text-sm text-gray-400 hover:text-gray-600 mb-6 inline-block">
        ← <%= @project.name %>
      </.link>

      <h1 class="text-2xl font-bold text-gray-900 mb-8">New sentinel</h1>

      <div class="bg-white rounded-xl border border-gray-200 shadow-sm p-6">
        <.form for={@form} phx-submit="save" phx-change="validate">
          <div class="mb-5">
            <label class="block text-sm font-medium text-gray-700 mb-1">Name</label>
            <input
              type="text"
              name="sentinel[name]"
              value={Phoenix.HTML.Form.input_value(@form, :name)}
              placeholder="daily-backup"
              class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
            />
            <.error :for={error <- Keyword.get_values(@form.errors, :name)}>
              <%= translate_error(error) %>
            </.error>
          </div>

          <div class="mb-5">
            <label class="block text-sm font-medium text-gray-700 mb-1">Interval</label>
            <select
              name="sentinel[interval]"
              class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
            >
              <%= for {label, value} <- @intervals do %>
                <option value={value}
                  selected={Phoenix.HTML.Form.input_value(@form, :interval) == value}>
                  <%= label %>
                </option>
              <% end %>
            </select>
          </div>

          <div class="mb-5">
            <label class="block text-sm font-medium text-gray-700 mb-1">
              Alert type
            </label>
            <div class="flex gap-4">
              <label class="flex items-center gap-2 text-sm text-gray-700 cursor-pointer">
                <input type="radio" name="sentinel[alert_type]" value="basic"
                  checked={Phoenix.HTML.Form.input_value(@form, :alert_type) != "smart"} />
                Basic <span class="text-gray-400">(fixed window)</span>
              </label>
              <label class="flex items-center gap-2 text-sm text-gray-700 cursor-pointer">
                <input type="radio" name="sentinel[alert_type]" value="smart"
                  checked={Phoenix.HTML.Form.input_value(@form, :alert_type) == "smart"} />
                Smart <span class="text-gray-400">(learns your schedule)</span>
              </label>
            </div>
          </div>

          <div class="mb-6">
            <label class="block text-sm font-medium text-gray-700 mb-1">
              Notes <span class="text-gray-400 font-normal">(optional)</span>
            </label>
            <textarea
              name="sentinel[notes]"
              rows="3"
              placeholder="What does this sentinel monitor?"
              class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
            ><%= Phoenix.HTML.Form.input_value(@form, :notes) %></textarea>
          </div>

          <div class="flex gap-3 justify-end">
            <.link navigate={~p"/projects/#{@project.slug}"}
              class="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
              Cancel
            </.link>
            <button type="submit"
              class="bg-gray-900 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-gray-700">
              Create sentinel
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
