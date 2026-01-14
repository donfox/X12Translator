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
    field :status, :string, default: "uploaded"

    # Verification tracking
    field :verified_files, :integer, default: 0
    field :failed_verification_files, :integer, default: 0
    field :translated_files, :integer, default: 0
    field :failed_translation_files, :integer, default: 0

    # Claim tracking for billing
    field :total_claims, :integer, default: 0
    field :total_claims_charged, :integer, default: 0

    has_many :jobs, X12Bridge.Conversions.Job, foreign_key: :batch_id

    timestamps()
  end

  # Valid batch statuses for the multi-stage pipeline
  @valid_statuses ~w(uploaded verifying verified translating translated completed failed pending processing)

  @doc false
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :name, :total_files, :completed_files, :failed_files, :status,
      :verified_files, :failed_verification_files, :translated_files, :failed_translation_files,
      :total_claims, :total_claims_charged
    ])
    |> validate_required([:name, :total_files])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def progress_percentage(%__MODULE__{} = batch) do
    if batch.total_files > 0 do
      round((batch.completed_files + batch.failed_files) / batch.total_files * 100)
    else
      0
    end
  end
end
