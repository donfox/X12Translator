defmodule X12Bridge.Conversions.Job do
  @moduledoc """
  X12 Conversion Job - tracks individual file processing through the two-stage pipeline.

  ## Status Flow

  Each job progresses through verification (Stage 1) and translation (Stage 2):

  ```
  uploaded → verifying → verified/failed_verification
                           ↓
                        translating → translated/failed_translation
  ```

  ## Fields

  ### File Information
  - `original_filename` - Name of the uploaded X12 file
  - `file_size` - Size in bytes

  ### Processing Status
  - `status` - Current job status (see JobStatus module)
  - `progress` - Processing progress percentage (0-100)
  - `processing_time_ms` - Total milliseconds spent processing

  ### Results & Content
  - `x12_content` - Original X12 EDI content (stored for round-trip validation)
  - `json_result` - Converted JSON output
  - `error_message` - Error details if processing failed

  ### Verification (Stage 1 - FREE)
  - `verification_result` - Map containing verification metadata
  - `verification_error` - Error message if verification failed
  - `verified_at` - Timestamp when verification completed
  - `claim_count` - Number of CLM segments (billable claims) found

  ### Translation (Stage 2 - BILLED)
  - `claims_charged` - Number of claims actually billed
  - `translated_at` - Timestamp when translation completed

  ### Round-trip Validation
  - `roundtrip_valid` - Whether X12→JSON→X12 matches original
  - `roundtrip_diff` - Diff details if round-trip failed
  - `roundtrip_error` - Error message if validation failed
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias X12Bridge.Conversions.Status

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversion_jobs" do
    # File metadata
    field :original_filename, :string
    field :file_size, :integer

    # Processing status & progress
    field :status, :string, default: "uploaded"
    field :progress, :integer, default: 0
    field :processing_time_ms, :integer

    # Content & results
    field :x12_content, :string
    field :json_result, :string
    field :error_message, :string

    # Verification (Stage 1: FREE)
    field :verification_result, :map
    field :verification_error, :string
    field :verified_at, :utc_datetime
    field :claim_count, :integer, default: 0

    # Translation (Stage 2: BILLED)
    field :claims_charged, :integer, default: 0
    field :translated_at, :utc_datetime

    # Round-trip validation
    field :roundtrip_valid, :boolean
    field :roundtrip_diff, :string
    field :roundtrip_error, :string

    belongs_to :batch, X12Bridge.Conversions.Batch

    timestamps()
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :batch_id,
      :original_filename,
      :file_size,
      :status,
      :json_result,
      :x12_content,
      :error_message,
      :processing_time_ms,
      :progress,
      :verification_result,
      :verification_error,
      :verified_at,
      :claim_count,
      :claims_charged,
      :translated_at,
      :roundtrip_valid,
      :roundtrip_diff,
      :roundtrip_error
    ])
    |> validate_required([:original_filename])
    |> validate_inclusion(:status, Status.list_all_strings())
  end
end
