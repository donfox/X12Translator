defmodule X12Bridge.Conversions.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversion_jobs" do
    field :original_filename, :string
    field :file_size, :integer
    field :status, :string, default: "pending"
    field :json_result, :string
    field :x12_content, :string
    field :error_message, :string
    field :processing_time_ms, :integer
    field :progress, :integer, default: 0

    # Round-trip validation fields
    field :roundtrip_valid, :boolean
    field :roundtrip_diff, :string
    field :roundtrip_error, :string

    belongs_to :batch, X12Bridge.Conversions.Batch

    timestamps()
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:batch_id, :original_filename, :file_size, :status, :json_result, :x12_content, :error_message, :processing_time_ms, :progress, :roundtrip_valid, :roundtrip_diff, :roundtrip_error])
    |> validate_required([:original_filename])
    |> validate_inclusion(:status, ["pending", "processing", "completed", "failed"])
  end
end
