defmodule Jagua.Alerts.Channels.Telegram do
  @moduledoc "Sends alert messages via Telegram Bot API using Finch."

  require Logger

  @telegram_api "https://api.telegram.org"

  def send(channel, sentinel, type) do
    bot_token = Map.get(channel.config, "bot_token")
    chat_id = Map.get(channel.config, "chat_id")

    if bot_token && chat_id do
      text = format_message(sentinel, type)
      post_message(bot_token, chat_id, text)
    else
      Logger.warning("Telegram channel #{channel.id} missing bot_token or chat_id")
    end
  end

  defp format_message(sentinel, :failed) do
    "🔴 *#{escape(sentinel.name)}* missed its check\\-in\n_Interval: #{escape(to_string(sentinel.interval))}_"
  end

  defp format_message(sentinel, :errored) do
    "🟠 *#{escape(sentinel.name)}* reported an error \\(non\\-zero exit code\\)\n_Interval: #{escape(to_string(sentinel.interval))}_"
  end

  defp format_message(sentinel, :recovered) do
    "✅ *#{escape(sentinel.name)}* has recovered and checked in successfully"
  end

  defp format_message(sentinel, :pending_reminder) do
    "⏳ *#{escape(sentinel.name)}* was created 3 days ago and has never checked in"
  end

  defp format_message(sentinel, :paused_reminder) do
    "⏸ *#{escape(sentinel.name)}* has been paused for 3 days"
  end

  defp post_message(bot_token, chat_id, text) do
    url = "#{@telegram_api}/bot#{bot_token}/sendMessage"

    body =
      Jason.encode!(%{
        chat_id: chat_id,
        text: text,
        parse_mode: "MarkdownV2"
      })

    request =
      Finch.build(:post, url, [{"content-type", "application/json"}], body)

    case Finch.request(request, Jagua.Finch) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning("Telegram API returned #{status}: #{resp_body}")
        {:error, :telegram_error}

      {:error, reason} ->
        Logger.error("Telegram request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Escape special characters for MarkdownV2
  defp escape(text) do
    String.replace(text, ~r/([_*\[\]()~`>#+=|{}.!-])/, "\\\\\\1")
  end
end
