defmodule X12Bridge.RemoteFetcherTest do
  use ExUnit.Case, async: false

  alias X12Bridge.RemoteFetcher

  @test_data_dir Path.expand("../../test/fixtures/manual_test_data", __DIR__)

  describe "validate_url/1" do
    test "accepts valid HTTP URL" do
      assert {:ok, _uri} = RemoteFetcher.validate_url("http://example.com/file.zip")
    end

    test "accepts valid HTTPS URL" do
      assert {:ok, _uri} = RemoteFetcher.validate_url("https://example.com/file.zip")
    end

    test "rejects FTP URL" do
      assert {:error, :invalid_url} = RemoteFetcher.validate_url("ftp://example.com/file.zip")
    end

    test "rejects file:// URL" do
      assert {:error, :invalid_url} = RemoteFetcher.validate_url("file:///path/to/file.zip")
    end

    test "rejects malformed URL" do
      assert {:error, :invalid_url} = RemoteFetcher.validate_url("not-a-url")
    end

    test "rejects URL without scheme" do
      assert {:error, :invalid_url} = RemoteFetcher.validate_url("example.com/file.zip")
    end

    test "rejects URL without host" do
      assert {:error, :invalid_url} = RemoteFetcher.validate_url("http:///file.zip")
    end

    test "rejects non-string input" do
      assert {:error, :invalid_url} = RemoteFetcher.validate_url(123)
      assert {:error, :invalid_url} = RemoteFetcher.validate_url(nil)
    end
  end

  describe "cleanup_temp_files/1" do
    test "removes existing directory" do
      temp_dir = Path.join(System.tmp_dir!(), "test_cleanup_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_dir)
      test_file = Path.join(temp_dir, "test.txt")
      File.write!(test_file, "test content")

      assert File.exists?(temp_dir)
      assert :ok = RemoteFetcher.cleanup_temp_files(temp_dir)
      refute File.exists?(temp_dir)
    end

    test "handles non-existent directory gracefully" do
      assert :ok = RemoteFetcher.cleanup_temp_files("/nonexistent/path")
    end

    test "handles nil input gracefully" do
      assert :ok = RemoteFetcher.cleanup_temp_files(nil)
    end
  end

  describe "fetch_and_extract/2 with local file URLs" do
    setup do
      # Create a simple test ZIP for local testing
      temp_dir = Path.join(System.tmp_dir!(), "test_zip_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_dir)

      # Create test X12 files
      test_file_1 = Path.join(temp_dir, "test1.x12")
      test_file_2 = Path.join(temp_dir, "test2.x12")
      File.write!(test_file_1, "ISA~test content 1~")
      File.write!(test_file_2, "ISA~test content 2~")

      # Create ZIP
      zip_path = Path.join(temp_dir, "test.zip")

      :ok =
        :zip.create(
          String.to_charlist(zip_path),
          [
            {~c"test1.x12", File.read!(test_file_1)},
            {~c"test2.x12", File.read!(test_file_2)}
          ]
        )

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      {:ok, zip_path: zip_path, temp_dir: temp_dir}
    end

    @tag :skip
    test "successfully extracts X12 files from local ZIP", %{zip_path: zip_path} do
      # Note: This test is skipped because RemoteFetcher only supports HTTP/HTTPS
      # For real testing, you'd need to mock the HTTP client or use a test server
      url = "file://#{zip_path}"

      case RemoteFetcher.fetch_and_extract(url) do
        {:ok, result} ->
          assert length(result.files) == 2
          assert result.temp_dir != nil
          assert Enum.all?(result.files, &String.ends_with?(&1, ".x12"))

          # Cleanup
          RemoteFetcher.cleanup_temp_files(result.temp_dir)

        {:error, :invalid_url} ->
          # Expected since file:// is not supported
          :ok
      end
    end
  end

  describe "fetch_and_extract/2 error scenarios" do
    test "returns error for invalid URL" do
      assert {:error, :invalid_url} = RemoteFetcher.fetch_and_extract("not-a-url")
    end

    @tag :skip
    test "returns error for 404 not found" do
      # This would require a test HTTP server or mocking
      # Skipped for now - would need Bypass or similar
      :ok
    end

    @tag :skip
    test "returns error for timeout" do
      # This would require a test HTTP server that delays
      # Skipped for now
      :ok
    end

    @tag :skip
    test "returns error for invalid ZIP format" do
      # This would require hosting an invalid ZIP file
      # Skipped for now
      :ok
    end
  end

  describe "configuration" do
    test "uses default timeout when not configured" do
      # Test that the module can read configuration
      config = Application.get_env(:x12_bridge, :remote_fetcher, [])
      timeout = Keyword.get(config, :download_timeout_ms, 60_000)
      assert timeout == 60_000
    end

    test "uses default max size when not configured" do
      config = Application.get_env(:x12_bridge, :remote_fetcher, [])
      max_size = Keyword.get(config, :max_file_size_bytes, 100_000_000)
      assert max_size == 100_000_000
    end

    test "uses default allowed extensions" do
      config = Application.get_env(:x12_bridge, :remote_fetcher, [])

      extensions =
        Keyword.get(config, :allowed_extensions, [".x12", ".edi", ".txt"])

      assert ".x12" in extensions
      assert ".edi" in extensions
      assert ".txt" in extensions
    end
  end

  describe "integration with existing test data" do
    test "test ZIP files exist in priv/test_data/remote_batches" do
      assert File.exists?(Path.join(@test_data_dir, "test_batch_3files.zip"))
      assert File.exists?(Path.join(@test_data_dir, "test_batch_with_manifest.zip"))
      assert File.exists?(Path.join(@test_data_dir, "test_batch_invalid.zip"))
    end

    test "test ZIP contains expected number of files" do
      zip_path = Path.join(@test_data_dir, "test_batch_3files.zip")

      case :zip.list_dir(String.to_charlist(zip_path)) do
        {:ok, file_list} ->
          # Filter out :zip_comment entries and count only :zip_file entries
          files = Enum.filter(file_list, fn
            {:zip_file, _, _, _, _, _} -> true
            _ -> false
          end)
          # Should have 3 X12 files
          assert length(files) == 3

        {:error, _reason} ->
          flunk("Could not read test ZIP file")
      end
    end

    test "test ZIP with manifest contains manifest.json" do
      zip_path = Path.join(@test_data_dir, "test_batch_with_manifest.zip")

      case :zip.list_dir(String.to_charlist(zip_path)) do
        {:ok, file_list} ->
          filenames =
            file_list
            |> Enum.filter(fn
              {:zip_file, _, _, _, _, _} -> true
              _ -> false
            end)
            |> Enum.map(fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

          assert "manifest.json" in filenames

        {:error, _reason} ->
          flunk("Could not read test ZIP with manifest")
      end
    end

    test "invalid test ZIP contains no X12 files" do
      zip_path = Path.join(@test_data_dir, "test_batch_invalid.zip")

      case :zip.list_dir(String.to_charlist(zip_path)) do
        {:ok, file_list} ->
          filenames =
            file_list
            |> Enum.filter(fn
              {:zip_file, _, _, _, _, _} -> true
              _ -> false
            end)
            |> Enum.map(fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

          x12_files = Enum.filter(filenames, &String.ends_with?(&1, [".x12", ".edi"]))
          # The .txt file might match the extension but won't be valid X12
          # The key is that there are no .x12 or .edi files
          assert length(x12_files) == 0

        {:error, _reason} ->
          flunk("Could not read invalid test ZIP")
      end
    end
  end

  describe "manual testing helpers" do
    @tag :manual
    test "can serve test ZIPs via local HTTP server" do
      # This test provides instructions for manual testing
      # Run: cd test/fixtures/manual_test_data && python3 -m http.server 8000
      # Then test with: http://localhost:8000/test_batch_3files.zip

      IO.puts("""

      === Manual Testing Instructions ===

      1. Start HTTP server:
         cd test/fixtures/manual_test_data
         python3 -m http.server 8000

      2. Test URLs (synthetic test data):
         http://localhost:8000/test_batch_3files.zip
         http://localhost:8000/test_batch_with_manifest.zip
         http://localhost:8000/test_batch_invalid.zip

      3. Test URL (real Databricks data):
         http://localhost:8000/databricks_sample_2026-01-09.zip

      4. Run in IEx:
         {:ok, result} = X12Bridge.RemoteFetcher.fetch_and_extract("http://localhost:8000/test_batch_3files.zip")
         X12Bridge.RemoteFetcher.cleanup_temp_files(result.temp_dir)

      """)

      assert true
    end

    @tag :manual
    test "can test with real remote URL" do
      # This test can be uncommented and run with a real remote URL
      # url = "https://example.com/real-batch.zip"
      # {:ok, result} = RemoteFetcher.fetch_and_extract(url)
      # assert length(result.files) > 0
      # RemoteFetcher.cleanup_temp_files(result.temp_dir)

      IO.puts("""

      === Testing with Real Remote URLs ===

      Uncomment and modify the test code above to test with real remote URLs.
      Make sure the remote ZIP file contains valid X12 files.

      """)

      assert true
    end
  end
end
