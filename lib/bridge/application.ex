defmodule Bridge.Application do
  use Application

  @impl true
  def start(_type, _args) do
    :inets.start()
    :ssl.start()

    port = System.get_env("PORT", "4000") |> String.to_integer()

    children = [
      {Bandit, plug: Bridge.Router, port: port, startup_log: false}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Bridge.Supervisor)
  end
end
