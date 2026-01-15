defmodule X12Bridge.Repo.Migrations.CreateConversionBatches do
  use Ecto.Migration

  def change do
    # =========================================================================
    # conversion_batches: Track batch processing sessions
    # =========================================================================
    # Each batch represents a user's processing session containing multiple files.
    # Batches progress through two stages:
    #   Stage 1 (FREE): Verification - validates X12 structure, counts claims
    #   Stage 2 (BILLED): Translation - converts X12 to JSON, validates round-trip
    #
    # Status flow: uploaded → verifying → verified → translating → translated
    # =========================================================================
    create table(:conversion_batches, primary_key: false) do
      # Identification
      add :id, :uuid, primary_key: true

      # Batch metadata
      add :name, :string, comment: "User-provided batch name/identifier"
      add :total_files, :integer, comment: "Total files in this batch"

      # Processing progress tracking
      add :completed_files, :integer,
        default: 0,
        comment: "Files that finished (success or failure)"

      add :failed_files, :integer, default: 0, comment: "Files that encountered errors"

      add :status, :string,
        default: "pending",
        comment: "Current batch status (pending/processing/completed/failed)"

      timestamps()
    end

    # =========================================================================
    # conversion_jobs: Track individual file processing
    # =========================================================================
    # Each job represents a single file within a batch, with separate tracking
    # for verification (Stage 1) and translation (Stage 2).
    # =========================================================================
    create table(:conversion_jobs, primary_key: false) do
      # Identification & relationships
      add :id, :uuid, primary_key: true

      add :batch_id, references(:conversion_batches, type: :uuid, on_delete: :delete_all),
        comment: "Parent batch"

      # File metadata
      add :original_filename, :string, comment: "Original filename of uploaded file"
      add :file_size, :integer, comment: "File size in bytes"

      # Processing status & progress
      add :status, :string,
        default: "pending",
        comment: "Current job status (pending/processing/completed/failed)"

      add :json_result, :text,
        comment: "Converted JSON output (stored after successful translation)"

      add :error_message, :text, comment: "Error details if processing failed"
      add :processing_time_ms, :integer, comment: "Total milliseconds spent processing this file"
      add :progress, :integer, default: 0, comment: "Processing progress percentage (0-100)"

      timestamps()
    end

    # Indexes for common queries
    create index(:conversion_jobs, [:batch_id], comment: "Find all jobs in a batch")
    create index(:conversion_jobs, [:status], comment: "Find jobs by status")
  end
end
