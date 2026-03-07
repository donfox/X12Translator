defmodule X12Translator.Repo do
  use Ecto.Repo,
    otp_app: :x12_translator,
    adapter: Ecto.Adapters.Postgres
end
