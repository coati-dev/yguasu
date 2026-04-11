defmodule Jagua.Accounts.Auth do
  @moduledoc """
  Magic link authentication context.
  Handles token generation, hashing, email dispatch, and confirmation.
  """

  require Ash.Query

  @token_validity_minutes 15

  @doc """
  Requests a magic link for the given email address.
  Creates the user if they don't exist yet (open registration).
  Returns :ok regardless of whether the email exists (prevents enumeration).
  """
  def request_magic_link(email) do
    with {:ok, user} <- get_or_create_user(email),
         {:ok, raw_token} <- create_magic_link(user) do
      Jagua.Mailer.MagicLinkEmail.deliver(user.email, raw_token)
      :ok
    else
      _ -> :ok
    end
  end

  @doc """
  Confirms a magic link token. Returns {:ok, user} or {:error, :invalid}.
  """
  def confirm_magic_link(raw_token) do
    token_hash = hash_token(raw_token)

    query =
      Jagua.Accounts.MagicLink
      |> Ash.Query.for_read(:by_token_hash, %{token_hash: token_hash})
      |> Ash.Query.load(:user)

    case Ash.read_one(query, domain: Jagua.Accounts) do
      {:ok, nil} ->
        {:error, :invalid}

      {:ok, magic_link} ->
        magic_link
        |> Ash.Changeset.for_update(:consume, %{})
        |> Ash.update!(domain: Jagua.Accounts)
        {:ok, magic_link.user}

      {:error, _} ->
        {:error, :invalid}
    end
  end

  # Private

  defp get_or_create_user(email) do
    query =
      Jagua.Accounts.User
      |> Ash.Query.for_read(:by_email, %{email: email})

    case Ash.read_one(query, domain: Jagua.Accounts) do
      {:ok, nil} ->
        Jagua.Accounts.User
        |> Ash.Changeset.for_create(:create, %{email: email})
        |> Ash.create(domain: Jagua.Accounts)

      {:ok, user} ->
        {:ok, user}

      error ->
        error
    end
  end

  defp create_magic_link(user) do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_hash = hash_token(raw_token)
    expires_at = DateTime.add(DateTime.utc_now(), @token_validity_minutes, :minute)

    result =
      Jagua.Accounts.MagicLink
      |> Ash.Changeset.for_create(:create, %{
        user_id: user.id,
        token_hash: token_hash,
        expires_at: expires_at
      })
      |> Ash.create(domain: Jagua.Accounts)

    case result do
      {:ok, _} -> {:ok, raw_token}
      error -> error
    end
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
