defmodule Mix.Tasks.Setup.CheckEnv do
  @moduledoc """
  Checks for PostgreSQL environment variables that might conflict with config/dev.exs

  This task runs before `mix setup` to warn users about environment variables
  that override the default database configuration.
  """
  @shortdoc "Check for PostgreSQL environment variable conflicts"

  use Mix.Task

  @pg_env_vars ~w(PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE)

  # ANSI color codes
  @yellow "\e[33m"
  @blue "\e[34m"
  @green "\e[32m"
  @reset "\e[0m"

  @impl Mix.Task
  def run(_args) do
    env_vars = get_pg_env_vars()

    if Enum.any?(env_vars) do
      show_warning(env_vars)
    else
      show_success()
    end

    :ok
  end

  defp get_pg_env_vars do
    @pg_env_vars
    |> Enum.map(fn var -> {var, System.get_env(var)} end)
    |> Enum.reject(fn {_var, value} -> is_nil(value) end)
  end

  defp show_warning(env_vars) do
    IO.puts([
      "\n",
      @yellow,
      "⚠️  WARNING: PostgreSQL environment variables detected!",
      @reset,
      "\n"
    ])

    IO.puts("These environment variables will override config/dev.exs settings:")
    IO.puts("")

    Enum.each(env_vars, fn {var, value} ->
      IO.puts("  #{@blue}#{var}=#{value}#{@reset}")
    end)

    IO.puts("")
    IO.puts("Expected configuration (from config/dev.exs):")
    IO.puts("  hostname: localhost")
    IO.puts("  port:     5432")
    IO.puts("  username: postgres")
    IO.puts("  database: x12_bridge_dev")
    IO.puts("")

    show_effective_config(env_vars)

    IO.puts([
      @yellow,
      "If this is NOT intentional, fix it by running:",
      @reset
    ])

    IO.puts("")
    IO.puts("  unset PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE")
    IO.puts("")
    IO.puts("Or run the validation script for detailed guidance:")
    IO.puts("  bash priv/scripts/check_setup.sh")
    IO.puts("")

    case prompt_continue() do
      :continue ->
        IO.puts([
          @green,
          "✓ Continuing with environment variable configuration...",
          @reset,
          "\n"
        ])

      :abort ->
        Mix.raise("""
        Setup aborted.

        To fix environment variable conflicts:
          1. Run: unset PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE
          2. Or run: bash priv/scripts/check_setup.sh
          3. Then try: mix setup again
        """)
    end
  end

  defp show_effective_config(env_vars) do
    env_map = Map.new(env_vars)

    effective_host = Map.get(env_map, "PGHOST", "localhost")
    effective_port = Map.get(env_map, "PGPORT", "5432")
    effective_user = Map.get(env_map, "PGUSER", "postgres")
    effective_db = Map.get(env_map, "PGDATABASE", "x12_bridge_dev")

    IO.puts("Effective configuration that will be used:")
    IO.puts("  Host:     #{effective_host}")
    IO.puts("  Port:     #{effective_port}")
    IO.puts("  User:     #{effective_user}")
    IO.puts("  Database: #{effective_db}")
    IO.puts("")
  end

  defp show_success do
    IO.puts([
      @green,
      "✓ No conflicting PostgreSQL environment variables detected.",
      @reset,
      "\n"
    ])
  end

  defp prompt_continue do
    if System.get_env("CI") || !io_interactive?() do
      # In CI or non-interactive mode, continue without prompting
      :continue
    else
      answer =
        IO.gets(
          "Do you want to continue with this configuration? [y/N] "
        )
        |> to_string()
        |> String.trim()
        |> String.downcase()

      case answer do
        answer when answer in ["y", "yes"] -> :continue
        _ -> :abort
      end
    end
  end

  defp io_interactive? do
    # Check if we're in an interactive terminal
    match?({:ok, _}, :io.columns())
  end
end
