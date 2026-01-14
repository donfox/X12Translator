defmodule X12Bridge.Conversions.Batch do
  @moduledoc """
  Batch processing session - tracks multiple files through verification and translation.

  ## Status Flow

  Batches progress through two stages:

  ```
  uploaded → verifying → verified → translating → translated
  ```

  Some files may fail verification or translation, but the batch continues.

  ## Fields

  ### Batch Information
  - `name` - User-provided batch identifier
  - `total_files` - Total files in this batch

  ### Processing Status
  - `status` - Current batch status (uploaded/verifying/verified/...)
  - `completed_files` - Files that finished (success or failure)
  - `failed_files` - Files that failed

  ### Verification Tracking (Stage 1 - FREE)
  - `verified_files` - Files that passed verification
  - `failed_verification_files` - Files that failed verification

  ### Translation Tracking (Stage 2 - BILLED)
  - `translated_files` - Files successfully translated
  - `failed_translation_files` - Files that failed translation

  ### Billing Tracking
  - `total_claims` - Total CLM segments across all files
  - `total_claims_charged` - Total claims actually billed
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias X12Bridge.JobStatus

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversion_batches" do
    # Batch information
    field :name, :string
    field :total_files, :integer

    # Overall processing status
    field :completed_files, :integer, default: 0
    field :failed_files, :integer, default: 0
    field :status, :string, default: "uploaded"

    # Stage 1: Verification (FREE)
    field :verified_files, :integer, default: 0
    field :failed_verification_files, :integer, default: 0

    # Stage 2: Translation (BILLED)
    field :translated_files, :integer, default: 0
    field :failed_translation_files, :integer, default: 0

    # Billing tracking
    field :total_claims, :integer, default: 0
    field :total_claims_charged, :integer, default: 0

    has_many :jobs, X12Bridge.Conversions.Job, foreign_key: :batch_id

    timestamps()
  end

  @doc false
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :name, :total_files, :completed_files, :failed_files, :status,
      :verified_files, :failed_verification_files, :translated_files, :failed_translation_files,
      :total_claims, :total_claims_charged
    ])
    |> validate_required([:name, :total_files])
    |> validate_inclusion(:status, JobStatus.list_batch_status_strings())
  end

  def progress_percentage(%__MODULE__{} = batch) do
    if batch.total_files > 0 do
      round((batch.completed_files + batch.failed_files) / batch.total_files * 100)
    else
      0
    end
  end
end
