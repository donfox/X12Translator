defmodule X12Bridge.BatchProcessorTest do
  use ExUnit.Case, async: true

  alias X12Bridge.BatchProcessor
  alias X12Bridge.BatchProcessor.{BatchResult, FileResult}

  @moduletag :batch_processing

  describe "process_test_batch/2" do
    test "processes batch_quick successfully" do
      {:ok, result} = BatchProcessor.process_test_batch("batch_quick")

      assert %BatchResult{} = result
      assert result.total_files == 5
      assert result.successful_files == 4
      assert result.failed_files == 1
      assert result.processing_time_ms > 0

      # Verify manifest was created
      assert File.exists?(result.manifest_path)

      # Verify output files were created
      output_files = Path.join(result.output_directory, "*.json")
                     |> Path.wildcard()

      # 4 successful files + 1 manifest
      assert length(output_files) == 5

      # Verify failed files were moved
      failed_files = Path.join(result.failed_directory, "*.x12")
                     |> Path.wildcard()

      assert length(failed_files) == 1

      # Verify error report was created
      error_reports = Path.join(result.failed_directory, "*_error.json")
                      |> Path.wildcard()

      assert length(error_reports) == 1
    end

    test "processes batch_realistic successfully" do
      {:ok, result} = BatchProcessor.process_test_batch("batch_realistic")

      assert %BatchResult{} = result
      assert result.total_files == 50
      assert result.successful_files == 45
      assert result.failed_files == 5
      assert result.processing_time_ms > 0
    end

    @tag :performance
    test "processes batch_performance with good throughput" do
      start_time = System.monotonic_time(:millisecond)
      {:ok, result} = BatchProcessor.process_test_batch("batch_performance")
      total_time = System.monotonic_time(:millisecond) - start_time

      assert %BatchResult{} = result
      assert result.total_files == 500
      assert result.successful_files == 475
      assert result.failed_files == 25

      # Performance assertions
      # With 10 concurrent workers, 500 files should process in under 2 minutes
      assert total_time < 120_000, "Batch took too long: #{total_time}ms"

      # Calculate throughput
      files_per_second = result.total_files / (total_time / 1000)

      IO.puts("\n=== Performance Results ===")
      IO.puts("Total files: #{result.total_files}")
      IO.puts("Processing time: #{total_time}ms (#{Float.round(total_time / 1000, 2)}s)")
      IO.puts("Throughput: #{Float.round(files_per_second, 2)} files/second")
      IO.puts("Average per file: #{Float.round(total_time / result.total_files, 2)}ms")
      IO.puts("==========================\n")

      # Should process at least 5 files per second with concurrency
      assert files_per_second > 5.0
    end
  end

  describe "process_single_file/3" do
    setup do
      batch_id = "test_#{:os.system_time(:millisecond)}"
      config = %{
        output_dir: "priv/batch_processing/output",
        failed_dir: "priv/batch_processing/failed"
      }

      # Ensure directories exist
      File.mkdir_p!(Path.join(config.output_dir, batch_id))
      File.mkdir_p!(Path.join(config.failed_dir, batch_id))

      {:ok, batch_id: batch_id, config: config}
    end

    test "processes valid X12 file successfully", %{batch_id: batch_id, config: config} do
      file_path = "priv/test_data/batches/batch_quick/001_837p_valid.x12"

      result = BatchProcessor.process_single_file(file_path, batch_id, config)

      assert %FileResult{} = result
      assert result.status == :success
      assert result.filename == "001_837p_valid.x12"
      assert result.processing_time_ms > 0
      assert result.output_path != nil
      assert result.claims_count == 1

      # Verify JSON was created
      assert File.exists?(result.output_path)
    end

    test "handles malformed X12 file", %{batch_id: batch_id, config: config} do
      file_path = "priv/test_data/batches/batch_quick/005_837p_error.x12"

      result = BatchProcessor.process_single_file(file_path, batch_id, config)

      assert %FileResult{} = result
      assert result.status == :failed
      assert result.filename == "005_837p_error.x12"
      assert result.error_message != nil

      # Verify failed file was moved
      failed_path = Path.join(config.failed_dir, batch_id)
      failed_files = Path.wildcard(Path.join(failed_path, "*.x12"))
      assert length(failed_files) == 1

      # Verify error report was created
      error_reports = Path.wildcard(Path.join(failed_path, "*_error.json"))
      assert length(error_reports) == 1
    end
  end

  describe "concurrent processing" do
    test "processes multiple files concurrently" do
      # This test verifies that concurrent processing is faster than sequential
      # We'll process the batch_realistic with different concurrency settings

      # Sequential (concurrency = 1)
      start_sequential = System.monotonic_time(:millisecond)
      {:ok, _result} = BatchProcessor.process_test_batch("batch_realistic", max_concurrency: 1)
      sequential_time = System.monotonic_time(:millisecond) - start_sequential

      # Concurrent (concurrency = 10)
      start_concurrent = System.monotonic_time(:millisecond)
      {:ok, _result} = BatchProcessor.process_test_batch("batch_realistic", max_concurrency: 10)
      concurrent_time = System.monotonic_time(:millisecond) - start_concurrent

      IO.puts("\n=== Concurrency Comparison ===")
      IO.puts("Sequential (1 worker): #{sequential_time}ms")
      IO.puts("Concurrent (10 workers): #{concurrent_time}ms")
      IO.puts("Speedup: #{Float.round(sequential_time / concurrent_time, 2)}x")
      IO.puts("==============================\n")

      # Concurrent should be faster than sequential (may not be 3x for small batches due to overhead)
      # For larger batches, the speedup will be more significant
      assert concurrent_time <= sequential_time,
        "Concurrent processing (#{concurrent_time}ms) should be faster than sequential (#{sequential_time}ms)"
    end
  end

  describe "batch results" do
    test "includes detailed file results" do
      {:ok, result} = BatchProcessor.process_test_batch("batch_quick")

      assert length(result.files) == 5

      # Check that file results have all expected fields
      Enum.each(result.files, fn file_result ->
        assert %FileResult{} = file_result
        assert file_result.filename != nil
        assert file_result.status in [:success, :failed]
        assert file_result.processing_time_ms > 0

        if file_result.status == :success do
          assert file_result.output_path != nil
        else
          assert file_result.error_message != nil
        end
      end)
    end

    test "manifest contains accurate summary" do
      {:ok, result} = BatchProcessor.process_test_batch("batch_quick")

      # Read and parse manifest
      {:ok, manifest_json} = File.read(result.manifest_path)
      {:ok, manifest} = Jason.decode(manifest_json)

      assert manifest["batch_id"] != nil
      assert manifest["total_files"] == 5
      assert manifest["successful_files"] == 4
      assert manifest["failed_files"] == 1
      assert manifest["total_processing_time_ms"] > 0
      assert length(manifest["files"]) == 5

      # Verify individual file entries
      successful_count = Enum.count(manifest["files"], fn f -> f["status"] == "success" end)
      failed_count = Enum.count(manifest["files"], fn f -> f["status"] == "failed" end)

      assert successful_count == 4
      assert failed_count == 1
    end
  end
end
