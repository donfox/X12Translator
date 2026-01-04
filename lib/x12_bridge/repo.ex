defmodule X12Bridge.Repo do
  use Ecto.Repo,
    otp_app: :x12_bridge,
    adapter: Ecto.Adapters.Postgres
end
