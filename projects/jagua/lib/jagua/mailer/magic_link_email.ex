defmodule Jagua.Mailer.MagicLinkEmail do
  @moduledoc "Builds and delivers magic link login emails via Swoosh."

  import Swoosh.Email

  alias Jagua.Mailer

  def deliver(to_email, raw_token) do
    url = JaguaWeb.Endpoint.url() <> "/auth/confirm/#{raw_token}"

    new()
    |> from({"Jagua", "noreply@jagua.app"})
    |> to(to_email)
    |> subject("Your Jagua login link")
    |> text_body("""
    Click the link below to log in to Jagua.
    This link expires in 15 minutes and can only be used once.

    #{url}

    If you didn't request this, you can safely ignore this email.
    """)
    |> html_body("""
    <!DOCTYPE html>
    <html>
      <body style="font-family: sans-serif; max-width: 480px; margin: 40px auto; padding: 0 20px; color: #111;">
        <h2 style="margin-bottom: 8px;">Log in to Jagua</h2>
        <p style="color: #555;">Click the button below to sign in. This link expires in 15 minutes.</p>
        <a href="#{url}"
           style="display:inline-block;margin:24px 0;padding:12px 24px;background:#1a1a1a;color:#fff;text-decoration:none;border-radius:6px;font-weight:600;">
          Sign in to Jagua
        </a>
        <p style="color:#999;font-size:13px;">
          Or copy this URL into your browser:<br>
          <a href="#{url}" style="color:#555;">#{url}</a>
        </p>
        <p style="color:#ccc;font-size:12px;">If you didn't request this, ignore this email.</p>
      </body>
    </html>
    """)
    |> Mailer.deliver()
  end
end
