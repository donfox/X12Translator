defmodule X12Bridge.Repo.Migrations.AddDeliveryTrackingToJobs do
  use Ecto.Migration

  def change do
    alter table(:conversion_jobs) do
      add :input_path, :text, comment: "Full path where input X12 file was read"
      add :output_path, :text, comment: "Full path where JSON output was written"
      add :delivery_status, :string, comment: "Delivery status (received/ready/picked_up/deleted)"
      add :picked_up_at, :utc_datetime, comment: "Timestamp when JSON was picked up"
      add :deleted_at, :utc_datetime, comment: "Timestamp when input file was deleted"
    end

    create index(:conversion_jobs, [:delivery_status], comment: "Find jobs by delivery status")
  end
end
