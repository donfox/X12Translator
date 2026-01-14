defmodule X12Bridge.Repo.Migrations.AddVerificationFieldsToBatches do
  use Ecto.Migration

  def change do
    alter table(:conversion_batches) do
      # Verification tracking
      add :verified_files, :integer, default: 0
      add :failed_verification_files, :integer, default: 0
      add :translated_files, :integer, default: 0
      add :failed_translation_files, :integer, default: 0

      # Claim tracking for billing
      add :total_claims, :integer, default: 0
      add :total_claims_charged, :integer, default: 0
    end
  end
end
