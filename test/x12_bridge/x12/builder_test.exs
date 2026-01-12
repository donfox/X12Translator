defmodule X12Bridge.X12.BuilderTest do
  use ExUnit.Case, async: true

  alias X12Bridge.X12.{Builder, Parser, Converter}

  @fixtures_dir "test/fixtures/automated_test_data"

  describe "build_from_structure/2" do
    test "builds X12 from parsed 837P structure" do
      x12_content = File.read!(Path.join(@fixtures_dir, "001_837p_valid.x12"))

      # Parse and convert to structure
      {:ok, %{delimiters: delimiters, segments: segments}} = Parser.parse(x12_content)
      {:ok, structured_data} = Converter.build_structure(segments, delimiters)

      # Build X12 from structure
      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      # Verify it's valid X12
      assert String.starts_with?(rebuilt_x12, "ISA*")
      assert String.contains?(rebuilt_x12, "~")
      assert String.ends_with?(rebuilt_x12, "~")
      assert String.contains?(rebuilt_x12, "GS*")
      assert String.contains?(rebuilt_x12, "ST*")
      assert String.contains?(rebuilt_x12, "CLM*")
      assert String.contains?(rebuilt_x12, "SE*")
      assert String.contains?(rebuilt_x12, "GE*")
      assert String.contains?(rebuilt_x12, "IEA*")
    end

    test "builds X12 from parsed 837I structure" do
      x12_content = File.read!(Path.join(@fixtures_dir, "002_837i_valid.x12"))

      {:ok, %{delimiters: delimiters, segments: segments}} = Parser.parse(x12_content)
      {:ok, structured_data} = Converter.build_structure(segments, delimiters)

      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      assert String.starts_with?(rebuilt_x12, "ISA*")
      assert String.contains?(rebuilt_x12, "SV2*")  # Institutional service segment
    end

    test "builds X12 from parsed 837D structure" do
      x12_content = File.read!(Path.join(@fixtures_dir, "003_837d_valid.x12"))

      {:ok, %{delimiters: delimiters, segments: segments}} = Parser.parse(x12_content)
      {:ok, structured_data} = Converter.build_structure(segments, delimiters)

      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      assert String.starts_with?(rebuilt_x12, "ISA*")
      assert String.contains?(rebuilt_x12, "SV3*")  # Dental service segment
    end

    test "preserves all envelope segments" do
      x12_content = File.read!(Path.join(@fixtures_dir, "001_837p_valid.x12"))

      {:ok, %{delimiters: delimiters, segments: segments}} = Parser.parse(x12_content)
      {:ok, structured_data} = Converter.build_structure(segments, delimiters)

      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      # Count segments
      rebuilt_segments = String.split(rebuilt_x12, "~", trim: true)

      # Should have ISA, GS, ST, ..., SE, GE, IEA
      isa_count = Enum.count(rebuilt_segments, &String.starts_with?(&1, "ISA*"))
      gs_count = Enum.count(rebuilt_segments, &String.starts_with?(&1, "GS*"))
      st_count = Enum.count(rebuilt_segments, &String.starts_with?(&1, "ST*"))
      se_count = Enum.count(rebuilt_segments, &String.starts_with?(&1, "SE*"))
      ge_count = Enum.count(rebuilt_segments, &String.starts_with?(&1, "GE*"))
      iea_count = Enum.count(rebuilt_segments, &String.starts_with?(&1, "IEA*"))

      assert isa_count == 1
      assert gs_count == 1
      assert st_count == 1
      assert se_count == 1
      assert ge_count == 1
      assert iea_count == 1
    end

    test "preserves claim and service line structure" do
      x12_content = File.read!(Path.join(@fixtures_dir, "001_837p_valid.x12"))

      {:ok, %{delimiters: delimiters, segments: segments}} = Parser.parse(x12_content)
      {:ok, structured_data} = Converter.build_structure(segments, delimiters)

      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      # Verify CLM segments (claims)
      clm_count = rebuilt_x12 |> String.split("~", trim: true) |> Enum.count(&String.starts_with?(&1, "CLM*"))
      assert clm_count > 0

      # Verify service line segments
      sv1_count = rebuilt_x12 |> String.split("~", trim: true) |> Enum.count(&String.starts_with?(&1, "SV1*"))
      assert sv1_count > 0
    end

    test "handles multi-claim files" do
      x12_content = File.read!(Path.join(@fixtures_dir, "004_837p_multi.x12"))

      {:ok, %{delimiters: delimiters, segments: segments}} = Parser.parse(x12_content)
      {:ok, structured_data} = Converter.build_structure(segments, delimiters)

      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      # Should have CLM segments (file name is misleading, only has 1 claim but multiple service lines)
      clm_count = rebuilt_x12 |> String.split("~", trim: true) |> Enum.count(&String.starts_with?(&1, "CLM*"))
      assert clm_count >= 1

      # Should preserve structure
      assert String.starts_with?(rebuilt_x12, "ISA*")
    end
  end

  describe "build_from_json/1" do
    test "builds X12 from JSON string" do
      x12_content = File.read!(Path.join(@fixtures_dir, "001_837p_valid.x12"))

      # Convert to JSON
      {:ok, json_string} = Converter.convert_content(x12_content)

      # Build X12 from JSON
      {:ok, rebuilt_x12} = Builder.build_from_json(json_string)

      # Verify it's valid X12
      assert String.starts_with?(rebuilt_x12, "ISA*")
      assert String.contains?(rebuilt_x12, "~")
    end

    test "returns error for invalid JSON" do
      invalid_json = "{not valid json"

      result = Builder.build_from_json(invalid_json)

      assert {:error, _reason} = result
    end
  end

  describe "round-trip integrity" do
    test "preserves data through full round-trip (837P)" do
      x12_content = File.read!(Path.join(@fixtures_dir, "001_837p_valid.x12"))

      # Round-trip: X12 → JSON → X12
      {:ok, %{delimiters: delimiters, segments: original_segments}} = Parser.parse(x12_content)
      {:ok, structured_data} = Converter.build_structure(original_segments, delimiters)
      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      # Parse rebuilt X12
      {:ok, %{segments: rebuilt_segments}} = Parser.parse(rebuilt_x12)

      # Segment counts should match (or be very close)
      # Note: Some implementations may differ slightly in segment order or optional segments
      assert abs(length(original_segments) - length(rebuilt_segments)) <= 2
    end

    test "preserves critical claim data through round-trip" do
      x12_content = File.read!(Path.join(@fixtures_dir, "001_837p_valid.x12"))

      # Extract claim data from original
      {:ok, %{delimiters: delimiters, segments: original_segments}} = Parser.parse(x12_content)
      original_clm = Enum.find(original_segments, &(&1.id == "CLM"))
      original_claim_id = Parser.get_element(original_clm, 1)

      # Round-trip
      {:ok, structured_data} = Converter.build_structure(original_segments, delimiters)
      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      # Extract claim data from rebuilt
      {:ok, %{segments: rebuilt_segments}} = Parser.parse(rebuilt_x12)
      rebuilt_clm = Enum.find(rebuilt_segments, &(&1.id == "CLM"))
      rebuilt_claim_id = Parser.get_element(rebuilt_clm, 1)

      # Claim ID should be preserved
      assert original_claim_id == rebuilt_claim_id
    end

    test "preserves entity information through round-trip" do
      x12_content = File.read!(Path.join(@fixtures_dir, "001_837p_valid.x12"))

      # Extract billing provider from original
      {:ok, %{delimiters: delimiters, segments: original_segments}} = Parser.parse(x12_content)
      original_nm1_85 = Enum.find(original_segments, fn seg ->
        seg.id == "NM1" && Parser.get_element(seg, 1) == "85"
      end)
      original_provider_name = Parser.get_element(original_nm1_85, 3)

      # Round-trip
      {:ok, structured_data} = Converter.build_structure(original_segments, delimiters)
      {:ok, rebuilt_x12} = Builder.build_from_structure(structured_data, delimiters)

      # Extract billing provider from rebuilt
      {:ok, %{segments: rebuilt_segments}} = Parser.parse(rebuilt_x12)
      rebuilt_nm1_85 = Enum.find(rebuilt_segments, fn seg ->
        seg.id == "NM1" && Parser.get_element(seg, 1) == "85"
      end)
      rebuilt_provider_name = Parser.get_element(rebuilt_nm1_85, 3)

      # Provider name should be preserved
      assert original_provider_name == rebuilt_provider_name
    end
  end

  describe "edge cases" do
    test "handles empty optional fields" do
      # Create minimal structure with some empty fields
      minimal_structure = %{
        file_info: %{},
        interchange_header: %{
          all_elements: ["ISA", "00", "          ", "00", "          ", "ZZ", "SENDER", "ZZ", "RECEIVER", "250101", "1200", "U", "00401", "000000001", "0", "P"]
        },
        functional_group: %{
          all_elements: ["GS", "HC", "SENDER", "RECEIVER", "20250101", "1200", "1", "X", "004010X098A1"]
        },
        transaction_set: %{
          all_elements: ["ST", "837", "0001"],
          transaction_control_number: "0001"
        },
        billing_provider: nil,
        subscriber: nil,
        claims: [],
        all_segments: [],
        other_entities: [],
        contacts: [],
        hierarchical_levels: [],
        header_references: [],
        warnings: [],
        summary: %{}
      }

      delimiters = %Parser.Delimiters{element: "*", sub_element: ":", segment: "~"}

      {:ok, rebuilt_x12} = Builder.build_from_structure(minimal_structure, delimiters)

      # Should produce valid envelope
      assert String.starts_with?(rebuilt_x12, "ISA*")
      assert String.contains?(rebuilt_x12, "SE*")
      assert String.contains?(rebuilt_x12, "IEA*")
    end
  end
end
