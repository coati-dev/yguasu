defmodule Jagua.Alerts.Channels.Email do
  @moduledoc "Sends alert emails via Swoosh."

  import Swoosh.Email

  alias Jagua.Mailer

  def send(channel, sentinel, type) do
    emails = Map.get(channel.config, "emails", [])

    Enum.each(emails, fn recipient ->
      build_email(recipient, sentinel, type)
      |> Mailer.deliver()
    end)
  end

  defp build_email(to, sentinel, type) do
    {subject, body_text, body_html} = content(sentinel, type)

    new()
    |> from({"Jagua", "noreply@jagua.app"})
    |> to(to)
    |> subject(subject)
    |> text_body(body_text)
    |> html_body(body_html)
  end

  defp content(sentinel, :failed) do
    subject = "[Jagua] #{sentinel.name} missed its check-in"
    url = sentinel_url(sentinel)

    text = """
    Sentinel "#{sentinel.name}" missed its expected check-in.

    Interval: #{sentinel.interval}
    Status: Failed

    View details: #{url}
    """

    html = alert_html("🔴 Sentinel missed check-in", sentinel, :failed, url)
    {subject, text, html}
  end

  defp content(sentinel, :errored) do
    subject = "[Jagua] #{sentinel.name} reported an error"
    url = sentinel_url(sentinel)

    text = """
    Sentinel "#{sentinel.name}" checked in with a non-zero exit code.

    Interval: #{sentinel.interval}
    Status: Errored

    View details: #{url}
    """

    html = alert_html("🟠 Sentinel reported an error", sentinel, :errored, url)
    {subject, text, html}
  end

  defp content(sentinel, :recovered) do
    subject = "[Jagua] #{sentinel.name} has recovered"
    url = sentinel_url(sentinel)

    text = """
    Sentinel "#{sentinel.name}" has recovered — it checked in successfully.

    Interval: #{sentinel.interval}

    View details: #{url}
    """

    html = alert_html("✅ Sentinel has recovered", sentinel, :recovered, url)
    {subject, text, html}
  end

  defp content(sentinel, :pending_reminder) do
    subject = "[Jagua] #{sentinel.name} hasn't checked in yet"
    url = sentinel_url(sentinel)

    text = """
    Sentinel "#{sentinel.name}" was created 3 days ago and has never checked in.

    Make sure your job is configured to call the check-in URL:
    #{check_in_url(sentinel)}

    View details: #{url}
    """

    html = alert_html("⏳ Sentinel hasn't checked in yet", sentinel, :pending_reminder, url)
    {subject, text, html}
  end

  defp content(sentinel, :paused_reminder) do
    subject = "[Jagua] #{sentinel.name} has been paused for 3 days"
    url = sentinel_url(sentinel)

    text = """
    Sentinel "#{sentinel.name}" has been paused for 3 days. Don't forget to unpause it when your job resumes.

    View details: #{url}
    """

    html = alert_html("⏸ Sentinel has been paused for 3 days", sentinel, :paused_reminder, url)
    {subject, text, html}
  end

  defp alert_html(headline, sentinel, _type, url) do
    """
    <!DOCTYPE html>
    <html>
      <body style="font-family: sans-serif; max-width: 480px; margin: 40px auto; padding: 0 20px; color: #111;">
        <h2 style="margin-bottom: 8px;">#{headline}</h2>
        <p style="color: #555;"><strong>#{sentinel.name}</strong></p>
        <a href="#{url}"
           style="display:inline-block;margin:24px 0;padding:12px 24px;background:#1a1a1a;color:#fff;text-decoration:none;border-radius:6px;font-weight:600;">
          View Sentinel
        </a>
        <p style="color:#ccc;font-size:12px;">You are receiving this because you have alert notifications enabled for this project.</p>
      </body>
    </html>
    """
  end

  defp sentinel_url(sentinel) do
    JaguaWeb.Endpoint.url() <> "/projects/#{sentinel.project_id}/sentinels/#{sentinel.token}"
  end

  defp check_in_url(sentinel) do
    JaguaWeb.Endpoint.url() <> "/in/#{sentinel.token}"
  end
end
