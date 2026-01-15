defmodule X12Bridge.Conversions do
  @moduledoc """
  The Conversions context handles batch processing and job tracking.
  """

  import Ecto.Query
  alias X12Bridge.Repo
  alias X12Bridge.Conversions.{Batch, Job}
  alias X12Bridge.X12.{Converter, RoundtripValidator, Verifier}

  ## Batch functions

  @doc """
  Creates a new batch and triggers automatic cleanup of old batches.
  """
  def create_batch(attrs \\ %{}) do
    with {:ok, batch} <-
           %Batch{}
           |> Batch.changeset(attrs)
           |> Repo.insert() do
      # Automatically cleanup old batches after creating a new one
      cleanup_old_batches()
      {:ok, batch}
    end
  end

  @doc """
  Gets a batch with its jobs preloaded.
  """
  def get_batch!(id) do
    Batch
    |> Repo.get!(id)
    |> Repo.preload(:jobs)
  end

  @doc """
  Lists all batches, ordered by most recent.
  """
  def list_batches(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Batch
    |> order_by([b], desc: b.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(:jobs)
  end

  @doc """
  Updates a batch.
  """
  def update_batch(%Batch{} = batch, attrs) do
    batch
    |> Batch.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a batch and all its associated jobs (cascade).
  """
  def delete_batch(%Batch{} = batch) do
    Repo.delete(batch)
  end

  @doc """
  Deletes all batches and their associated jobs.
  Useful for clearing test data in development.
  """
  def delete_all_batches do
    {count, _} = Repo.delete_all(Batch)
    {:ok, count}
  end

  @doc """
  Cleans up old batches, keeping only the most recent N batches.
  The limit is configurable via application config.

  ## Options
    * `:keep` - Number of most recent batches to keep (default: from config or 50)

  ## Examples

      cleanup_old_batches()  # Uses config value
      cleanup_old_batches(keep: 100)  # Keep 100 most recent
  """
  def cleanup_old_batches(opts \\ []) do
    max_batches =
      Keyword.get(opts, :keep) ||
        Application.get_env(:x12_bridge, :batch_retention)[:max_batches] ||
        50

    # Get IDs of batches to keep (most recent N)
    batch_ids_to_keep =
      Batch
      |> order_by([b], desc: b.inserted_at)
      |> limit(^max_batches)
      |> select([b], b.id)
      |> Repo.all()

    # Delete batches not in the keep list
    {count, _} =
      Batch
      |> where([b], b.id not in ^batch_ids_to_keep)
      |> Repo.delete_all()

    {:ok, count}
  end

  ## Job functions

  @doc """
  Creates a new job.
  """
  def create_job(attrs \\ %{}) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single job.
  """
  def get_job!(id), do: Repo.get!(Job, id)

  @doc """
  Updates a job.
  """
  def update_job(%Job{} = job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists jobs for a specific batch.
  """
  def list_batch_jobs(batch_id) do
    Job
    |> where([j], j.batch_id == ^batch_id)
    |> order_by([j], asc: j.inserted_at)
    |> Repo.all()
  end

  ## Processing functions

  @doc """
  Processes a single file synchronously (for testing/small files).

  IMPORTANT: This includes round-trip validation as an initial phase.
  The conversion will FAIL if round-trip validation fails (strict mode).
  """
  def process_file_sync(file_content, _filename) do
    start_time = System.monotonic_time(:millisecond)

    # STEP 1: Perform round-trip validation FIRST
    validation_result = RoundtripValidator.validate(file_content)

    result =
      if validation_result.valid? do
        # STEP 2: Round-trip validation passed, proceed with conversion
        case Converter.convert_content(file_content) do
          {:ok, json} ->
            %{
              status: "completed",
              json_result: json,
              processing_time_ms: System.monotonic_time(:millisecond) - start_time,
              roundtrip_valid: true,
              roundtrip_diff: nil,
              roundtrip_error: nil
            }

          {:error, reason} ->
            %{
              status: "failed",
              error_message: inspect(reason),
              processing_time_ms: System.monotonic_time(:millisecond) - start_time,
              roundtrip_valid: false,
              roundtrip_diff: nil,
              roundtrip_error: "Conversion failed: #{inspect(reason)}"
            }
        end
      else
        # STEP 3: Round-trip validation FAILED - block conversion
        formatted_diff = RoundtripValidator.format_result(validation_result)

        %{
          status: "failed",
          error_message:
            "Round-trip validation failed - X12 cannot be perfectly reconstructed from JSON",
          processing_time_ms: System.monotonic_time(:millisecond) - start_time,
          roundtrip_valid: false,
          roundtrip_diff: formatted_diff,
          roundtrip_error:
            validation_result.error_message || "X12 reconstruction differs from original"
        }
      end

    {:ok, result}
  end

  @doc """
  Processes all jobs in a batch synchronously.
  Used for simple implementation without background jobs.
  """
  def process_batch_sync(batch_id, uploaded_files) do
    batch = get_batch!(batch_id)
    update_batch(batch, %{status: "processing"})

    # Process each file concurrently with controlled concurrency
    max_concurrency = Application.get_env(:x12_bridge, :batch_max_concurrency, 8)

    uploaded_files
    |> Task.async_stream(
      fn {job_id, file_content} ->
        job = get_job!(job_id)
        update_job(job, %{status: "processing", progress: 50})

        # Process the file
        {:ok, result} = process_file_sync(file_content, job.original_filename)

        # Update job with results including original X12 content
        update_job(job, result |> Map.put(:progress, 100) |> Map.put(:x12_content, file_content))

        # Broadcast progress update
        Phoenix.PubSub.broadcast(
          X12Bridge.PubSub,
          "batch:#{batch_id}",
          {:job_completed, job.id, result.status}
        )
      end,
      max_concurrency: max_concurrency,
      timeout: :infinity
    )
    |> Stream.run()

    # Update batch status
    completed_jobs = count_jobs_by_status(batch_id, "completed")
    failed_jobs = count_jobs_by_status(batch_id, "failed")

    update_batch(batch, %{
      status: "completed",
      completed_files: completed_jobs,
      failed_files: failed_jobs
    })

    # Broadcast batch completion
    Phoenix.PubSub.broadcast(
      X12Bridge.PubSub,
      "batch:#{batch_id}",
      {:batch_completed, batch_id}
    )

    {:ok, batch}
  end

  @doc """
  Verifies all jobs in a batch (Stage 1: Verification).

  This runs lightweight X12 structure validation on all jobs,
  without performing full translation. Verification is FREE.

  Updates job status to either 'verified' or 'failed_verification'.
  """
  def verify_batch_sync(batch_id, uploaded_files) do
    batch = get_batch!(batch_id)
    update_batch(batch, %{status: "verifying"})

    # Verify each file
    Enum.each(uploaded_files, fn {job_id, file_content} ->
      job = get_job!(job_id)
      update_job(job, %{status: "verifying"})

      # Run verification
      verification_result = Verifier.verify(file_content)

      # Update job based on verification result
      if verification_result.valid? do
        update_job(job, %{
          status: "verified",
          verification_result: verification_result,
          verification_error: nil,
          verified_at: DateTime.utc_now(),
          claim_count: verification_result.claim_count
        })

        # Broadcast success
        Phoenix.PubSub.broadcast(
          X12Bridge.PubSub,
          "batch:#{batch_id}",
          {:job_verified, job_id}
        )
      else
        # Format error message
        error_message = Enum.join(verification_result.errors, "; ")

        update_job(job, %{
          status: "failed_verification",
          verification_result: verification_result,
          verification_error: error_message,
          verified_at: DateTime.utc_now(),
          claim_count: 0
        })

        # Broadcast failure
        Phoenix.PubSub.broadcast(
          X12Bridge.PubSub,
          "batch:#{batch_id}",
          {:job_verification_failed, job_id, error_message}
        )
      end
    end)

    # Update batch with verification results
    verified_count = count_jobs_by_status(batch_id, "verified")
    failed_verification_count = count_jobs_by_status(batch_id, "failed_verification")

    # Calculate total claims from verified jobs
    total_claims =
      Job
      |> where([j], j.batch_id == ^batch_id and j.status == "verified")
      |> select([j], sum(j.claim_count))
      |> Repo.one() || 0

    update_batch(batch, %{
      status: "verified",
      verified_files: verified_count,
      failed_verification_files: failed_verification_count,
      total_claims: total_claims
    })

    # Broadcast batch verification complete
    Phoenix.PubSub.broadcast(
      X12Bridge.PubSub,
      "batch:#{batch_id}",
      {:batch_verified, batch_id, verified_count, failed_verification_count, total_claims}
    )

    {:ok, get_batch!(batch_id)}
  end

  @doc """
  Translates all VERIFIED jobs in a batch (Stage 2: Translation).

  This runs full X12 → JSON conversion + round-trip validation.
  Only jobs with status 'verified' are processed.
  Translation is BILLED per claim.

  Updates job status to either 'translated' or 'failed_translation'.
  """
  def translate_batch_sync(batch_id, uploaded_files) do
    batch = get_batch!(batch_id)
    update_batch(batch, %{status: "translating"})

    # Get only verified jobs
    verified_jobs =
      Job
      |> where([j], j.batch_id == ^batch_id and j.status == "verified")
      |> Repo.all()

    # Translate each verified file
    Enum.each(verified_jobs, fn job ->
      # Find the file content for this job
      file_content = Map.get(uploaded_files, job.id)

      if file_content do
        update_job(job, %{status: "translating"})

        start_time = System.monotonic_time(:millisecond)

        # STEP 1: Perform round-trip validation FIRST
        validation_result = RoundtripValidator.validate(file_content)

        if validation_result.valid? do
          # STEP 2: Round-trip validation passed, proceed with conversion
          case Converter.convert_content(file_content) do
            {:ok, json} ->
              processing_time = System.monotonic_time(:millisecond) - start_time

              update_job(job, %{
                status: "translated",
                json_result: json,
                processing_time_ms: processing_time,
                roundtrip_valid: true,
                roundtrip_diff: nil,
                roundtrip_error: nil,
                translated_at: DateTime.utc_now(),
                # Charge for successful translation
                claims_charged: job.claim_count
              })

              # Broadcast success
              Phoenix.PubSub.broadcast(
                X12Bridge.PubSub,
                "batch:#{batch_id}",
                {:job_translated, job.id}
              )

            {:error, reason} ->
              processing_time = System.monotonic_time(:millisecond) - start_time

              update_job(job, %{
                status: "failed_translation",
                error_message: inspect(reason),
                processing_time_ms: processing_time,
                roundtrip_valid: false,
                roundtrip_error: "Conversion failed: #{inspect(reason)}",
                translated_at: DateTime.utc_now(),
                # No charge for failed translation
                claims_charged: 0
              })

              # Broadcast failure
              Phoenix.PubSub.broadcast(
                X12Bridge.PubSub,
                "batch:#{batch_id}",
                {:job_translation_failed, job.id, inspect(reason)}
              )
          end
        else
          # STEP 3: Round-trip validation FAILED - block conversion
          processing_time = System.monotonic_time(:millisecond) - start_time
          formatted_diff = RoundtripValidator.format_result(validation_result)

          update_job(job, %{
            status: "failed_translation",
            error_message: "Round-trip validation failed",
            processing_time_ms: processing_time,
            roundtrip_valid: false,
            roundtrip_diff: formatted_diff,
            roundtrip_error:
              validation_result.error_message || "X12 reconstruction differs from original",
            translated_at: DateTime.utc_now(),
            # No charge for failed translation
            claims_charged: 0
          })

          # Broadcast failure
          Phoenix.PubSub.broadcast(
            X12Bridge.PubSub,
            "batch:#{batch_id}",
            {:job_translation_failed, job.id, "Round-trip validation failed"}
          )
        end
      end
    end)

    # Update batch with translation results
    translated_count = count_jobs_by_status(batch_id, "translated")
    failed_translation_count = count_jobs_by_status(batch_id, "failed_translation")

    # Calculate total claims charged (only for successful translations)
    total_claims_charged =
      Job
      |> where([j], j.batch_id == ^batch_id and j.status == "translated")
      |> select([j], sum(j.claims_charged))
      |> Repo.one() || 0

    update_batch(batch, %{
      status: "translated",
      translated_files: translated_count,
      failed_translation_files: failed_translation_count,
      total_claims_charged: total_claims_charged,
      # Also update legacy fields for backward compatibility
      completed_files: translated_count,
      failed_files: failed_translation_count
    })

    # Broadcast batch translation complete
    Phoenix.PubSub.broadcast(
      X12Bridge.PubSub,
      "batch:#{batch_id}",
      {:batch_translated, batch_id, translated_count, failed_translation_count,
       total_claims_charged}
    )

    {:ok, get_batch!(batch_id)}
  end

  defp count_jobs_by_status(batch_id, status) do
    Job
    |> where([j], j.batch_id == ^batch_id and j.status == ^status)
    |> Repo.aggregate(:count)
  end
end
