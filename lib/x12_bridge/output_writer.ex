# Copyright (c) 2026 Don Fox
# Licensed under the MIT License. See LICENSE file in the project root.

defmodule X12Bridge.OutputWriter do
  @moduledoc """
  Writes processed JSON output files back to the source directory.

  For batch processing workflows, this module handles writing the converted
  JSON files to an `output/` subdirectory of where the X12 files were read from.

  ## Example

      # Write a single JSON file
      OutputWriter.write_json("/path/to/batch", "claim.x12", json_content)
      # Creates: /path/to/batch/output/claim.json

      # Write multiple JSON files from a batch
      OutputWriter.write_batch_output("/path/to/batch", batch_id)
      # Creates: /path/to/batch/output/*.json for all translated jobs

  """

  require Logger

  alias X12Bridge.Conversions

  @output_subdir "output"

  @doc """
  Writes a single JSON file to the output subdirectory.

  ## Parameters
    * `source_dir` - The source directory where X12 files were read from
    * `original_filename` - The original X12 filename (e.g., "claim.x12")
    * `json_content` - The JSON string to write

  ## Returns
    * `{:ok, output_path}` - The path where the file was written
    * `{:error, reason}` - If writing failed
  """
  def write_json(source_dir, original_filename, json_content) when is_binary(source_dir) do
    output_dir = Path.join(source_dir, @output_subdir)
    json_filename = to_json_filename(original_filename)
    output_path = Path.join(output_dir, json_filename)

    with :ok <- ensure_output_dir(output_dir),
         :ok <- File.write(output_path, json_content) do
      Logger.info("Wrote JSON output: #{output_path}")
      {:ok, output_path}
    else
      {:error, reason} ->
        Logger.error("Failed to write JSON to #{output_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def write_json(nil, _original_filename, _json_content) do
    Logger.debug("No source_dir provided, skipping JSON file output")
    {:ok, :skipped}
  end

  @doc """
  Writes all translated jobs from a batch to the output subdirectory.

  ## Parameters
    * `source_dir` - The source directory where X12 files were read from
    * `batch_id` - The batch ID to write output for

  ## Returns
    * `{:ok, %{written: count, failed: count, paths: [paths]}}` - Summary of results
  """
  def write_batch_output(source_dir, batch_id) when is_binary(source_dir) do
    batch = Conversions.get_batch!(batch_id)

    # Get all translated jobs with JSON results
    translated_jobs =
      batch.jobs
      |> Enum.filter(fn job ->
        job.status in ["translated", "completed"] && job.json_result
      end)

    if Enum.empty?(translated_jobs) do
      Logger.info("No translated jobs to write for batch #{batch_id}")
      {:ok, %{written: 0, failed: 0, paths: []}}
    else
      results =
        Enum.map(translated_jobs, fn job ->
          case write_json(source_dir, job.original_filename, job.json_result) do
            {:ok, path} -> {:ok, path}
            {:error, reason} -> {:error, {job.original_filename, reason}}
          end
        end)

      written = Enum.filter(results, &match?({:ok, _}, &1))
      failed = Enum.filter(results, &match?({:error, _}, &1))

      paths = Enum.map(written, fn {:ok, path} -> path end)

      Logger.info(
        "Batch #{batch_id} output: #{length(written)} written, #{length(failed)} failed"
      )

      {:ok, %{written: length(written), failed: length(failed), paths: paths}}
    end
  end

  def write_batch_output(nil, batch_id) do
    Logger.debug("No source_dir provided for batch #{batch_id}, skipping file output")
    {:ok, %{written: 0, failed: 0, paths: [], skipped: true}}
  end

  @doc """
  Writes batch output as a ZIP file to the output subdirectory.

  ## Parameters
    * `source_dir` - The source directory
    * `batch_id` - The batch ID
    * `zip_filename` - Optional custom ZIP filename (default: "batch_results.zip")

  ## Returns
    * `{:ok, zip_path}` - Path to the created ZIP file
    * `{:error, reason}` - If creation failed
  """
  def write_batch_zip(source_dir, batch_id, zip_filename \\ "batch_results.zip")

  def write_batch_zip(source_dir, batch_id, zip_filename)
      when is_binary(source_dir) do
    batch = Conversions.get_batch!(batch_id)
    output_dir = Path.join(source_dir, @output_subdir)

    # Get all translated jobs with JSON results
    translated_jobs =
      batch.jobs
      |> Enum.filter(fn job ->
        job.status in ["translated", "completed"] && job.json_result
      end)

    if Enum.empty?(translated_jobs) do
      {:error, :no_translated_files}
    else
      # Create list of files for ZIP archive
      files =
        Enum.map(translated_jobs, fn job ->
          json_filename = to_json_filename(job.original_filename)
          {String.to_charlist(json_filename), job.json_result}
        end)

      with :ok <- ensure_output_dir(output_dir),
           {:ok, {_name, zip_binary}} <- :zip.create(zip_filename, files, [:memory]) do
        zip_path = Path.join(output_dir, zip_filename)

        case File.write(zip_path, zip_binary) do
          :ok ->
            Logger.info("Wrote batch ZIP: #{zip_path}")
            {:ok, zip_path}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  def write_batch_zip(nil, _batch_id, _zip_filename) do
    {:ok, :skipped}
  end

  @doc """
  Returns the output directory path for a given source directory.
  """
  def output_dir(source_dir) when is_binary(source_dir) do
    Path.join(source_dir, @output_subdir)
  end

  def output_dir(nil), do: nil

  # Private functions

  defp ensure_output_dir(output_dir) do
    case File.mkdir_p(output_dir) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to create output directory #{output_dir}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp to_json_filename(original_filename) do
    # Replace .x12, .edi, .txt extension with .json
    original_filename
    |> String.replace(~r/\.(x12|edi|txt)$/i, ".json")
  end
end
