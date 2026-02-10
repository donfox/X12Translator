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
  alias X12Bridge.OutputWriter

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
      :input_directory,
      :output_directory,
      :output_summary,
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

  @doc """
  Process X12 files from an input directory and write JSON outputs to a
  separate output directory.

  This is intended for manual batch runs against a hot folder on disk.

  ## Options
    * `:input_dir` - Directory containing X12 files (defaults to config)
    * `:output_dir` - Directory for JSON output (defaults to config)
    * `:batch_name` - Optional batch name override
    * `:allowed_extensions` - List of file extensions (defaults to config)
  """
  def process_input_directory(opts \\ []) do
    config = get_config(opts)
    hot_config = get_hot_folder_config(opts)
    opts_map = opts |> Map.new()
    file_metadata = Map.get(opts_map, :file_metadata, %{})
    submitted_by = Map.get(opts_map, :submitted_by)

    input_dir = hot_config.input_dir
    output_dir = hot_config.output_dir
    allowed_extensions = hot_config.allowed_extensions
    batch_name = hot_config.batch_name || build_batch_name("hot_folder")

    Logger.info("Scanning input directory #{input_dir} for X12 files")

    with {:ok, files} <- scan_directory_for_extensions(input_dir, allowed_extensions),
         {:ok, %BatchResult{} = result} <-
           process_files_to_database(files, batch_name, config, file_metadata, submitted_by),
         {:ok, output_summary} <-
           OutputWriter.write_batch_output_to_dir(output_dir, result.batch_id) do
      update_delivery_tracking(output_summary)

      Logger.info("Batch #{result.batch_id} output written to #{output_dir}")

      {:ok,
       %BatchResult{
         result
         | input_directory: input_dir,
           output_directory: output_dir,
           output_summary: output_summary
       }}
    else
      {:error, :no_files} ->
        {:error, "No input files found in #{input_dir}"}

      {:error, reason} = error ->
        Logger.error("Input directory processing failed: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp get_config(opts) do
    app_config = normalize_config(Application.get_env(:x12_bridge, :batch_processor, %{}))

    @default_config
    |> Map.merge(app_config)
    |> Map.merge(normalize_config(opts))
  end

  defp get_hot_folder_config(opts) do
    app_config = normalize_config(Application.get_env(:x12_bridge, :batch_hot_folder, %{}))

    %{
      input_dir: "priv/uploads/input",
      output_dir: "priv/uploads/output",
      allowed_extensions: [".x12", ".edi", ".txt"],
      batch_name: nil
    }
    |> Map.merge(app_config)
    |> Map.merge(
      opts
      |> normalize_config()
      |> Map.take([:input_dir, :output_dir, :allowed_extensions, :batch_name])
    )
  end

  defp normalize_config(config) when is_map(config), do: config
  defp normalize_config(config) when is_list(config), do: Map.new(config)
  defp normalize_config(_config), do: %{}

  defp maybe_put_submitted_by(attrs, nil), do: attrs
  defp maybe_put_submitted_by(attrs, ""), do: attrs
  defp maybe_put_submitted_by(attrs, name), do: Map.put(attrs, :submitted_by, name)

  # Process files and store in database (no file output)
  defp process_files_to_database(file_paths, batch_name, config, file_metadata \\ %{}, submitted_by \\ nil) do
    start_time = System.monotonic_time(:millisecond)
    total_files = length(file_paths)

    # Create batch in database
    batch_attrs =
      %{
        name: batch_name,
        total_files: total_files,
        completed_files: 0,
        failed_files: 0,
        status: "processing"
      }
      |> maybe_put_submitted_by(submitted_by)

    {:ok, batch} = Conversions.create_batch(batch_attrs)

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
            job_attrs =
              %{
                batch_id: batch.id,
                original_filename: filename,
                file_size: file_size,
                status: "pending",
                input_path: file_path,
                delivery_status: "received"
              }
              |> Map.merge(Map.get(file_metadata, file_path, %{}))

            {:ok, job} = Conversions.create_job(job_attrs)

            {job.id, content}

          {:error, reason} ->
            Logger.error("Failed to read #{filename}: #{inspect(reason)}")

            # Create failed job
            job_attrs =
              %{
                batch_id: batch.id,
                original_filename: filename,
                file_size: 0,
                status: "failed",
                error_message: "Failed to read file: #{inspect(reason)}",
                input_path: file_path,
                delivery_status: "failed"
              }
              |> Map.merge(Map.get(file_metadata, file_path, %{}))

            {:ok, job} = Conversions.create_job(job_attrs)

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

  defp scan_directory_for_extensions(directory, allowed_extensions) do
    unless File.exists?(directory) do
      File.mkdir_p!(directory)
    end

    extensions =
      allowed_extensions
      |> Enum.map(&String.downcase/1)
      |> Enum.map(fn ext -> if String.starts_with?(ext, "."), do: ext, else: ".#{ext}" end)

    files =
      case File.ls(directory) do
        {:ok, entries} ->
          entries
          |> Enum.map(&Path.join(directory, &1))
          |> Enum.filter(&File.regular?/1)
          |> Enum.filter(fn path ->
            String.downcase(Path.extname(path)) in extensions
          end)

        {:error, reason} ->
          Logger.error("Failed to list directory #{directory}: #{inspect(reason)}")
          []
      end

    if Enum.empty?(files) do
      {:error, :no_files}
    else
      {:ok, files}
    end
  end

  defp build_batch_name(prefix) do
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601()
      |> String.replace(["-", ":"], "")
      |> String.replace("T", "_")
      |> String.replace("Z", "")

    "#{prefix}_#{timestamp}"
  end

  defp update_delivery_tracking(%{by_job: by_job}) when is_map(by_job) do
    Enum.each(by_job, fn {job_id, paths} ->
      output_path = List.first(paths)

      job = Conversions.get_job!(job_id)

      Conversions.update_job(job, %{
        output_path: output_path,
        delivery_status: "ready"
      })
    end)
  end

  defp update_delivery_tracking(_), do: :ok
end
