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
    # Add a diagnostic heartbeat job — fires every minute to prove Quantum works
    heartbeat =
      X12Translator.Scheduler.new_job()
      |> Quantum.Job.set_name(:heartbeat)
      |> Quantum.Job.set_schedule(Crontab.CronExpression.Parser.parse!("* * * * *"))
      |> Quantum.Job.set_task({__MODULE__, :heartbeat, []})

    X12Translator.Scheduler.add_job(heartbeat)
    Logger.info("ConfigPoller: added heartbeat job (fires every minute)")

    send(self(), :poll)
    {:ok, %{last_config: nil}}
  end

  def heartbeat do
    Logger.info("ConfigPoller: ♥ heartbeat — Quantum is alive at #{DateTime.utc_now()}")
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_next_poll()

    case fetch_config() do
      {:ok, config} ->
        # Build a stable fingerprint: only source IDs, URIs, types, and schedule expressions
        comparable = config_fingerprint(config)

        if comparable != state.last_config do
          source_count = length(config["fetch_sources"] || [])
          schedule_count = config["fetch_sources"] |> List.wrap() |> Enum.flat_map(& &1["schedules"] || []) |> length()
          Logger.info("ConfigPoller: config changed — #{source_count} source(s), #{schedule_count} schedule(s)")
          update_schedules(config)
          {:noreply, %{state | last_config: comparable}}
        else
          {:noreply, state}
        end

      {:error, reason} ->
        Logger.warning("ConfigPoller: failed to fetch config — #{inspect(reason)}")
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

        timezone = Application.get_env(:x12_translator, X12Translator.Scheduler, []) |> Keyword.get(:timezone, "Etc/UTC")

        job =
          X12Translator.Scheduler.new_job()
          |> Quantum.Job.set_name(job_name)
          |> Quantum.Job.set_schedule(quantum_schedule)
          |> Quantum.Job.set_timezone(timezone)
          |> Quantum.Job.set_task({X12Translator.FetchRunner, :run, [source]})

        X12Translator.Scheduler.add_job(job)
        Logger.info("ConfigPoller: added job #{job_name} — cron: #{schedule["cron_expression"] || "interval #{schedule["interval_seconds"]}s"} (tz: #{timezone})")
      end)
    end)

    active_jobs = X12Translator.Scheduler.jobs() |> Enum.map(fn {name, _} -> name end)
    Logger.info("ConfigPoller: active Quantum jobs: #{inspect(active_jobs)}")
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

  defp config_fingerprint(%{"fetch_sources" => sources}) when is_list(sources) do
    Enum.map(sources, fn source ->
      schedules =
        (source["schedules"] || [])
        |> Enum.map(fn s ->
          %{
            "id" => s["id"],
            "cron_expression" => s["cron_expression"],
            "interval_seconds" => s["interval_seconds"],
            "enabled" => s["enabled"]
          }
        end)
        |> Enum.sort_by(& &1["id"])

      %{
        "id" => source["id"],
        "uri" => source["uri"],
        "source_type" => source["source_type"],
        "schedules" => schedules
      }
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp config_fingerprint(_), do: nil
end
