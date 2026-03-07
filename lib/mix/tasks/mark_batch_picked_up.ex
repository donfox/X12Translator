defmodule Mix.Tasks.MarkBatchPickedUp do
  @moduledoc """
  Marks a batch as picked up and deletes input X12 files.

  Usage:
    mix mark_batch_picked_up --batch <batch_id> [--keep-input]
  """

  @shortdoc "Mark batch picked up and delete input files"

  use Mix.Task

  alias X12Translator.Conversions

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        switches: [batch: :string, keep_input: :boolean]
      )

    batch_id = opts[:batch]
    keep_input = opts[:keep_input] || false

    if is_nil(batch_id) do
      Mix.shell().error("Missing --batch <batch_id>")
      System.halt(1)
    end

    batch = Conversions.get_batch!(batch_id)
    picked_up_at = DateTime.utc_now()

    Enum.each(batch.jobs, fn job ->
      updates = %{
        picked_up_at: picked_up_at,
        delivery_status: "picked_up"
      }

      updates =
        if keep_input do
          updates
        else
          delete_input_file(job, updates)
        end

      Conversions.update_job(job, updates)
    end)

    Mix.shell().info("Marked batch #{batch_id} as picked up")

    if keep_input do
      Mix.shell().info("Input files were preserved (--keep-input)")
    else
      Mix.shell().info("Input files were deleted")
    end
  end

  defp delete_input_file(job, updates) do
    if job.input_path && File.exists?(job.input_path) do
      case File.rm(job.input_path) do
        :ok ->
          updates
          |> Map.put(:deleted_at, DateTime.utc_now())
          |> Map.put(:delivery_status, "deleted")

        {:error, reason} ->
          Mix.shell().error("Failed to delete #{job.input_path}: #{inspect(reason)}")

          updates
      end
    else
      updates
    end
  end
end
