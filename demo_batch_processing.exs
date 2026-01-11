#!/usr/bin/env elixir

# Demo script for X12Bridge Batch Processing
# This demonstrates the hot folder pattern with concurrent processing

IO.puts """
========================================
X12Bridge Batch Processing Demo
========================================

This demo shows:
1. Hot folder pattern (input → output/failed)
2. Concurrent processing using Elixir's Task.async_stream
3. Performance comparison: sequential vs concurrent

"""

# Ensure we're in the right directory
if !File.exists?("mix.exs") do
  IO.puts "Error: Please run this script from the X12Bridge project root"
  System.halt(1)
end

# Start the application
Mix.install([], system_env: [{"MIX_ENV", "dev"}])
Application.ensure_all_started(:x12_bridge)

alias X12Bridge.BatchProcessor

IO.puts "📁 Directory Structure:\n"
IO.puts "   Input:   priv/batch_processing/input/"
IO.puts "   Output:  priv/batch_processing/output/"
IO.puts "   Failed:  priv/batch_processing/failed/"
IO.puts ""

# Demo 1: Automated test data batch (5 files)
IO.puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
IO.puts "Demo 1: Automated Test Data (5 files)"
IO.puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

IO.puts "Processing automated_test_data..."
{time_quick, {:ok, result_quick}} = :timer.tc(fn ->
  BatchProcessor.process_test_batch("automated_test_data")
end)

IO.puts """

✓ Completed in #{Float.round(time_quick / 1_000_000, 2)}s

Results:
  Total files:      #{result_quick.total_files}
  ✓ Successful:     #{result_quick.successful_files}
  ✗ Failed:         #{result_quick.failed_files}
  Processing time:  #{result_quick.processing_time_ms}ms
  Output dir:       #{result_quick.output_directory}
  Failed dir:       #{result_quick.failed_directory}

"""

# Show output files
output_files = Path.join(result_quick.output_directory, "*.json") |> Path.wildcard()
IO.puts "Output files created:"
Enum.each(output_files, fn file ->
  IO.puts "  - #{Path.basename(file)}"
end)

# Show failed files
failed_files = Path.join(result_quick.failed_directory, "*.*") |> Path.wildcard()
if length(failed_files) > 0 do
  IO.puts "\nFailed files:"
  Enum.each(failed_files, fn file ->
    IO.puts "  - #{Path.basename(file)}"
  end)
end

IO.puts "\n"

# Demo 2: Concurrency comparison
IO.puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
IO.puts "Demo 2: Concurrency Impact (5 files)"
IO.puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

IO.puts "Testing different concurrency levels:\n"

concurrency_levels = [1, 2, 5]
results = Enum.map(concurrency_levels, fn concurrency ->
  IO.write("  Testing concurrency=#{concurrency}... ")
  {time, {:ok, result}} = :timer.tc(fn ->
    BatchProcessor.process_test_batch("automated_test_data", max_concurrency: concurrency)
  end)

  time_seconds = time / 1_000_000
  throughput = result.total_files / time_seconds

  IO.puts("#{Float.round(time_seconds, 2)}s (#{Float.round(throughput, 2)} files/sec)")

  {concurrency, time_seconds, throughput}
end)

IO.puts "\n"
IO.puts "Concurrency Analysis:"
IO.puts String.duplicate("-", 50)
IO.puts String.pad_trailing("Workers", 12) <>
        String.pad_trailing("Time", 12) <>
        String.pad_trailing("Throughput", 15) <>
        "Speedup"
IO.puts String.duplicate("-", 50)

base_time = elem(Enum.at(results, 0), 1)

Enum.each(results, fn {concurrency, time, throughput} ->
  speedup = base_time / time
  IO.puts String.pad_trailing("#{concurrency}", 12) <>
          String.pad_trailing("#{Float.round(time, 2)}s", 12) <>
          String.pad_trailing("#{Float.round(throughput, 2)} files/s", 15) <>
          "#{Float.round(speedup, 2)}x"
end)

IO.puts String.duplicate("-", 50)

IO.puts """


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Key Takeaways
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Hot Folder Pattern:
   - X12 files placed in input directory
   - Processed files → JSON in output directory
   - Failed files → failed directory with error reports

2. Concurrent Processing:
   - Elixir's Task.async_stream processes files in parallel
   - #{Enum.at(results, 2) |> elem(0)} concurrent workers = ~#{Float.round(elem(Enum.at(results, 2), 1) / elem(Enum.at(results, 0), 1), 1)}x speedup
   - Throughput increases with concurrency even on small batches

3. Error Handling:
   - Failed files isolated in failed directory
   - Error reports in JSON format for debugging
   - Batch continues processing on file-level errors

4. Test Data:
   - Automated test data: test/fixtures/x12/automated_test_data/
   - Real-world samples: test/fixtures/x12/manual_test_data/
   - Generate custom batches: mix generate_batch custom --size N --name my_batch

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 Next Steps:
   1. Run tests: mix test test/x12_bridge/batch_processor_test.exs
   2. Try processing your own files in priv/batch_processing/input/
   3. Generate custom test data: mix generate_batch custom --size 100 --name my_batch

"""
