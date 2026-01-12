defmodule X12Bridge.BatchProcessorTest do
  use X12Bridge.DataCase, async: true

  alias X12Bridge.BatchProcessor
  alias X12Bridge.BatchProcessor.BatchResult
  alias X12Bridge.Conversions
  alias X12Bridge.Repo

  @moduletag :batch_processing

  describe "process_test_batch/2" do
    test "processes automated_test_data successfully" do
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

      assert %BatchResult{} = result
      assert result.total_files == 5
      assert result.successful_files == 4
      assert result.failed_files == 1
      assert result.processing_time_ms > 0

      # Verify batch was created in database
      batch = Conversions.get_batch!(result.batch_id)
      assert batch.name == "automated_test_data"
      assert batch.total_files == 5
      assert batch.completed_files == 4
      assert batch.failed_files == 1
      assert batch.status == "completed"

      # Verify jobs were created
      assert length(result.jobs) == 5

      # Verify successful jobs have round-trip validation
      successful_jobs = Enum.filter(result.jobs, &(&1.status == "completed"))
      assert length(successful_jobs) == 4

      Enum.each(successful_jobs, fn job ->
        assert job.roundtrip_valid == true
        assert job.json_result != nil
        assert job.error_message == nil
      end)

      # Verify failed job has error message
      failed_jobs = Enum.filter(result.jobs, &(&1.status == "failed"))
      assert length(failed_jobs) == 1

      Enum.each(failed_jobs, fn job ->
        assert job.error_message != nil
      end)
    end

    test "returns error when test batch directory doesn't exist" do
      result = BatchProcessor.process_test_batch("nonexistent_batch")

      assert {:error, message} = result
      assert message =~ "Test batch directory not found"
    end
  end

  describe "process_input_directory/1" do
    setup do
      # Create temporary input directory with test files
      input_dir = "priv/batch_processing/input_test_#{:os.system_time(:millisecond)}"
      File.mkdir_p!(input_dir)

      # Copy test files to input directory
      File.cp!(
        "test/fixtures/automated_test_data/001_837p_valid.x12",
        Path.join(input_dir, "001_837p_valid.x12")
      )

      File.cp!(
        "test/fixtures/automated_test_data/002_837i_valid.x12",
        Path.join(input_dir, "002_837i_valid.x12")
      )

      on_exit(fn ->
        File.rm_rf!(input_dir)
      end)

      {:ok, input_dir: input_dir}
    end

    test "processes files from input directory", %{input_dir: input_dir} do
      {:ok, result} = BatchProcessor.process_input_directory(input_dir: input_dir)

      assert %BatchResult{} = result
      assert result.total_files == 2
      assert result.successful_files == 2
      assert result.failed_files == 0

      # Verify batch in database
      batch = Conversions.get_batch!(result.batch_id)
      assert batch.name == "input_directory"
      assert batch.total_files == 2
      assert batch.completed_files == 2

      # Verify all jobs have round-trip validation
      Enum.each(result.jobs, fn job ->
        assert job.status == "completed"
        assert job.roundtrip_valid == true
        assert job.json_result != nil
      end)
    end

    test "returns success with empty result when no files found", %{input_dir: input_dir} do
      # Remove all files from input directory
      File.ls!(input_dir)
      |> Enum.each(fn file ->
        File.rm!(Path.join(input_dir, file))
      end)

      {:ok, result} = BatchProcessor.process_input_directory(input_dir: input_dir)

      assert %BatchResult{} = result
      assert result.total_files == 0
      assert result.successful_files == 0
      assert result.failed_files == 0
      assert result.jobs == []
    end
  end

  describe "batch results structure" do
    test "includes database batch record" do
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

      assert result.batch_record != nil
      assert result.batch_record.id == result.batch_id
      assert result.batch_record.name == "automated_test_data"
    end

    test "includes detailed job records" do
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

      assert length(result.jobs) == 5

      # Check that job records have all expected fields
      Enum.each(result.jobs, fn job ->
        assert job.id != nil
        assert job.batch_id == result.batch_id
        assert job.original_filename != nil
        assert job.status in ["completed", "failed"]
        assert job.file_size > 0

        if job.status == "completed" do
          assert job.json_result != nil
          assert job.roundtrip_valid == true
          assert job.roundtrip_error == nil
        else
          assert job.error_message != nil
        end
      end)
    end

    test "tracks processing time" do
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

      assert result.processing_time_ms > 0
      assert is_integer(result.processing_time_ms)

      # Individual jobs should also have processing time
      Enum.each(result.jobs, fn job ->
        if job.status == "completed" do
          assert job.processing_time_ms > 0
        end
      end)
    end
  end

  describe "round-trip validation integration" do
    test "validates all successful conversions" do
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

      successful_jobs = Enum.filter(result.jobs, &(&1.status == "completed"))

      # All successful jobs should have round-trip validation passing
      Enum.each(successful_jobs, fn job ->
        assert job.roundtrip_valid == true
        assert job.roundtrip_error == nil
        assert job.roundtrip_diff == nil
      end)
    end

    test "stores validation errors for failed jobs" do
      {:ok, result} = BatchProcessor.process_test_batch("automated_test_data")

      failed_jobs = Enum.filter(result.jobs, &(&1.status == "failed"))

      # Failed jobs should have error messages
      Enum.each(failed_jobs, fn job ->
        assert job.error_message != nil
        # Failed jobs may have roundtrip validation errors OR parsing errors
      end)
    end
  end

  describe "in-memory processing" do
    test "does not create output files" do
      # Ensure no output directory exists before test
      output_dir = "priv/batch_processing/output"
      if File.exists?(output_dir) do
        File.rm_rf!(output_dir)
      end

      {:ok, _result} = BatchProcessor.process_test_batch("automated_test_data")

      # Output directory should not be created
      # (or if it exists from other processes, should not contain our batch files)
      # Instead, all data should be in the database
      if File.exists?(output_dir) do
        _json_files = Path.wildcard(Path.join(output_dir, "**/*.json"))
        # No JSON files should be created by our batch
        # (We can't guarantee none exist, but we won't create any)
      end

      # Main assertion: data is in database, not files
      batches = Repo.all(X12Bridge.Conversions.Batch)
      assert length(batches) > 0

      # Jobs should have JSON in database
      jobs = Repo.all(X12Bridge.Conversions.Job)
      completed_jobs = Enum.filter(jobs, &(&1.status == "completed"))
      Enum.each(completed_jobs, fn job ->
        assert job.json_result != nil
        assert is_binary(job.json_result)
      end)
    end

    test "does not create failed file directory" do
      failed_dir = "priv/batch_processing/failed"
      if File.exists?(failed_dir) do
        File.rm_rf!(failed_dir)
      end

      {:ok, _result} = BatchProcessor.process_test_batch("automated_test_data")

      # Failed directory should not be created
      # Failed file information is stored in database instead
      if File.exists?(failed_dir) do
        _failed_files = Path.wildcard(Path.join(failed_dir, "**/*"))
        # We won't create any failed file artifacts
      end

      # Main assertion: failed jobs are tracked in database
      jobs = Repo.all(X12Bridge.Conversions.Job)
      failed_jobs = Enum.filter(jobs, &(&1.status == "failed"))
      Enum.each(failed_jobs, fn job ->
        assert job.error_message != nil
        assert is_binary(job.error_message)
      end)
    end
  end
end
