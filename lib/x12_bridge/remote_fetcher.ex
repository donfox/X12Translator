defmodule X12Bridge.RemoteFetcher do
  @moduledoc """
  Fetches and extracts remote X12 batch archives from HTTP/HTTPS URLs.

  Supports:
  - ZIP archives containing X12 files (.x12, .edi, .txt)
  - Optional manifest.json for batch metadata
  - Automatic cleanup of temporary files
  - Configurable timeouts and file size limits

  ## Example

      iex> X12Bridge.RemoteFetcher.fetch_and_extract("https://example.com/batch.zip")
      {:ok, %{files: ["/tmp/x12bridge_remote_123/file1.x12"], manifest: nil, temp_dir: "/tmp/x12bridge_remote_123"}}

  """

  require Logger

  @doc """
  Fetches a remote ZIP archive and extracts X12 files.

  ## Options

    * `:timeout` - Download timeout in milliseconds (default: from config, 60s)
    * `:max_size` - Maximum file size in bytes (default: from config, 100MB)

  ## Returns

    * `{:ok, result}` where result contains:
      * `:files` - List of absolute paths to extracted X12 files
      * `:manifest` - Parsed manifest.json map if present, nil otherwise
      * `:temp_dir` - Temporary directory path (caller must clean up via cleanup_temp_files/1)

    * `{:error, reason}` where reason is:
      * `:invalid_url` - URL format invalid or non-HTTP(S)
      * `:download_failed` - Network error or timeout
      * `{:http_error, status_code}` - Non-200 HTTP response
      * `:invalid_zip` - Not a valid ZIP file
      * `:no_x12_files` - ZIP contains no X12 files
      * `:file_too_large` - File exceeds max_size limit

  """
  def fetch_and_extract(url, opts \\ []) do
    with {:ok, _uri} <- validate_url(url),
         {:ok, config} <- get_config(opts),
         {:ok, zip_data} <- download_file(url, config.timeout, config.max_size),
         {:ok, temp_dir} <- create_temp_directory(),
         {:ok, extracted_files} <- extract_zip(zip_data, temp_dir),
         {:ok, x12_files} <- validate_zip_contents(extracted_files, config.allowed_extensions),
         {:ok, manifest} <- load_manifest(temp_dir) do
      {:ok,
       %{
         files: x12_files,
         manifest: manifest,
         temp_dir: temp_dir
       }}
    else
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Validates that a URL is well-formed and uses HTTP or HTTPS scheme.

  ## Examples

      iex> X12Bridge.RemoteFetcher.validate_url("https://example.com/file.zip")
      {:ok, %URI{scheme: "https", host: "example.com", ...}}

      iex> X12Bridge.RemoteFetcher.validate_url("ftp://example.com/file.zip")
      {:error, :invalid_url}

  """
  def validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and not is_nil(host) and host != "" ->
        {:ok, URI.parse(url)}

      _ ->
        {:error, :invalid_url}
    end
  end

  def validate_url(_), do: {:error, :invalid_url}

  @doc """
  Removes temporary directory and all its contents.

  ## Examples

      iex> X12Bridge.RemoteFetcher.cleanup_temp_files("/tmp/x12bridge_remote_123")
      :ok

  """
  def cleanup_temp_files(temp_dir) when is_binary(temp_dir) do
    if File.exists?(temp_dir) do
      File.rm_rf!(temp_dir)
      Logger.debug("Cleaned up temporary directory: #{temp_dir}")
    end

    :ok
  end

  def cleanup_temp_files(_), do: :ok

  # Private functions

  defp get_config(opts) do
    app_config = Application.get_env(:x12_bridge, :remote_fetcher, [])

    config = %{
      timeout: Keyword.get(opts, :timeout, Keyword.get(app_config, :download_timeout_ms, 60_000)),
      max_size:
        Keyword.get(opts, :max_size, Keyword.get(app_config, :max_file_size_bytes, 100_000_000)),
      allowed_extensions:
        Keyword.get(
          opts,
          :allowed_extensions,
          Keyword.get(app_config, :allowed_extensions, [".x12", ".edi", ".txt"])
        )
    }

    {:ok, config}
  end

  defp download_file(url, timeout, max_size) do
    Logger.info("Downloading remote batch file from: #{url}")

    # Start required applications
    :inets.start()
    :ssl.start()

    request = {
      String.to_charlist(url),
      []
    }

    http_options = [
      timeout: timeout,
      ssl: [verify: :verify_none]
    ]

    body_format_options = [body_format: :binary]

    case :httpc.request(:get, request, http_options, body_format_options) do
      {:ok, {{_version, 200, _status}, headers, body}} ->
        # Check file size
        content_length = get_content_length(headers)

        cond do
          content_length && content_length > max_size ->
            {:error, :file_too_large}

          byte_size(body) > max_size ->
            {:error, :file_too_large}

          true ->
            Logger.info("Downloaded #{byte_size(body)} bytes")
            {:ok, body}
        end

      {:ok, {{_version, status_code, _status}, _headers, _body}} ->
        Logger.error("HTTP error: #{status_code}")
        {:error, {:http_error, status_code}}

      {:error, reason} ->
        Logger.error("Download failed: #{inspect(reason)}")
        {:error, :download_failed}
    end
  end

  defp get_content_length(headers) do
    case Enum.find(headers, fn {key, _value} ->
           String.downcase(to_string(key)) == "content-length"
         end) do
      {_key, value} when is_list(value) ->
        value |> to_string() |> String.to_integer()

      {_key, value} when is_binary(value) ->
        String.to_integer(value)

      _ ->
        nil
    end
  end

  defp create_temp_directory do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    temp_dir = Path.join(System.tmp_dir!(), "x12bridge_remote_#{timestamp}_#{random}")

    case File.mkdir_p(temp_dir) do
      :ok ->
        Logger.debug("Created temporary directory: #{temp_dir}")
        {:ok, temp_dir}

      {:error, reason} ->
        Logger.error("Failed to create temp directory: #{inspect(reason)}")
        {:error, :temp_dir_failed}
    end
  end

  defp extract_zip(zip_data, extract_dir) when is_binary(zip_data) do
    # Write ZIP to temporary file (required by :zip.unzip)
    temp_zip = Path.join(extract_dir, "download.zip")

    with :ok <- File.write(temp_zip, zip_data),
         {:ok, files} <- unzip_file(temp_zip, extract_dir) do
      # Remove the temporary ZIP file
      File.rm(temp_zip)

      # Convert charlist paths to strings
      string_files =
        files
        |> Enum.map(&to_string/1)
        |> Enum.filter(&File.regular?/1)

      Logger.info("Extracted #{length(string_files)} files from ZIP")
      {:ok, string_files}
    else
      {:error, _reason} ->
        {:error, :invalid_zip}
    end
  end

  defp unzip_file(zip_path, extract_dir) do
    case :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(extract_dir)) do
      {:ok, files} ->
        {:ok, files}

      {:error, reason} ->
        Logger.error("ZIP extraction failed: #{inspect(reason)}")
        {:error, :invalid_zip}
    end
  end

  defp validate_zip_contents(files, allowed_extensions) do
    x12_files =
      Enum.filter(files, fn file ->
        ext = Path.extname(file) |> String.downcase()
        ext in allowed_extensions
      end)

    if Enum.empty?(x12_files) do
      Logger.error(
        "No X12 files found. Expected extensions: #{inspect(allowed_extensions)}, found: #{inspect(Enum.map(files, &Path.extname/1))}"
      )

      {:error, :no_x12_files}
    else
      Logger.info("Found #{length(x12_files)} X12 files")
      {:ok, x12_files}
    end
  end

  defp load_manifest(temp_dir) do
    manifest_path = Path.join(temp_dir, "manifest.json")

    case File.read(manifest_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, manifest} ->
            Logger.info("Loaded manifest.json")
            {:ok, manifest}

          {:error, _reason} ->
            Logger.warning("manifest.json found but could not be parsed")
            {:ok, nil}
        end

      {:error, _reason} ->
        # No manifest is fine
        {:ok, nil}
    end
  end
end
