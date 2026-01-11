defmodule X12Bridge.BatchProcessorTest do
  use ExUnit.Case, async: true

  alias X12Bridge.BatchProcessor
  alias X12Bridge.BatchProcessor.{BatchResult, FileResult}

  @moduletag :batch_processing

  describe "process_test_batch/2" do
    test "processes automated_test_data successfully" do
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

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
      file_path = "test/fixtures/automated_test_data/001_837p_valid.x12"

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
      file_path = "test/fixtures/automated_test_data/005_837p_error.x12"

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

  describe "batch results" do
    test "includes detailed file results" do
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

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
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

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
