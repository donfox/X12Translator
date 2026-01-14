defmodule X12Bridge.Repo.Migrations.AddVerificationFieldsToJobs do
  use Ecto.Migration

  def change do
    alter table(:conversion_jobs) do
      # Verification fields
      add :verification_result, :jsonb
      add :verification_error, :text
      add :verified_at, :utc_datetime
      add :claim_count, :integer, default: 0
      add :claims_charged, :integer, default: 0
      add :translated_at, :utc_datetime
    end

    # Add indexes for common queries
    create index(:conversion_jobs, [:verified_at])
    create index(:conversion_jobs, [:claim_count])
  end
end
