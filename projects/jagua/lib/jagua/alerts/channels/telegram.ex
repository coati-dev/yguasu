defmodule Jagua.Alerts.Channels.Telegram do
  @moduledoc "Sends alert messages via Telegram Bot API using Finch."

  require Logger

  def send(_channel, sentinel, type) do
    Logger.info("Telegram alert: sentinel=#{sentinel.name} type=#{type} [not yet implemented]")
    # TODO: POST to https://api.telegram.org/bot<token>/sendMessage
    :ok
  end
end
