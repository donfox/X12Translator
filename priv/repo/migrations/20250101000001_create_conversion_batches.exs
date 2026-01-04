defmodule X12Bridge.Repo.Migrations.CreateConversionBatches do
  use Ecto.Migration

  def change do
    # Batches table
    create table(:conversion_batches, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string
      add :total_files, :integer
      add :completed_files, :integer, default: 0
      add :failed_files, :integer, default: 0
      add :status, :string, default: "pending"  # pending, processing, completed, failed

      timestamps()
    end

    # Jobs table
    create table(:conversion_jobs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :batch_id, references(:conversion_batches, type: :uuid, on_delete: :delete_all)
      add :original_filename, :string
      add :file_size, :integer
      add :status, :string, default: "pending"  # pending, processing, completed, failed
      add :json_result, :text
      add :error_message, :text
      add :processing_time_ms, :integer
      add :progress, :integer, default: 0

      timestamps()
    end

    create index(:conversion_jobs, [:batch_id])
    create index(:conversion_jobs, [:status])
  end
end
