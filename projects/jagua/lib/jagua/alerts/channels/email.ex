defmodule Jagua.Alerts.Channels.Email do
  @moduledoc "Sends alert emails via Swoosh."

  require Logger

  def send(_channel, sentinel, type) do
    Logger.info("Email alert: sentinel=#{sentinel.name} type=#{type} [not yet implemented]")
    # TODO: build and deliver email via Jagua.Mailer
    :ok
  end
end
