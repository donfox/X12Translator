defmodule X12Translator.Repo.Migrations.AddVerificationFieldsToJobs do
  use Ecto.Migration

  def change do
    # =========================================================================
    # Stage 1: Verification (FREE) - Fast pre-flight checks
    # =========================================================================
    # Before translating, we run lightweight verification to:
    #   - Validate X12 structure (envelope, delimiters, required segments)
    #   - Count billable claims (CLM segments)
    #   - Catch errors early without translation overhead
    #
    # This is FREE and FAST (~5-20ms per file) so users can preview costs
    # before committing to translation charges.
    # =========================================================================
    alter table(:conversion_jobs) do
      # Verification results
      add :verification_result, :jsonb,
        comment: "Verification metadata (transaction_type, claim_count, etc.)"

      add :verification_error, :text, comment: "Error message if verification failed"
      add :verified_at, :utc_datetime, comment: "Timestamp when verification completed"

      add :claim_count, :integer,
        default: 0,
        comment: "Number of billable claims (CLM segments) found"

      # =========================================================================
      # Stage 2: Translation (BILLED) - Full conversion + validation
      # =========================================================================
      # After verification passes, files are translated (X12→JSON with round-trip
      # validation). Billing happens ONLY for successfully translated files.
      # =========================================================================
      add :claims_charged, :integer,
        default: 0,
        comment: "Number of claims actually billed after successful translation"

      add :translated_at, :utc_datetime, comment: "Timestamp when translation completed"
    end

    # Indexes for common queries
    create index(:conversion_jobs, [:verified_at], comment: "Find recently verified files")
    create index(:conversion_jobs, [:claim_count], comment: "Query by claim count range")
  end
end
