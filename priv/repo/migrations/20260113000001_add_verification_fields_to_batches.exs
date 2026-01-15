defmodule X12Bridge.Repo.Migrations.AddVerificationFieldsToBatches do
  use Ecto.Migration

  def change do
    # =========================================================================
    # Batch-level tracking for two-stage pipeline progress
    # =========================================================================
    # Batches now track:
    #   - Stage 1 (FREE) verification: verified_files, failed_verification_files
    #   - Stage 2 (BILLED) translation: translated_files, failed_translation_files
    #   - Billing: total_claims, total_claims_charged
    #
    # This allows batches to report:
    #   "5 verified, 2 failed verification" → "3 translated, 2 failed translation"
    # =========================================================================
    alter table(:conversion_batches) do
      # Stage 1: Verification (FREE)
      add :verified_files, :integer, default: 0, comment: "Files that passed verification"

      add :failed_verification_files, :integer,
        default: 0,
        comment: "Files that failed verification"

      # Stage 2: Translation (BILLED)
      add :translated_files, :integer, default: 0, comment: "Files successfully translated"

      add :failed_translation_files, :integer,
        default: 0,
        comment: "Files that failed translation"

      # Billing tracking
      add :total_claims, :integer, default: 0, comment: "Total billable claims across all files"
      add :total_claims_charged, :integer, default: 0, comment: "Total claims successfully billed"
    end
  end
end
