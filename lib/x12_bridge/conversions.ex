defmodule X12Bridge.Conversions do
  @moduledoc """
  The Conversions context handles batch processing and job tracking.
  """

  import Ecto.Query
  alias X12Bridge.Repo
  alias X12Bridge.Conversions.{Batch, Job}
  alias X12Bridge.X12.{Converter, RoundtripValidator}

  ## Batch functions

  @doc """
  Creates a new batch and triggers automatic cleanup of old batches.
  """
  def create_batch(attrs \\ %{}) do
    with {:ok, batch} <- %Batch{}
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
    max_batches = Keyword.get(opts, :keep) ||
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

    result = if validation_result.valid? do
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
        error_message: "Round-trip validation failed - X12 cannot be perfectly reconstructed from JSON",
        processing_time_ms: System.monotonic_time(:millisecond) - start_time,
        roundtrip_valid: false,
        roundtrip_diff: formatted_diff,
        roundtrip_error: validation_result.error_message || "X12 reconstruction differs from original"
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

    # Process each file
    Enum.each(uploaded_files, fn {job_id, file_content} ->
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
    end)

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

  defp count_jobs_by_status(batch_id, status) do
    Job
    |> where([j], j.batch_id == ^batch_id and j.status == ^status)
    |> Repo.aggregate(:count)
  end
end
