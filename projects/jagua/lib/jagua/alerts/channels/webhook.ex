defmodule Jagua.Alerts.Channels.Webhook do
  @moduledoc "POSTs alert payloads to a configured webhook URL via Finch."

  require Logger

  def send(_channel, sentinel, type) do
    Logger.info("Webhook alert: sentinel=#{sentinel.name} type=#{type} [not yet implemented]")
    # TODO: build JSON payload and POST to channel.config["url"]
    # Supports format: "json" (generic) or "slack" (Slack-compatible)
    :ok
  end
end
