defmodule X12Bridge.Conversions do
  @moduledoc """
  The Conversions context handles batch processing and job tracking.
  """

  import Ecto.Query
  alias X12Bridge.Repo
  alias X12Bridge.Conversions.{Batch, Job}
  alias X12Bridge.X12.Converter

  ## Batch functions

  @doc """
  Creates a new batch.
  """
  def create_batch(attrs \\ %{}) do
    %Batch{}
    |> Batch.changeset(attrs)
    |> Repo.insert()
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
  """
  def process_file_sync(file_content, _filename) do
    start_time = System.monotonic_time(:millisecond)

    result = case Converter.convert_content(file_content) do
      {:ok, json} ->
        %{
          status: "completed",
          json_result: json,
          processing_time_ms: System.monotonic_time(:millisecond) - start_time
        }

      {:error, reason} ->
        %{
          status: "failed",
          error_message: inspect(reason),
          processing_time_ms: System.monotonic_time(:millisecond) - start_time
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

      # Update job with results
      update_job(job, Map.put(result, :progress, 100))

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
