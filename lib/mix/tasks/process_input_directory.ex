defmodule Mix.Tasks.ProcessInputDirectory do
  @moduledoc """
  Processes X12 files from an input directory and writes JSON files to an output directory.

  Usage:
    mix process_input_directory --input /path/to/input --output /path/to/output
  """

  @shortdoc "Process X12 files from input directory"

  use Mix.Task

  alias X12Bridge.BatchProcessor

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        switches: [input: :string, output: :string, batch_name: :string]
      )

    batch_opts =
      %{}
      |> maybe_put(:input_dir, opts[:input])
      |> maybe_put(:output_dir, opts[:output])
      |> maybe_put(:batch_name, opts[:batch_name])

    case BatchProcessor.process_input_directory(batch_opts) do
      {:ok, result} ->
        Mix.shell().info("Batch completed: #{result.batch_id}")
        Mix.shell().info("  Input:  #{result.input_directory}")
        Mix.shell().info("  Output: #{result.output_directory}")
        Mix.shell().info("  Total:  #{result.total_files}")
        Mix.shell().info("  OK:     #{result.successful_files}")
        Mix.shell().info("  Failed: #{result.failed_files}")

        if result.output_summary do
          Mix.shell().info(
            "  Written: #{result.output_summary.written} (#{result.output_summary.failed} failed)"
          )
        end

      {:error, reason} ->
        Mix.shell().error("Batch processing failed: #{inspect(reason)}")
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
