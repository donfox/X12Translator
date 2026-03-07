defmodule X12Translator.Repo.Migrations.AddRoundtripValidationToJobs do
  use Ecto.Migration

  def change do
    # =========================================================================
    # Round-trip validation fields for data integrity assurance
    # =========================================================================
    # After translating X12→JSON and rebuilding X12 from JSON, we validate
    # that the reconstructed X12 matches the original (within whitespace
    # normalization). This ensures no data loss during the conversion process.
    #
    # Process:
    #   1. Parse original X12 → extract segments
    #   2. Build JSON structure
    #   3. Rebuild X12 from JSON
    #   4. Compare rebuilt with original
    #   5. Block translation if data differs
    # =========================================================================
    alter table(:conversion_jobs) do
      # Validation result & details
      add :roundtrip_valid, :boolean,
        comment: "Whether X12→JSON→X12 reconstruction matches original"

      add :roundtrip_diff, :text, comment: "Segment-by-segment diff if reconstruction failed"
      add :roundtrip_error, :text, comment: "Error message if round-trip validation failed"
    end
  end
end
