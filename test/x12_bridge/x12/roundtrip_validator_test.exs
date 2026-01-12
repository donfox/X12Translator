defmodule X12Bridge.X12.RoundtripValidatorTest do
  use ExUnit.Case, async: true

  alias X12Bridge.X12.RoundtripValidator

  @fixtures_dir "test/fixtures/automated_test_data"

  describe "validate/1" do
    test "validates successful round-trip for 837P file" do
      x12_content = File.read!(Path.join(@fixtures_dir, "001_837p_valid.x12"))

      result = RoundtripValidator.validate(x12_content)

      assert result.valid? == true
      assert result.differences == []
      assert result.original_segments > 0
      assert result.rebuilt_segments == result.original_segments
      assert result.error_message == nil
    end

    test "validates successful round-trip for 837I file" do
      x12_content = File.read!(Path.join(@fixtures_dir, "002_837i_valid.x12"))

      result = RoundtripValidator.validate(x12_content)

      assert result.valid? == true
      assert result.differences == []
      assert result.original_segments > 0
      assert result.rebuilt_segments == result.original_segments
      assert result.error_message == nil
    end

    test "validates successful round-trip for 837D file" do
      x12_content = File.read!(Path.join(@fixtures_dir, "003_837d_valid.x12"))

      result = RoundtripValidator.validate(x12_content)

      assert result.valid? == true
      assert result.differences == []
      assert result.original_segments > 0
      assert result.rebuilt_segments == result.original_segments
      assert result.error_message == nil
    end

    test "validates successful round-trip for multi-claim file" do
      x12_content = File.read!(Path.join(@fixtures_dir, "004_837p_multi.x12"))

      result = RoundtripValidator.validate(x12_content)

      assert result.valid? == true
      assert result.differences == []
      assert result.original_segments > 0
      assert result.rebuilt_segments == result.original_segments
      assert result.error_message == nil
    end

    test "handles invalid X12 file gracefully" do
      invalid_x12 = "NOT A VALID X12 FILE"

      result = RoundtripValidator.validate(invalid_x12)

      assert result.valid? == false
      assert result.error_message != nil
      assert String.contains?(result.error_message, "Failed to parse")
    end

    test "handles empty content" do
      result = RoundtripValidator.validate("")

      assert result.valid? == false
      assert result.error_message != nil
    end
  end

  describe "normalize_x12/2" do
    test "removes line breaks and extra whitespace" do
      x12_with_whitespace = """
      ISA*00*          *00*          *ZZ*SUBMITTER123   *ZZ*RECEIVER456    *250101*1200*U*00401*000183712*0*P*:~
      GS*HC*SUBMITTER123*RECEIVER456*20250101*1200*1*X*004010X098A1~
      ST*837*0001~
      """

      delimiters = %X12Bridge.X12.Parser.Delimiters{
        element: "*",
        sub_element: ":",
        segment: "~"
      }

      normalized = RoundtripValidator.normalize_x12(x12_with_whitespace, delimiters)

      refute String.contains?(normalized, "\n")
      refute String.contains?(normalized, "\r")
      assert String.contains?(normalized, "ISA*")
      assert String.contains?(normalized, "~GS*")
    end

    test "preserves segment data and delimiters" do
      original = "ISA*00*test*00*data~GS*HC*sender~ST*837*0001~"

      delimiters = %X12Bridge.X12.Parser.Delimiters{
        element: "*",
        sub_element: ":",
        segment: "~"
      }

      normalized = RoundtripValidator.normalize_x12(original, delimiters)

      assert normalized == original
    end
  end

  describe "split_segments/2" do
    test "splits X12 content into segments" do
      x12_content = "ISA*00*test~GS*HC*sender~ST*837*0001~"

      segments = RoundtripValidator.split_segments(x12_content, "~")

      assert length(segments) == 3
      assert Enum.at(segments, 0) == "ISA*00*test"
      assert Enum.at(segments, 1) == "GS*HC*sender"
      assert Enum.at(segments, 2) == "ST*837*0001"
    end

    test "filters out empty segments" do
      x12_content = "ISA*test~GS*test~~ST*test~"

      segments = RoundtripValidator.split_segments(x12_content, "~")

      assert length(segments) == 3
      refute Enum.any?(segments, &(&1 == ""))
    end
  end

  describe "format_result/1" do
    test "formats successful validation result" do
      result = %RoundtripValidator.ValidationResult{
        valid?: true,
        differences: [],
        original_segments: 10,
        rebuilt_segments: 10,
        error_message: nil
      }

      formatted = RoundtripValidator.format_result(result)

      assert String.contains?(formatted, "✓")
      assert String.contains?(formatted, "passed")
    end

    test "formats failed validation with error message" do
      result = %RoundtripValidator.ValidationResult{
        valid?: false,
        differences: nil,
        original_segments: 0,
        rebuilt_segments: 0,
        error_message: "Parsing failed"
      }

      formatted = RoundtripValidator.format_result(result)

      assert String.contains?(formatted, "✗")
      assert String.contains?(formatted, "failed")
      assert String.contains?(formatted, "Parsing failed")
    end

    test "formats failed validation with differences" do
      result = %RoundtripValidator.ValidationResult{
        valid?: false,
        differences: [
          %{
            type: :segment_mismatch,
            segment_number: 5,
            original: "CLM*CLAIM123*500.00",
            rebuilt: "CLM*CLAIM123*600.00",
            message: "Segment 5 differs"
          }
        ],
        original_segments: 10,
        rebuilt_segments: 10,
        error_message: nil
      }

      formatted = RoundtripValidator.format_result(result)

      assert String.contains?(formatted, "✗")
      assert String.contains?(formatted, "1 difference")
      assert String.contains?(formatted, "Segment 5")
    end
  end

  describe "get_summary/1" do
    test "returns summary statistics" do
      result = %RoundtripValidator.ValidationResult{
        valid?: true,
        differences: [],
        original_segments: 38,
        rebuilt_segments: 38,
        error_message: nil
      }

      summary = RoundtripValidator.get_summary(result)

      assert summary.valid == true
      assert summary.original_segments == 38
      assert summary.rebuilt_segments == 38
      assert summary.differences_count == 0
      assert summary.error_message == nil
    end

    test "returns summary with differences" do
      result = %RoundtripValidator.ValidationResult{
        valid?: false,
        differences: [
          %{type: :segment_mismatch},
          %{type: :segment_mismatch}
        ],
        original_segments: 10,
        rebuilt_segments: 10,
        error_message: nil
      }

      summary = RoundtripValidator.get_summary(result)

      assert summary.valid == false
      assert summary.differences_count == 2
    end
  end

  describe "compare_x12/3" do
    test "detects segment count mismatch" do
      original = "ISA*test~GS*test~ST*test~"
      rebuilt = "ISA*test~GS*test~"

      delimiters = %X12Bridge.X12.Parser.Delimiters{
        element: "*",
        sub_element: ":",
        segment: "~"
      }

      result = RoundtripValidator.compare_x12(original, rebuilt, delimiters)

      assert result.valid? == false
      assert result.original_segments == 3
      assert result.rebuilt_segments == 2
      assert result.error_message == "Segment count mismatch"
    end

    test "detects segment content differences" do
      original = "ISA*00*test~GS*HC*sender~"
      rebuilt = "ISA*00*different~GS*HC*sender~"

      delimiters = %X12Bridge.X12.Parser.Delimiters{
        element: "*",
        sub_element: ":",
        segment: "~"
      }

      result = RoundtripValidator.compare_x12(original, rebuilt, delimiters)

      assert result.valid? == false
      assert length(result.differences) == 1
      assert Enum.at(result.differences, 0).type == :segment_mismatch
      assert Enum.at(result.differences, 0).segment_number == 1
    end

    test "passes for identical content" do
      x12_content = "ISA*00*test~GS*HC*sender~ST*837*0001~"

      delimiters = %X12Bridge.X12.Parser.Delimiters{
        element: "*",
        sub_element: ":",
        segment: "~"
      }

      result = RoundtripValidator.compare_x12(x12_content, x12_content, delimiters)

      assert result.valid? == true
      assert result.differences == []
    end

    test "passes for content with normalized whitespace differences" do
      original = "ISA*00*test~GS*HC*sender~"
      rebuilt = "ISA*00*test~\nGS*HC*sender~\n"

      delimiters = %X12Bridge.X12.Parser.Delimiters{
        element: "*",
        sub_element: ":",
        segment: "~"
      }

      result = RoundtripValidator.compare_x12(original, rebuilt, delimiters)

      assert result.valid? == true
      assert result.differences == []
    end
  end
end
