defmodule X12Bridge.TestSupport.BatchLoader do
  @moduledoc """
  Helper module for loading mock batch data in tests.

  ## Examples

      # Load a complete batch with all files
      {:ok, batch} = BatchLoader.load_batch("automated_test_data")

      # Access batch metadata
      batch.batch_id        # "automated_test_data_001"
      batch.total_files     # 5

      # Iterate over files
      Enum.each(batch.files, fn file ->
        IO.puts("Processing file")
        IO.inspect(file.content)  # X12 file content
      end)

      # Get specific files
      content = BatchLoader.get_file_content("automated_test_data", "001_837p_valid.x12")
  """

  @batches_dir "test/fixtures/x12"

  @spec load_batch(
          binary()
          | maybe_improper_list(
              binary() | maybe_improper_list(any(), binary() | []) | char(),
              binary() | []
            )
        ) ::
          {:error, atom() | <<_::64, _::_*8>> | Jason.DecodeError.t()}
          | {:ok, %{:files => list(), optional(any()) => any()}}
  @doc """
  Loads a complete batch including manifest and file contents.

  Returns `{:ok, batch}` where batch is a map with:
  - `:batch_id` - Unique batch identifier
  - `:description` - Batch description
  - `:total_files` - Number of files
  - `:files` - List of file maps with content included

  ## Examples

      {:ok, batch} = load_batch("automated_test_data")
      Enum.count(batch.files)  # 5
  """
  def load_batch(batch_name) do
    batch_dir = Path.join(@batches_dir, batch_name)
    manifest_path = Path.join(batch_dir, "manifest.json")

    with true <- File.exists?(batch_dir),
         {:ok, manifest_json} <- File.read(manifest_path),
         {:ok, manifest} <- Jason.decode(manifest_json, keys: :atoms) do
      # Load file contents
      files_with_content =
        Enum.map(manifest.files, fn file_info ->
          file_path = Path.join(batch_dir, file_info.filename)
          {:ok, content} = File.read(file_path)

          Map.put(file_info, :content, content)
        end)

      {:ok, %{manifest | files: files_with_content}}
    else
      false -> {:error, "Batch directory not found: #{batch_dir}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all available batch names.

  ## Examples

      BatchLoader.list_batches()
      # ["automated_test_data", "batch_realistic", "batch_performance"]
  """
  def list_batches do
    case File.ls(@batches_dir) do
      {:ok, batches} -> batches
      {:error, _} -> []
    end
  end

  @doc """
  Gets the content of a specific file from a batch.

  ## Examples

      content = get_file_content("automated_test_data", "001_837p_valid.x12")
  """
  def get_file_content(batch_name, filename) do
    file_path = Path.join([@batches_dir, batch_name, filename])

    case File.read(file_path) do
      {:ok, content} -> content
      {:error, reason} -> raise "Failed to read #{filename}: #{inspect(reason)}"
    end
  end

  @doc """
  Loads just the manifest without file contents (faster).

  ## Examples

      {:ok, manifest} = load_manifest("automated_test_data")
      manifest.total_files  # 5
  """
  def load_manifest(batch_name) do
    manifest_path = Path.join([@batches_dir, batch_name, "manifest.json"])

    with {:ok, json} <- File.read(manifest_path),
         {:ok, manifest} <- Jason.decode(json, keys: :atoms) do
      {:ok, manifest}
    end
  end

  @doc """
  Gets statistics about a batch.

  ## Examples

      stats = batch_stats("automated_test_data")
      # %{
      #   total_files: 5,
      #   by_type: %{"837P" => 2, "837I" => 1, "837D" => 1, "ERROR" => 1},
      #   expected_success: 4,
      #   expected_errors: 1
      # }
  """
  def batch_stats(batch_name) do
    case load_manifest(batch_name) do
      {:ok, manifest} ->
        %{
          total_files: manifest.total_files,
          by_type: count_by_type(manifest.files),
          expected_success: count_by_status(manifest.files, "success"),
          expected_errors: count_by_status(manifest.files, "error")
        }

      {:error, _} ->
        %{}
    end
  end

  defp count_by_type(files) do
    Enum.reduce(files, %{}, fn file, acc ->
      Map.update(acc, file.type, 1, &(&1 + 1))
    end)
  end

  defp count_by_status(files, status) do
    Enum.count(files, fn file ->
      file[:expected_status] == status
    end)
  end
end
