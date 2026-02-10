defmodule X12Bridge.Repo.Migrations.AddSubmittedByToBatches do
  use Ecto.Migration

  def change do
    alter table(:conversion_batches) do
      add :submitted_by, :string
    end

    create index(:conversion_batches, [:submitted_by])
  end
end
