defmodule X12Bridge.Repo.Migrations.AddX12ContentToJobs do
  use Ecto.Migration

  def change do
    alter table(:conversion_jobs) do
      add :x12_content, :text
    end
  end
end
