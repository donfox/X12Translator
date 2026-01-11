defmodule Mix.Tasks.GenBatchData do
  @moduledoc """
  Generates mock batch data for testing batch processing.

  Usage:
      mix gen_batch_data custom --size 25 --name my_batch

  Note: This task is deprecated. For standard testing, use existing fixtures:
      test/fixtures/x12/automated_test_data/

  For custom test scenarios, use:
      mix generate_batch custom --size N --name batch_name
  """

  use Mix.Task

  @shortdoc "Deprecated: Use mix generate_batch instead"

  @base_path "test/fixtures/x12"
  @batches_path @base_path
  @single_path "#{@base_path}/automated_test_data"

  def run(args) do
    Mix.shell().info("⚠️  This task is deprecated. For standard testing, use: test/fixtures/x12/automated_test_data/")
    Mix.shell().info("   For custom batches, use: mix generate_batch custom --size N --name batch_name\n")

    case args do
      ["quick"] -> generate_quick_batch()
      ["realistic"] -> generate_realistic_batch()
      ["performance"] -> generate_performance_batch()
      ["edge_cases"] -> generate_edge_cases_batch()
      ["all"] -> generate_all_batches()
      _ ->
        Mix.shell().info("Usage: mix gen_batch_data [quick|realistic|performance|edge_cases|all]")
        :ok
    end
  end

  defp generate_all_batches do
    generate_quick_batch()
    generate_realistic_batch()
    generate_performance_batch()
    generate_edge_cases_batch()
  end

  defp generate_quick_batch do
    batch_dir = Path.join(@batches_path, "batch_quick")
    File.mkdir_p!(batch_dir)

    Mix.shell().info("Generating quick batch (5 files)...")

    # Copy and modify existing samples
    files = [
      copy_and_modify("sample_837p.x12", "001_837p_valid.x12", batch_dir, "837P", 1),
      copy_and_modify("sample_837i.x12", "002_837i_valid.x12", batch_dir, "837I", 1),
      copy_and_modify("sample_837d.x12", "003_837d_valid.x12", batch_dir, "837D", 1),
      duplicate_with_claims("sample_837p.x12", "004_837p_multi.x12", batch_dir, "837P", 3),
      create_error_file("005_837p_error.x12", batch_dir)
    ]

    # Generate manifest
    manifest = %{
      batch_id: "batch_quick_001",
      description: "Quick batch for smoke tests",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      total_files: 5,
      files: files
    }

    File.write!(
      Path.join(batch_dir, "manifest.json"),
      Jason.encode!(manifest, pretty: true)
    )

    Mix.shell().info("✓ Generated quick batch in #{batch_dir}")
  end

  defp generate_realistic_batch do
    batch_dir = Path.join(@batches_path, "batch_realistic")
    File.mkdir_p!(batch_dir)

    Mix.shell().info("Generating realistic batch (25 files)...")

    files =
      for i <- 1..25 do
        # Distribute types: 60% 837P, 30% 837I, 10% 837D (realistic distribution)
        type = case rem(i, 10) do
          n when n in [0, 1, 2, 3, 4, 5] -> "837P"
          n when n in [6, 7, 8] -> "837I"
          9 -> "837D"
        end

        source_file = "sample_#{String.downcase(type)}.x12"
        dest_file = "claim_#{String.pad_leading(to_string(i), 3, "0")}.x12"

        copy_and_modify(source_file, dest_file, batch_dir, type, 1)
      end

    manifest = %{
      batch_id: "batch_realistic_001",
      description: "Realistic batch simulating typical user workflow",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      total_files: 25,
      files: files
    }

    File.write!(
      Path.join(batch_dir, "manifest.json"),
      Jason.encode!(manifest, pretty: true)
    )

    Mix.shell().info("✓ Generated realistic batch in #{batch_dir}")
  end

  defp generate_performance_batch do
    batch_dir = Path.join(@batches_path, "batch_performance")
    File.mkdir_p!(batch_dir)

    Mix.shell().info("Generating performance batch (100 files)...")

    Enum.each(1..100, fn i ->
      if rem(i, 20) == 0 do
        Mix.shell().info("  Progress: #{i}/100")
      end

      type = case rem(i, 3) do
        0 -> "837P"
        1 -> "837I"
        2 -> "837D"
      end

      source_file = "sample_#{String.downcase(type)}.x12"
      dest_file = "perf_#{String.pad_leading(to_string(i), 4, "0")}.x12"

      copy_and_modify(source_file, dest_file, batch_dir, type, 1)
    end)

    manifest = %{
      batch_id: "batch_performance_001",
      description: "Performance test batch with 100 files",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      total_files: 100
    }

    File.write!(
      Path.join(batch_dir, "manifest.json"),
      Jason.encode!(manifest, pretty: true)
    )

    Mix.shell().info("✓ Generated performance batch in #{batch_dir}")
  end

  defp generate_edge_cases_batch do
    batch_dir = Path.join(@batches_path, "batch_edge_cases")
    File.mkdir_p!(batch_dir)

    Mix.shell().info("Generating edge cases batch...")

    files = [
      create_error_file("invalid_delimiter.x12", batch_dir),
      create_error_file("missing_segments.x12", batch_dir),
      create_error_file("corrupt_data.x12", batch_dir),
      copy_and_modify("sample_837p.x12", "valid_minimal.x12", batch_dir, "837P", 1)
    ]

    manifest = %{
      batch_id: "batch_edge_cases_001",
      description: "Edge cases and error conditions",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      total_files: length(files),
      files: files
    }

    File.write!(
      Path.join(batch_dir, "manifest.json"),
      Jason.encode!(manifest, pretty: true)
    )

    Mix.shell().info("✓ Generated edge cases batch in #{batch_dir}")
  end

  # Helper functions
  defp copy_and_modify(source_filename, dest_filename, dest_dir, type, num_claims) do
    source_path = Path.join(@single_path, source_filename)
    dest_path = Path.join(dest_dir, dest_filename)

    content = File.read!(source_path)

    # Modify control numbers to be unique
    modified_content = modify_control_numbers(content, dest_filename)

    File.write!(dest_path, modified_content)

    %{
      filename: dest_filename,
      type: type,
      expected_status: "success",
      expected_claims: num_claims,
      description: "Valid #{type} claim"
    }
  end

  defp duplicate_with_claims(source_filename, dest_filename, dest_dir, type, num_claims) do
    source_path = Path.join(@single_path, source_filename)
    dest_path = Path.join(dest_dir, dest_filename)

    content = File.read!(source_path)
    modified_content = modify_control_numbers(content, dest_filename)

    File.write!(dest_path, modified_content)

    %{
      filename: dest_filename,
      type: type,
      expected_status: "success",
      expected_claims: num_claims,
      description: "#{type} with #{num_claims} claims"
    }
  end

  defp create_error_file(filename, dest_dir) do
    dest_path = Path.join(dest_dir, filename)

    # Create intentionally malformed content
    content = case filename do
      "invalid_delimiter" <> _ ->
        "ISA|00|          |00|          |ZZ|BAD|||||||||||~\n"

      "missing_segments" <> _ ->
        "ISA*00*          *00*          *ZZ*TEST*ZZ*TEST*250101*1200*U*00401*000000001*0*P*:~\n" <>
        "GS*HC*TEST*TEST*20250101*1200*1*X*004010X098A1~\n" <>
        "ST*837*0001~\n" <>
        "SE*3*0001~\n" <>
        "GE*1*1~\n" <>
        "IEA*1*000000001~\n"

      "corrupt_data" <> _ ->
        "ISA*00*          *00*          *ZZ*CORRUPT***INVALID***DATA*~\n"

      _ ->
        "ISA*00*          *00*          *ZZ*ERROR*ZZ*ERROR*250101*1200*U*00401*000000001*0*P*:~\n"
    end

    File.write!(dest_path, content)

    %{
      filename: filename,
      type: "ERROR",
      expected_status: "error",
      expected_claims: 0,
      description: "Intentionally malformed file: #{filename}"
    }
  end

  defp modify_control_numbers(content, filename) do
    # Extract a unique number from filename for control numbers
    unique_num = filename
    |> String.replace(~r/[^\d]/, "")
    |> String.slice(0..8)
    |> String.pad_leading(9, "0")

    content
    |> String.replace(~r/\*000000001\*/, "*#{unique_num}*")
    |> String.replace(~r/BATCH123/, "BATCH#{unique_num}")
    |> String.replace(~r/CLAIM001/, "CLAIM#{unique_num}")
  end
end
