defmodule Jagua.Alerts.Channels.Webhook do
  @moduledoc "POSTs alert payloads to a configured webhook URL via Finch."

  require Logger

  def send(channel, sentinel, type) do
    url = Map.get(channel.config, "url")
    format = Map.get(channel.config, "format", "json")

    if url do
      body = build_payload(sentinel, type, format)
      post(url, body)
    else
      Logger.warning("Webhook channel #{channel.id} has no URL configured")
    end
  end

  defp build_payload(sentinel, type, "slack") do
    text = slack_text(sentinel, type)
    Jason.encode!(%{text: text})
  end

  defp build_payload(sentinel, type, _json) do
    Jason.encode!(%{
      sentinel_id: sentinel.id,
      sentinel_name: sentinel.name,
      project_id: sentinel.project_id,
      status: sentinel.status,
      alert_type: type,
      interval: sentinel.interval,
      last_check_in_at: sentinel.last_check_in_at,
      alert_url: sentinel_url(sentinel)
    })
  end

  defp slack_text(sentinel, :failed),
    do: "🔴 *#{sentinel.name}* missed its check-in (interval: #{sentinel.interval})"

  defp slack_text(sentinel, :errored),
    do: "🟠 *#{sentinel.name}* reported an error (non-zero exit code)"

  defp slack_text(sentinel, :recovered),
    do: "✅ *#{sentinel.name}* has recovered"

  defp slack_text(sentinel, :pending_reminder),
    do: "⏳ *#{sentinel.name}* hasn't checked in since it was created 3 days ago"

  defp slack_text(sentinel, :paused_reminder),
    do: "⏸ *#{sentinel.name}* has been paused for 3 days"

  defp post(url, body) do
    request = Finch.build(:post, url, [{"content-type", "application/json"}], body)

    case Finch.request(request, Jagua.Finch) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning("Webhook returned #{status}: #{resp_body}")
        {:error, :webhook_error}

      {:error, reason} ->
        Logger.error("Webhook request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp sentinel_url(sentinel) do
    JaguaWeb.Endpoint.url() <> "/projects/#{sentinel.project_id}/sentinels/#{sentinel.token}"
  end
end
