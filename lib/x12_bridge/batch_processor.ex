defmodule X12Bridge.BatchProcessor do
  @moduledoc """
  Hot folder batch processor for X12 files.

  Implements the hot folder/watched directory pattern:
  1. Scans input directory for X12 files
  2. Processes files concurrently (leveraging Elixir's Task.async_stream)
  3. Routes successful JSON to output directory
  4. Routes failed files to failed directory with error reports

  ## Configuration

      config :x12_bridge, :batch_processor,
        input_dir: "priv/batch_processing/input",
        output_dir: "priv/batch_processing/output",
        failed_dir: "priv/batch_processing/failed",
        archive_dir: "priv/batch_processing/archive",
        max_concurrency: 10,
        timeout_per_file_ms: 30_000

  ## Example Usage

      # Process all files in input directory
      {:ok, result} = BatchProcessor.process_input_directory()

      # Process specific batch
      {:ok, result} = BatchProcessor.process_batch("batch_20250131_120000")
  """

  require Logger

  alias X12Bridge.X12.Converter

  @default_config %{
    input_dir: "priv/batch_processing/input",
    output_dir: "priv/batch_processing/output",
    failed_dir: "priv/batch_processing/failed",
    archive_dir: "priv/batch_processing/archive",
    max_concurrency: 10,
    timeout_per_file_ms: 30_000
  }

  defmodule BatchResult do
    @moduledoc "Result of batch processing"
    defstruct [
      :batch_id,
      :total_files,
      :successful_files,
      :failed_files,
      :processing_time_ms,
      :output_directory,
      :failed_directory,
      :manifest_path,
      files: []
    ]
  end

  defmodule FileResult do
    @moduledoc "Result of processing a single file"
    defstruct [
      :filename,
      :status,
      :processing_time_ms,
      :output_path,
      :error_message,
      :claims_count
    ]
  end

  @doc """
  Process all X12 files in the input directory.

  Creates a new batch with timestamp and processes all files concurrently.
  """
  def process_input_directory(opts \\ []) do
    config = get_config(opts)
    batch_id = generate_batch_id()

    with {:ok, files} <- scan_input_directory(config),
         :ok <- ensure_output_directories(batch_id, config),
         {:ok, result} <- process_files(batch_id, files, config) do
      Logger.info("Batch #{batch_id} completed: #{result.successful_files}/#{result.total_files} successful")
      {:ok, result}
    else
      {:error, :no_files} ->
        Logger.info("No files found in input directory")
        {:ok, %BatchResult{batch_id: batch_id, total_files: 0, successful_files: 0, failed_files: 0}}

      {:error, reason} = error ->
        Logger.error("Batch processing failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Process files from a test batch directory (for testing with mock data).

  ## Example

      BatchProcessor.process_test_batch("batch_quick")
  """
  def process_test_batch(batch_name, opts \\ []) do
    config = get_config(opts)
    batch_id = "test_#{batch_name}_#{:os.system_time(:millisecond)}"

    test_batch_dir = Path.join("priv/test_data/batches", batch_name)

    with true <- File.exists?(test_batch_dir),
         {:ok, files} <- scan_directory(test_batch_dir, "*.x12"),
         :ok <- ensure_output_directories(batch_id, config),
         {:ok, result} <- process_files(batch_id, files, config) do
      Logger.info("Test batch #{batch_name} completed: #{result.successful_files}/#{result.total_files} successful")
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
  Process a single file and return result.

  Used internally by the batch processor.
  """
  def process_single_file(file_path, batch_id, config) do
    start_time = System.monotonic_time(:millisecond)
    filename = Path.basename(file_path)

    Logger.debug("Processing file: #{filename}")

    case File.read(file_path) do
      {:ok, content} ->
        case Converter.convert_content(content) do
          {:ok, json} ->
            # Write JSON to output directory
            output_path = build_output_path(batch_id, filename, config)
            File.write!(output_path, json)

            # Count claims in JSON
            claims_count = count_claims(json)

            processing_time = System.monotonic_time(:millisecond) - start_time

            %FileResult{
              filename: filename,
              status: :success,
              processing_time_ms: processing_time,
              output_path: output_path,
              claims_count: claims_count
            }

          {:error, reason} ->
            # Move failed file to failed directory
            {failed_path, _error_report_path} = handle_failed_file(file_path, batch_id, reason, config)

            processing_time = System.monotonic_time(:millisecond) - start_time

            %FileResult{
              filename: filename,
              status: :failed,
              processing_time_ms: processing_time,
              output_path: failed_path,
              error_message: inspect(reason)
            }
        end

      {:error, reason} ->
        Logger.error("Failed to read file #{filename}: #{inspect(reason)}")

        processing_time = System.monotonic_time(:millisecond) - start_time

        %FileResult{
          filename: filename,
          status: :failed,
          processing_time_ms: processing_time,
          error_message: "Failed to read file: #{inspect(reason)}"
        }
    end
  end

  # Private functions

  defp get_config(opts) do
    app_config = Application.get_env(:x12_bridge, :batch_processor, %{})

    @default_config
    |> Map.merge(app_config)
    |> Map.merge(Map.new(opts))
  end

  defp generate_batch_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    "batch_#{timestamp}"
  end

  defp scan_input_directory(config) do
    scan_directory(config.input_dir, "*.x12")
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

  defp ensure_output_directories(batch_id, config) do
    output_batch_dir = Path.join(config.output_dir, batch_id)
    failed_batch_dir = Path.join(config.failed_dir, batch_id)

    File.mkdir_p!(output_batch_dir)
    File.mkdir_p!(failed_batch_dir)

    :ok
  end

  defp process_files(batch_id, files, config) do
    start_time = System.monotonic_time(:millisecond)
    total_files = length(files)

    Logger.info("Processing batch #{batch_id} with #{total_files} files (max concurrency: #{config.max_concurrency})")

    # Process files concurrently using Task.async_stream
    results =
      files
      |> Task.async_stream(
        fn file_path -> process_single_file(file_path, batch_id, config) end,
        max_concurrency: config.max_concurrency,
        timeout: config.timeout_per_file_ms,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} ->
          Logger.error("Task exited: #{inspect(reason)}")
          %FileResult{filename: "unknown", status: :failed, error_message: "Task timeout or crash"}
      end)

    processing_time = System.monotonic_time(:millisecond) - start_time

    successful_files = Enum.count(results, fn r -> r.status == :success end)
    failed_files = Enum.count(results, fn r -> r.status == :failed end)

    # Generate batch manifest
    manifest_path = generate_manifest(batch_id, results, processing_time, config)

    # Clean up input files after successful processing
    cleanup_input_files(files, config)

    result = %BatchResult{
      batch_id: batch_id,
      total_files: total_files,
      successful_files: successful_files,
      failed_files: failed_files,
      processing_time_ms: processing_time,
      output_directory: Path.join(config.output_dir, batch_id),
      failed_directory: Path.join(config.failed_dir, batch_id),
      manifest_path: manifest_path,
      files: results
    }

    {:ok, result}
  end

  defp build_output_path(batch_id, filename, config) do
    output_batch_dir = Path.join(config.output_dir, batch_id)
    json_filename = Path.rootname(filename) <> ".json"
    Path.join(output_batch_dir, json_filename)
  end

  defp handle_failed_file(file_path, batch_id, reason, config) do
    failed_batch_dir = Path.join(config.failed_dir, batch_id)
    filename = Path.basename(file_path)

    # Copy original X12 file to failed directory
    failed_file_path = Path.join(failed_batch_dir, filename)
    File.cp!(file_path, failed_file_path)

    # Create error report
    error_report = %{
      filename: filename,
      error: inspect(reason),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      original_path: file_path
    }

    error_report_path = Path.join(failed_batch_dir, "#{Path.rootname(filename)}_error.json")
    error_json = Jason.encode!(error_report, pretty: true)
    File.write!(error_report_path, error_json)

    {failed_file_path, error_report_path}
  end

  defp generate_manifest(batch_id, results, processing_time_ms, config) do
    output_batch_dir = Path.join(config.output_dir, batch_id)

    manifest = %{
      batch_id: batch_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      total_files: length(results),
      successful_files: Enum.count(results, fn r -> r.status == :success end),
      failed_files: Enum.count(results, fn r -> r.status == :failed end),
      total_processing_time_ms: processing_time_ms,
      files: Enum.map(results, &file_result_to_map/1)
    }

    manifest_path = Path.join(output_batch_dir, "manifest.json")
    manifest_json = Jason.encode!(manifest, pretty: true)
    File.write!(manifest_path, manifest_json)

    manifest_path
  end

  defp file_result_to_map(%FileResult{} = result) do
    %{
      filename: result.filename,
      status: to_string(result.status),
      processing_time_ms: result.processing_time_ms,
      output_path: result.output_path,
      error_message: result.error_message,
      claims_count: result.claims_count
    }
  end

  defp cleanup_input_files(files, _config) do
    # Move processed files to archive or delete them
    # For now, we'll leave them in place for debugging
    # In production, you'd move them to archive directory
    Enum.each(files, fn file_path ->
      Logger.debug("File processed: #{file_path}")
      # File.rm(file_path)  # Uncomment to delete after processing
    end)
  end

  defp count_claims(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, %{"claims" => claims}} when is_list(claims) -> length(claims)
      {:ok, %{"summary" => %{"total_claims" => count}}} -> count
      _ -> 0
    end
  end
end
