defmodule X12Bridge.Conversions.Batch do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversion_batches" do
    field :name, :string
    field :total_files, :integer
    field :completed_files, :integer, default: 0
    field :failed_files, :integer, default: 0
    field :status, :string, default: "pending"

    has_many :jobs, X12Bridge.Conversions.Job, foreign_key: :batch_id

    timestamps()
  end

  @doc false
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [:name, :total_files, :completed_files, :failed_files, :status])
    |> validate_required([:name, :total_files])
    |> validate_inclusion(:status, ["pending", "processing", "completed", "failed"])
  end

  def progress_percentage(%__MODULE__{} = batch) do
    if batch.total_files > 0 do
      round((batch.completed_files + batch.failed_files) / batch.total_files * 100)
    else
      0
    end
  end
end
