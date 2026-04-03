defmodule Bridge.Router do
  use Plug.Router
  require Logger

  plug Plug.Logger
  plug :match

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug :dispatch

  post "/webhook" do
    with :ok <- check_auth(conn),
         %{"title" => title, "message" => message} <- conn.body_params do
      case forward_to_ntfy(title, message) do
        :ok ->
          send_resp(conn, 200, "ok")

        {:error, reason} ->
          Logger.error("ntfy forward failed: #{inspect(reason)}")
          send_resp(conn, 502, "upstream error")
      end
    else
      :unauthorized -> send_resp(conn, 401, "unauthorized")
      _ -> send_resp(conn, 400, "bad request")
    end
  end

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp check_auth(conn) do
    case System.get_env("AUTH_TOKEN") do
      nil ->
        :ok

      expected ->
        case Plug.Conn.get_req_header(conn, "authorization") do
          ["Bearer " <> token] when token == expected -> :ok
          received ->
            Logger.error("auth mismatch — received: #{inspect(received)}, expected length: #{String.length(expected)}")
            :unauthorized
        end
    end
  end

  defp forward_to_ntfy(title, message) do
    url = System.get_env("NTFY_URL", "http://ntfy:80/") |> String.to_charlist()
    topic = System.get_env("NTFY_TOPIC", "alerts")
    token = System.get_env("NTFY_TOKEN", "")

    body =
      Jason.encode!(%{topic: topic, title: title, message: message, priority: 3})

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"authorization", ~c"Bearer #{token}"}
    ]

    case :httpc.request(:post, {url, headers, ~c"application/json", body}, [{:timeout, 5000}], []) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
        :ok

      {:ok, {{_, status, _}, _, resp_body}} ->
        {:error, {status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
