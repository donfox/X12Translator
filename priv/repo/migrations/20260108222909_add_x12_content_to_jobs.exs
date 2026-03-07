defmodule X12Translator.Repo.Migrations.AddX12ContentToJobs do
  use Ecto.Migration

  def change do
    # =========================================================================
    # Store original X12 content for round-trip validation
    # =========================================================================
    # After converting X12→JSON, we rebuild X12 from the JSON and compare it
    # with the original to ensure no data was lost (byte-for-byte match).
    # This requires storing the original X12 content for validation.
    # =========================================================================
    alter table(:conversion_jobs) do
      add :x12_content, :text, comment: "Original X12 content (used for round-trip validation)"
    end
  end
end
