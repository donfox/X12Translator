defmodule X12Translator.ConfigPoller do
  @moduledoc """
  Polls medicaid_claims_checker for fetch source configuration and
  dynamically updates Quantum scheduler jobs to match.
  """
  use GenServer
  require Logger

  @default_poll_interval_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send(self(), :poll)
    {:ok, %{last_config: nil}}
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_next_poll()

    case fetch_config() do
      {:ok, config} ->
        if config != state.last_config do
          Logger.info("Fetch config changed, updating Quantum schedules")
          update_schedules(config)
          {:noreply, %{state | last_config: config}}
        else
          {:noreply, state}
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch config from medicaid_claims_checker: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp schedule_next_poll do
    interval = poll_interval()
    Process.send_after(self(), :poll, interval)
  end

  defp poll_interval do
    Application.get_env(:x12_translator, :config_poller, [])
    |> Keyword.get(:poll_interval_ms, @default_poll_interval_ms)
  end

  defp config_url do
    Application.get_env(:x12_translator, :config_poller, [])
    |> Keyword.get(:url, "http://localhost:4000/api/fetch-config")
  end

  defp fetch_config do
    case Req.get(config_url(), receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_schedules(%{"fetch_sources" => sources}) do
    # Remove all dynamically-created fetch jobs
    X12Translator.Scheduler.jobs()
    |> Enum.filter(fn {name, _job} -> String.starts_with?(to_string(name), "fetch_") end)
    |> Enum.each(fn {name, _job} -> X12Translator.Scheduler.delete_job(name) end)

    # Create new jobs from config
    Enum.each(sources, fn source ->
      Enum.each(source["schedules"] || [], fn schedule ->
        job_name = String.to_atom("fetch_#{source["id"]}_#{schedule["id"]}")

        quantum_schedule =
          if schedule["cron_expression"] do
            Crontab.CronExpression.Parser.parse!(schedule["cron_expression"])
          else
            build_interval_schedule(schedule["interval_seconds"])
          end

        job =
          X12Translator.Scheduler.new_job()
          |> Quantum.Job.set_name(job_name)
          |> Quantum.Job.set_schedule(quantum_schedule)
          |> Quantum.Job.set_task({X12Translator.FetchRunner, :run, [source]})

        X12Translator.Scheduler.add_job(job)
        Logger.info("Added fetch job #{job_name} for source '#{source["name"]}'")
      end)
    end)
  end

  defp update_schedules(_), do: :ok

  defp build_interval_schedule(seconds) when is_integer(seconds) and seconds <= 60 do
    Crontab.CronExpression.Parser.parse!("* * * * *")
  end

  defp build_interval_schedule(seconds) when is_integer(seconds) and seconds <= 3600 do
    minutes = div(seconds, 60)
    Crontab.CronExpression.Parser.parse!("*/#{minutes} * * * *")
  end

  defp build_interval_schedule(seconds) when is_integer(seconds) do
    hours = max(div(seconds, 3600), 1)
    Crontab.CronExpression.Parser.parse!("0 */#{hours} * * *")
  end

  defp build_interval_schedule(_), do: Crontab.CronExpression.Parser.parse!("0 * * * *")
end
