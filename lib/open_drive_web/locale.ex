defmodule OpenDriveWeb.Locale do
  @moduledoc """
  Resolves the active locale from params, session, and request headers.
  """

  @behaviour Plug

  import Plug.Conn

  alias OpenDriveWeb.Gettext, as: Backend

  @gettext_config Application.compile_env(:open_drive, Backend, [])
  @session_key :locale
  @default_locale Keyword.get(@gettext_config, :default_locale, "pt_BR")
  @supported_locales Keyword.get(@gettext_config, :locales, ~w(en pt_BR))
  @locale_aliases %{
    "en" => "en",
    "en-us" => "en",
    "en_us" => "en",
    "pt" => "pt_BR",
    "pt-br" => "pt_BR",
    "pt_br" => "pt_BR",
    "pt-BR" => "pt_BR",
    "pt_BR" => "pt_BR"
  }
  @html_lang_by_locale %{
    "en" => "en",
    "pt_BR" => "pt-BR"
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    locale = locale_from_conn(conn)

    Gettext.put_locale(Backend, locale)

    conn
    |> assign(:locale, locale)
    |> put_session(@session_key, locale)
  end

  def on_mount(:default, params, session, socket) do
    locale =
      params["locale"] |> normalize_locale() || session["locale"] |> normalize_locale() ||
        default_locale()

    Gettext.put_locale(Backend, locale)

    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  def default_locale, do: @default_locale
  def supported_locales, do: @supported_locales

  def html_lang(locale) do
    locale
    |> normalize_locale()
    |> case do
      nil -> @default_locale
      normalized -> normalized
    end
    |> then(&Map.fetch!(@html_lang_by_locale, &1))
  end

  def normalize_locale(nil), do: nil

  def normalize_locale(locale) when is_binary(locale) do
    locale
    |> String.trim()
    |> case do
      "" ->
        nil

      trimmed ->
        Map.get(@locale_aliases, trimmed) ||
          Map.get(@locale_aliases, String.downcase(trimmed))
    end
  end

  defp locale_from_conn(conn) do
    conn.params["locale"]
    |> normalize_locale()
    |> Kernel.||(get_session(conn, @session_key) |> normalize_locale())
    |> Kernel.||(accept_language_locale(get_req_header(conn, "accept-language")))
    |> Kernel.||(default_locale())
  end

  defp accept_language_locale([header | _]) do
    header
    |> String.split(",")
    |> Enum.map(fn entry ->
      entry
      |> String.split(";")
      |> List.first()
      |> String.trim()
    end)
    |> Enum.find_value(&normalize_locale/1)
  end

  defp accept_language_locale(_), do: nil
end
