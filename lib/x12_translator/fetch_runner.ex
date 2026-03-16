defmodule X12Translator.FetchRunner do
  @moduledoc """
  Executed by Quantum when a scheduled fetch fires.
  Fetches files from the configured source, processes them through
  the X12 pipeline, and sends results to medicaid_claims_checker via webhook.
  """
  require Logger

  alias X12Translator.{RemoteFetcher, BatchProcessor, Webhook}

  def run(source_config) do
    uri = source_config["uri"]
    name = source_config["name"]
    source_type = source_config["source_type"]

    Logger.info("Running scheduled fetch for '#{name}' (#{source_type}) from #{uri}")

    opts = build_fetch_opts(source_config)

    case RemoteFetcher.fetch_and_extract(uri, opts) do
      {:ok, %{files: files, temp_dir: temp_dir}} ->
        Logger.info("Fetched #{length(files)} files from '#{name}'")

        batch_name = "Scheduled: #{name} - #{Calendar.strftime(DateTime.utc_now(), "%b %d, %Y %I:%M %p")}"

        result =
          BatchProcessor.process_input_directory(
            files: files,
            batch_name: batch_name
          )

        case result do
          {:ok, batch_result} ->
            Webhook.send_batch(
              to_string(batch_result.batch_id),
              batch_result.jobs
            )

          {:error, reason} ->
            Logger.error("Batch processing failed for '#{name}': #{inspect(reason)}")
        end

        if temp_dir, do: RemoteFetcher.cleanup_temp_files(temp_dir)

      {:error, reason} ->
        Logger.error("Fetch failed for '#{name}': #{inspect(reason)}")
    end
  end

  defp build_fetch_opts(source_config) do
    creds = source_config["credentials"] || %{}
    uri = source_config["uri"] || ""

    password = creds["password"]
    username = creds["username"] || extract_username_from_uri(uri)

    cond do
      password && username -> [sftp_username: username, sftp_password: password]
      password -> [sftp_password: password]
      true -> []
    end
  end

  defp extract_username_from_uri(uri) do
    case Regex.run(~r{://([^@]+)@}, uri) do
      [_, user] -> user
      _ -> nil
    end
  end
end
