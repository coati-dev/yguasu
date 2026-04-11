defmodule Jagua.Alerts.Dispatcher do
  @moduledoc """
  Dispatches alert notifications to all enabled channels for a project.
  Called by Jagua.Sentinel.Timer when a sentinel misses its check-in window.
  """

  require Logger

  alias Jagua.Alerts.AlertChannel
  alias Jagua.Alerts.AlertEvent

  @doc """
  Sends an alert to all enabled channels for the sentinel's project.
  type is one of: :failed, :errored, :recovered, :pending_reminder, :paused_reminder
  """
  def dispatch(sentinel, type) do
    channels =
      AlertChannel
      |> Ash.Query.for_read(:for_project, %{project_id: sentinel.project_id})
      |> Ash.read!(domain: Jagua.Alerts)

    Enum.each(channels, fn channel ->
      Task.start(fn -> send_to_channel(channel, sentinel, type) end)
    end)
  end

  defp send_to_channel(%{type: :email} = channel, sentinel, type) do
    Jagua.Alerts.Channels.Email.send(channel, sentinel, type)
    record_event(channel, sentinel, type)
  rescue
    e -> Logger.error("Email alert failed for sentinel #{sentinel.id}: #{inspect(e)}")
  end

  defp send_to_channel(%{type: :telegram} = channel, sentinel, type) do
    Jagua.Alerts.Channels.Telegram.send(channel, sentinel, type)
    record_event(channel, sentinel, type)
  rescue
    e -> Logger.error("Telegram alert failed for sentinel #{sentinel.id}: #{inspect(e)}")
  end

  defp send_to_channel(%{type: :webhook} = channel, sentinel, type) do
    Jagua.Alerts.Channels.Webhook.send(channel, sentinel, type)
    record_event(channel, sentinel, type)
  rescue
    e -> Logger.error("Webhook alert failed for sentinel #{sentinel.id}: #{inspect(e)}")
  end

  defp record_event(channel, sentinel, type) do
    AlertEvent
    |> Ash.Changeset.for_create(:record, %{
      sentinel_id: sentinel.id,
      alert_channel_id: channel.id,
      type: type,
      payload: %{sentinel_name: sentinel.name, status: sentinel.status}
    })
    |> Ash.create!(domain: Jagua.Alerts)
  end
end
