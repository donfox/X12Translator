defmodule X12Bridge.JobStatus do
  @moduledoc """
  Centralized job status definitions.

  Provides a single source of truth for all valid job statuses,
  preventing typos and making it easy to enumerate all states.

  ## Status Flow

  ```
                      ┌─ failed_verification
                      │  (verify error)
  uploaded → verifying ┤
                      └─ verified → translating ┐
                                                ├─ translated ✓
                                                └─ failed_translation ✗
                                                   (conversion/round-trip error)
  ```

  ## Legacy Statuses

  These statuses are for backward compatibility with single-stage processing:
  - `pending` - Legacy: queued for processing
  - `processing` - Legacy: actively processing
  - `completed` - Legacy: finished successfully
  - `failed` - Legacy: finished with error
  """

  @statuses [
    # Two-stage pipeline
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

  @statuses_strings Enum.map(@statuses, &to_string/1)

  @doc """
  List all valid job statuses as atoms.

  ## Examples

      iex> JobStatus.list_all()
      [:uploaded, :verifying, :verified, :failed_verification, :translating, :translated, :failed_translation, :pending, :processing, :completed, :failed]
  """
  def list_all, do: @statuses

  @doc """
  List all valid job statuses as strings.

  Used for database validation and JSON serialization.

  ## Examples

      iex> JobStatus.list_all_strings()
      ["uploaded", "verifying", "verified", "failed_verification", "translating", "translated", "failed_translation", "pending", "processing", "completed", "failed"]
  """
  def list_all_strings, do: @statuses_strings

  @doc """
  Check if a status is valid.

  Accepts both atoms and strings for flexibility.

  ## Examples

      iex> JobStatus.valid?(:uploaded)
      true

      iex> JobStatus.valid?("uploaded")
      true

      iex> JobStatus.valid?(:invalid)
      false
  """
  def valid?(status) when is_atom(status), do: status in @statuses
  def valid?(status) when is_binary(status), do: status in @statuses_strings
  def valid?(_), do: false

  @doc """
  Check if a status indicates completion (success or failure).

  ## Examples

      iex> JobStatus.complete?(:translated)
      true

      iex> JobStatus.complete?(:failed_translation)
      true

      iex> JobStatus.complete?(:verifying)
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

      iex> JobStatus.success?(:translated)
      true

      iex> JobStatus.success?(:failed_translation)
      false
  """
  def success?(:translated), do: true
  def success?(:completed), do: true
  def success?(_), do: false

  @doc """
  Check if a status indicates failure.

  ## Examples

      iex> JobStatus.failed?(:failed_translation)
      true

      iex> JobStatus.failed?(:translated)
      false
  """
  def failed?(:failed_translation), do: true
  def failed?(:failed_verification), do: true
  def failed?(:failed), do: true
  def failed?(_), do: false

  @doc """
  Check if a status is part of the verification stage.

  ## Examples

      iex> JobStatus.verifying?(:verifying)
      true

      iex> JobStatus.verifying?(:verified)
      true

      iex> JobStatus.verifying?(:translating)
      false
  """
  def verifying?(:verifying), do: true
  def verifying?(:verified), do: true
  def verifying?(:failed_verification), do: true
  def verifying?(_), do: false

  @doc """
  Check if a status is part of the translation stage.

  ## Examples

      iex> JobStatus.translating?(:translating)
      true

      iex> JobStatus.translating?(:translated)
      true

      iex> JobStatus.translating?(:verifying)
      false
  """
  def translating?(:translating), do: true
  def translating?(:translated), do: true
  def translating?(:failed_translation), do: true
  def translating?(_), do: false
end
