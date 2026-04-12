defmodule JaguaWeb.Live.ProjectLive.New do
  use JaguaWeb, :live_view

  on_mount {JaguaWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    form =
      AshPhoenix.Form.for_create(Jagua.Projects.Project, :create,
        domain: Jagua.Projects,
        as: "project"
      )

    {:ok, assign(socket, form: to_form(form), page_title: "New project")}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("save", %{"project" => params}, socket) do
    user = socket.assigns.current_user
    slug = slugify(params["name"] || "")
    params = Map.merge(params, %{"slug" => slug, "owner_id" => user.id})

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created.")
         |> push_navigate(to: ~p"/projects/#{project.slug}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-4 py-8">
      <.link navigate={~p"/dashboard"} class="text-sm text-gray-400 hover:text-gray-600 mb-6 inline-block">
        ← Back to projects
      </.link>

      <h1 class="text-2xl font-bold text-gray-900 mb-8">New project</h1>

      <div class="bg-white rounded-xl border border-gray-200 shadow-sm p-6">
        <.form for={@form} phx-submit="save" phx-change="validate">
          <div class="mb-5">
            <label class="block text-sm font-medium text-gray-700 mb-1">Project name</label>
            <input
              type="text"
              name="project[name]"
              value={Phoenix.HTML.Form.input_value(@form, :name)}
              placeholder="My Application"
              class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
            />
            <.error :for={error <- Keyword.get_values(@form.errors, :name)}>
              <%= translate_error(error) %>
            </.error>
          </div>

          <div class="flex gap-3 justify-end">
            <.link navigate={~p"/dashboard"}
              class="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
              Cancel
            </.link>
            <button type="submit"
              class="bg-gray-900 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-gray-700">
              Create project
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
