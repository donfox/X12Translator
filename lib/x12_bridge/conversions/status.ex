defmodule X12Bridge.Conversions.Status do
  @moduledoc """
  Centralized status definitions for jobs and batches.

  Provides a single source of truth for all valid statuses (jobs and batches),
  preventing typos and making it easy to enumerate all states.

  ## Job Status Flow

  ```
                      ┌─ failed_verification
                      │  (verify error)
  uploaded → verifying ┤
                      └─ verified → translating ┐
                                                ├─ translated ✓
                                                └─ failed_translation ✗
                                                   (conversion/round-trip error)
  ```

  ## Batch Status Flow

  Batches track overall progress of multi-file processing:
  - `uploaded` - Files staged, ready for verification
  - `verifying` - Running Stage 1 (FREE verification)
  - `verified` - Verification complete (may have some failures)
  - `translating` - Running Stage 2 (BILLED translation) on verified files
  - `translated` - Translation complete
  - `completed` - Batch fully processed and archived
  - `failed` - Batch failed before completion

  ## Legacy Statuses

  These statuses are for backward compatibility with single-stage processing:
  - `pending` - Legacy: queued for processing
  - `processing` - Legacy: actively processing
  """

  # Job-specific statuses (two-stage pipeline)
  @job_statuses [
    :uploaded,
    :verifying,
    :verified,
    :failed_verification,
    :translating,
    :translated,
    :failed_translation,
    # Legacy single-stage
    :pending,
    :processing,
    :completed,
    :failed
  ]

  # Batch-specific statuses (multi-file tracking)
  @batch_statuses [
    :uploaded,
    :verifying,
    :verified,
    :translating,
    :translated,
    :completed,
    :failed,
    # Legacy
    :pending,
    :processing
  ]

  @all_statuses (@job_statuses ++ @batch_statuses) |> Enum.uniq()
  @all_statuses_strings Enum.map(@all_statuses, &to_string/1)

  @doc """
  List all valid job statuses as atoms.

  ## Examples

      iex> Status.list_all()
      [:uploaded, :verifying, :verified, :failed_verification, :translating, :translated, :failed_translation, :pending, :processing, :completed, :failed]
  """
  def list_all, do: @job_statuses

  @doc """
  List all valid job and batch statuses as atoms.

  Use when validating either job or batch status fields.
  """
  def list_all_combined, do: @all_statuses

  @doc """
  List all valid job statuses as strings.

  Used for database validation and JSON serialization.

  ## Examples

      iex> Status.list_all_strings()
      ["uploaded", "verifying", "verified", "failed_verification", "translating", "translated", "failed_translation", "pending", "processing", "completed", "failed"]
  """
  def list_all_strings, do: Enum.map(@job_statuses, &to_string/1)

  @doc """
  List all valid batch statuses as strings.

  Used for database validation.
  """
  def list_batch_status_strings, do: Enum.map(@batch_statuses, &to_string/1)

  @doc """
  Check if a status is valid for jobs.

  Accepts both atoms and strings for flexibility.

  ## Examples

      iex> Status.valid?(:uploaded)
      true

      iex> Status.valid?("uploaded")
      true

      iex> Status.valid?(:invalid)
      false
  """
  def valid?(status) when is_atom(status), do: status in @job_statuses
  def valid?(status) when is_binary(status), do: status in list_all_strings()
  def valid?(_), do: false

  @doc """
  Check if a status indicates completion (success or failure).

  ## Examples

      iex> Status.complete?(:translated)
      true

      iex> Status.complete?(:failed_translation)
      true

      iex> Status.complete?(:verifying)
      false
  """
  def complete?(:translated), do: true
  def complete?(:failed_translation), do: true
  def complete?(:failed_verification), do: true
  def complete?(:completed), do: true
  def complete?(:failed), do: true
  def complete?(_), do: false

  @doc """
  Check if a status indicates success.

  ## Examples

      iex> Status.success?(:translated)
      true

      iex> Status.success?(:failed_translation)
      false
  """
  def success?(:translated), do: true
  def success?(:completed), do: true
  def success?(_), do: false

  @doc """
  Check if a status indicates failure.

  ## Examples

      iex> Status.failed?(:failed_translation)
      true

      iex> Status.failed?(:translated)
      false
  """
  def failed?(:failed_translation), do: true
  def failed?(:failed_verification), do: true
  def failed?(:failed), do: true
  def failed?(_), do: false

  @doc """
  Check if status is in verifying stage.
  """
  def verifying?(:verifying), do: true
  def verifying?(_), do: false

  @doc """
  Check if status is in translating stage.
  """
  def translating?(:translating), do: true
  def translating?(_), do: false
end
