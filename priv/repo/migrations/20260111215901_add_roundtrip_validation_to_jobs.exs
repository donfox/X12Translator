defmodule X12Bridge.Repo.Migrations.AddRoundtripValidationToJobs do
  use Ecto.Migration

  def change do
    alter table(:conversion_jobs) do
      add :roundtrip_valid, :boolean
      add :roundtrip_diff, :text
      add :roundtrip_error, :text
    end
  end
end
