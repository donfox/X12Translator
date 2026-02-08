defmodule Mix.Tasks.ProcessSftpImport do
  @moduledoc """
  Pulls X12 files from an SFTP source, loads them into the local input directory,
  then processes them into JSON output.

  Usage:
    mix process_sftp_import --source sftp://host/path [--input /path/to/input]
      [--output /path/to/output] [--batch-name name]
      [--sftp-username user] [--sftp-password pass] [--sftp-port 22]
  """

  @shortdoc "Import X12 files from SFTP and process"

  use Mix.Task

  alias X12Bridge.{BatchProcessor, RemoteFetcher}

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        switches: [
          source: :string,
          input: :string,
          output: :string,
          batch_name: :string,
          sftp_username: :string,
          sftp_password: :string,
          sftp_port: :integer,
          keep_temp: :boolean
        ]
      )

    source = opts[:source] || default_source()

    if is_nil(source) do
      Mix.shell().error("Missing --source sftp://host/path (and no default configured)")
      System.halt(1)
    end

    {input_dir, output_dir} = resolve_hot_folder_dirs(opts)

    sftp_opts =
      []
      |> maybe_put(:sftp_username, opts[:sftp_username])
      |> maybe_put(:sftp_password, opts[:sftp_password])
      |> maybe_put(:sftp_port, opts[:sftp_port])

    case RemoteFetcher.fetch_and_extract(source, sftp_opts) do
      {:ok, %{files: files, temp_dir: temp_dir}} ->
        File.mkdir_p!(input_dir)

        {copied_files, metadata} =
          copy_files_to_input(files, source, input_dir)

        batch_opts =
          %{}
          |> maybe_put(:input_dir, input_dir)
          |> maybe_put(:output_dir, output_dir)
          |> maybe_put(:batch_name, opts[:batch_name])
          |> Map.put(:file_metadata, metadata)

        case BatchProcessor.process_input_directory(batch_opts) do
          {:ok, result} ->
            Mix.shell().info("Batch completed: #{result.batch_id}")
            Mix.shell().info("  Input:  #{result.input_directory}")
            Mix.shell().info("  Output: #{result.output_directory}")
            Mix.shell().info("  Total:  #{result.total_files}")
            Mix.shell().info("  OK:     #{result.successful_files}")
            Mix.shell().info("  Failed: #{result.failed_files}")

          {:error, reason} ->
            Mix.shell().error("Batch processing failed: #{inspect(reason)}")
        end

        cleanup_temp_dir(temp_dir, opts[:keep_temp])

        if Enum.empty?(copied_files) do
          Mix.shell().error("No files were copied into #{input_dir}")
        end

      {:error, reason} ->
        Mix.shell().error("SFTP import failed: #{inspect(reason)}")
    end
  end

  defp resolve_hot_folder_dirs(opts) do
    config = Application.get_env(:x12_bridge, :batch_hot_folder, [])

    input_dir = opts[:input] || Keyword.get(config, :input_dir, "priv/batch_processing/input")
    output_dir = opts[:output] || Keyword.get(config, :output_dir, "priv/batch_processing/output")

    {input_dir, output_dir}
  end

  defp default_source do
    Application.get_env(:x12_bridge, :sftp_import, [])
    |> Keyword.get(:default_source)
  end

  defp copy_files_to_input(files, source, input_dir) do
    uri = URI.parse(source)
    remote_host = uri.host
    remote_base = uri.path || "/"

    Enum.reduce(files, {[], %{}}, fn temp_path, {acc_files, acc_metadata} ->
      filename = Path.basename(temp_path)
      dest_path = unique_dest_path(input_dir, filename)

      case File.cp(temp_path, dest_path) do
        :ok ->
          remote_path = build_remote_path(remote_base, filename, length(files))

          metadata =
            acc_metadata
            |> Map.put(dest_path, %{
              remote_host: remote_host,
              remote_path: remote_path,
              remote_source_url: source
            })

          {[dest_path | acc_files], metadata}

        {:error, reason} ->
          Mix.shell().error("Failed to copy #{temp_path}: #{inspect(reason)}")
          {acc_files, acc_metadata}
      end
    end)
    |> then(fn {files_copied, metadata} -> {Enum.reverse(files_copied), metadata} end)
  end

  defp build_remote_path(base_path, filename, file_count) do
    cond do
      file_count <= 1 ->
        base_path

      String.ends_with?(base_path, "/") ->
        Path.join(base_path, filename)

      true ->
        Path.join(base_path, filename)
    end
  end

  defp unique_dest_path(input_dir, filename) do
    base = Path.rootname(filename)
    ext = Path.extname(filename)

    candidate = Path.join(input_dir, filename)

    if File.exists?(candidate) do
      find_unique_path(input_dir, base, ext, 1)
    else
      candidate
    end
  end

  defp find_unique_path(input_dir, base, ext, index) do
    candidate = Path.join(input_dir, "#{base}_#{index}#{ext}")

    if File.exists?(candidate) do
      find_unique_path(input_dir, base, ext, index + 1)
    else
      candidate
    end
  end

  defp cleanup_temp_dir(nil, _keep_temp), do: :ok

  defp cleanup_temp_dir(temp_dir, keep_temp) do
    if keep_temp do
      Mix.shell().info("Temp dir preserved: #{temp_dir}")
      :ok
    else
      RemoteFetcher.cleanup_temp_files(temp_dir)
    end
  end

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)
end
