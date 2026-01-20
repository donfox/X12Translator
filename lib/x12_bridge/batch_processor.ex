# Copyright (c) 2026 Don Fox
# Licensed under the MIT License. See LICENSE file in the project root.

defmodule X12Bridge.BatchProcessor do
  @moduledoc """
  Batch processor for X12 files used in testing.

  Processes X12 test files and stores results in the database using the Conversions context.

  All processing is done IN MEMORY with results stored in the database - no files
  are written to disk except during temporary processing.

  ## Configuration

      config :x12_bridge, :batch_processor,
        max_concurrency: 10,
        timeout_per_file_ms: 30_000

  ## Example Usage

      # Process specific test batch
      {:ok, batch} = BatchProcessor.process_test_batch("automated_test_data")
  """

  require Logger

  alias X12Bridge.Conversions

  @default_config %{
    max_concurrency: 10,
    timeout_per_file_ms: 30_000
  }

  defmodule BatchResult do
    @moduledoc "Result of batch processing"
    defstruct [
      :batch_id,
      :batch_record,
      :total_files,
      :successful_files,
      :failed_files,
      :processing_time_ms,
      jobs: []
    ]
  end

  @doc """
  Process files from a test batch directory (for testing with mock data).

  ## Example

      BatchProcessor.process_test_batch("automated_test_data")
  """
  def process_test_batch(batch_name, opts \\ []) do
    config = get_config(opts)
    test_batch_dir = Path.join("test/fixtures", batch_name)

    with true <- File.exists?(test_batch_dir),
         {:ok, files} <- scan_directory(test_batch_dir, "*.x12"),
         {:ok, result} <- process_files_to_database(files, batch_name, config) do
      Logger.info(
        "Test batch #{batch_name} completed: #{result.successful_files}/#{result.total_files} successful"
      )

      {:ok, result}
    else
      false ->
        {:error, "Test batch directory not found: #{test_batch_dir}"}

      {:error, reason} = error ->
        Logger.error("Test batch processing failed: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp get_config(opts) do
    app_config = Application.get_env(:x12_bridge, :batch_processor, %{})

    @default_config
    |> Map.merge(app_config)
    |> Map.merge(Map.new(opts))
  end

  # Process files and store in database (no file output)
  defp process_files_to_database(file_paths, batch_name, config) do
    start_time = System.monotonic_time(:millisecond)
    total_files = length(file_paths)

    # Create batch in database
    {:ok, batch} =
      Conversions.create_batch(%{
        name: batch_name,
        total_files: total_files,
        completed_files: 0,
        failed_files: 0,
        status: "processing"
      })

    Logger.info(
      "Processing batch #{batch.id} with #{total_files} files (max concurrency: #{config.max_concurrency})"
    )

    # Read all files into memory
    uploaded_files =
      file_paths
      |> Enum.map(fn file_path ->
        filename = Path.basename(file_path)

        case File.read(file_path) do
          {:ok, content} ->
            file_size = byte_size(content)

            # Create job in database
            {:ok, job} =
              Conversions.create_job(%{
                batch_id: batch.id,
                original_filename: filename,
                file_size: file_size,
                status: "pending"
              })

            {job.id, content}

          {:error, reason} ->
            Logger.error("Failed to read #{filename}: #{inspect(reason)}")

            # Create failed job
            {:ok, job} =
              Conversions.create_job(%{
                batch_id: batch.id,
                original_filename: filename,
                file_size: 0,
                status: "failed",
                error_message: "Failed to read file: #{inspect(reason)}"
              })

            {job.id, nil}
        end
      end)
      |> Enum.filter(fn {_job_id, content} -> content != nil end)
      |> Map.new()

    # Process batch synchronously (includes round-trip validation)
    Conversions.process_batch_sync(batch.id, uploaded_files)

    # Reload batch to get updated stats
    batch = Conversions.get_batch!(batch.id)

    processing_time = System.monotonic_time(:millisecond) - start_time

    result = %BatchResult{
      batch_id: batch.id,
      batch_record: batch,
      total_files: batch.total_files,
      successful_files: batch.completed_files,
      failed_files: batch.failed_files,
      processing_time_ms: processing_time,
      jobs: batch.jobs
    }

    {:ok, result}
  end

  defp scan_directory(directory, pattern) do
    unless File.exists?(directory) do
      File.mkdir_p!(directory)
    end

    pattern_path = Path.join(directory, pattern)

    files =
      pattern_path
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)

    if Enum.empty?(files) do
      {:error, :no_files}
    else
      {:ok, files}
    end
  end
end
