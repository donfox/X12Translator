defmodule X12Translator.X12.SegmentMapperTest do
  use ExUnit.Case, async: true

  alias X12Translator.X12.{Converter, SegmentMapper}

  @fixtures_path "test/fixtures/automated_test_data"

  # Helper: load X12 fixture, convert to flat JSON, decode, and map to semantic
  defp load_and_map(filename) do
    content = File.read!(Path.join(@fixtures_path, filename))
    {:ok, json} = Converter.convert_content(content)
    {:ok, decoded} = Jason.decode(json)
    SegmentMapper.map_segments(decoded["all_segments"])
  end

  # Helper: load and map, returning just the result (bang version)
  defp load_and_map!(filename) do
    {:ok, result} = load_and_map(filename)
    result
  end

  # ---------------------------------------------------------------------------
  # 837P Professional Claims
  # ---------------------------------------------------------------------------

  describe "837P mapping" do
    setup do
      {:ok, result: load_and_map!("001_837p_valid.x12")}
    end

    test "detects transaction type", %{result: result} do
      assert result.transaction_type == "837P"
    end

    test "extracts interchange", %{result: result} do
      assert result.interchange.control_number == "000183712"
      assert result.interchange.sender_id == "SUBMITTER123"
      assert result.interchange.receiver_id == "RECEIVER456"
      assert result.interchange.usage_indicator == "P"
    end

    test "extracts functional group", %{result: result} do
      assert result.functional_group.functional_id_code == "HC"
      assert result.functional_group.sender_code == "SUBMITTER123"
      assert String.contains?(result.functional_group.version, "X098")
    end

    test "extracts submitter", %{result: result} do
      assert result.submitter.name == "ACME MEDICAL BILLING"
      assert result.submitter.id == "SUB123"
      assert result.submitter.contact_name == "JOHN DOE"
      assert result.submitter.contact_phone == "5555551234"
    end

    test "extracts receiver", %{result: result} do
      assert result.receiver.name == "BLUE CROSS BLUE SHIELD"
      assert result.receiver.id == "REC456"
    end

    test "extracts billing provider", %{result: result} do
      bp = result.billing_provider
      assert bp.name == "CITY HOSPITAL CLINIC"
      assert bp.npi == "1234567890"
      assert bp.taxonomy_code == "207Q00000X"
      assert bp.tax_id == "123456789"
      assert bp.address.street == "123 MAIN STREET"
      assert bp.address.city == "ANYTOWN"
      assert bp.address.state == "CA"
      assert bp.address.zip == "90210"
    end

    test "extracts claim basics", %{result: result} do
      claim = result.claim
      assert claim.claim_id == "CLAIM000183712"
      assert claim.total_charge_amount == "500.00"
      assert claim.place_of_service == "11"
      assert claim.facility_type == "B"
      assert claim.frequency_code == "1"
      assert claim.claim_filing_indicator == "CI"
    end

    test "extracts subscriber", %{result: result} do
      sub = result.claim.subscriber
      assert sub.last_name == "SMITH"
      assert sub.first_name == "JANE"
      assert sub.middle_name == "M"
      assert sub.member_id == "MEMBER123456"
      assert sub.payer_responsibility == "P"
      assert sub.relationship_code == "18"
      assert sub.group_number == "GROUP123"
      assert sub.date_of_birth == "19800515"
      assert sub.gender == "F"
      assert sub.address.street == "456 ELM STREET"
    end

    test "extracts payer", %{result: result} do
      assert result.claim.payer.name == "BLUE CROSS BLUE SHIELD"
      assert result.claim.payer.payer_id == "54321"
    end

    test "extracts dates", %{result: result} do
      assert result.claim.dates.onset_date == "20241215"
      assert result.claim.dates.service_date == "20241215"
    end

    test "extracts diagnosis codes", %{result: result} do
      dx = result.claim.diagnosis_codes
      assert length(dx) == 2
      assert Enum.at(dx, 0) == %{qualifier: "ABK", code: "J189"}
      assert Enum.at(dx, 1) == %{qualifier: "ABK", code: "E119"}
    end

    test "extracts rendering provider", %{result: result} do
      rp = result.claim.rendering_provider
      assert rp.last_name == "JOHNSON"
      assert rp.first_name == "ROBERT"
      assert rp.npi == "9876543210"
      assert rp.taxonomy_code == "207Q00000X"
    end

    test "attending provider is nil for 837P", %{result: result} do
      assert result.claim.attending_provider == nil
    end

    test "institutional claim is nil for 837P", %{result: result} do
      assert result.claim.institutional_claim == nil
    end

    test "extracts 3 service lines", %{result: result} do
      lines = result.claim.service_lines
      assert length(lines) == 3

      line1 = Enum.at(lines, 0)
      assert line1.line_number == 1
      assert line1.procedure_qualifier == "HC"
      assert line1.procedure_code == "99213"
      assert line1.charge_amount == "150.00"
      assert line1.unit_type == "UN"
      assert line1.units == "1"
      assert line1.service_date == "20241215"
      assert line1.revenue_code == nil
      assert line1.tooth_info == nil

      line2 = Enum.at(lines, 1)
      assert line2.procedure_code == "80053"
      assert line2.charge_amount == "200.00"

      line3 = Enum.at(lines, 2)
      assert line3.procedure_code == "93000"
      assert line3.charge_amount == "150.00"
    end
  end

  # ---------------------------------------------------------------------------
  # 837I Institutional Claims
  # ---------------------------------------------------------------------------

  describe "837I mapping" do
    setup do
      {:ok, result: load_and_map!("002_837i_valid.x12")}
    end

    test "detects transaction type", %{result: result} do
      assert result.transaction_type == "837I"
    end

    test "extracts institutional claim info (CL1)", %{result: result} do
      ic = result.claim.institutional_claim
      assert ic != nil
      assert ic.admission_type == "1"
      assert ic.admission_source == "1"
      assert ic.patient_status == "01"
    end

    test "extracts attending provider", %{result: result} do
      ap = result.claim.attending_provider
      assert ap != nil
      assert ap.last_name == "WILLIAMS"
      assert ap.first_name == "SARAH"
      assert ap.npi == "1122334455"
      assert ap.taxonomy_code == "208600000X"
    end

    test "extracts SV2 service lines with revenue codes", %{result: result} do
      lines = result.claim.service_lines
      assert length(lines) == 4

      line1 = Enum.at(lines, 0)
      assert line1.revenue_code == "0450"
      assert line1.procedure_qualifier == "HC"
      assert line1.procedure_code == "4567"
      assert line1.charge_amount == "350.00"
      assert line1.units == "3"
    end

    test "extracts diagnosis codes including procedure codes", %{result: result} do
      dx = result.claim.diagnosis_codes
      # HI*ABK:I2510*ABK:E1169 + HI*BK:3051
      assert length(dx) == 3
      assert Enum.at(dx, 0) == %{qualifier: "ABK", code: "I2510"}
      assert Enum.at(dx, 1) == %{qualifier: "ABK", code: "E1169"}
      assert Enum.at(dx, 2) == %{qualifier: "BK", code: "3051"}
    end
  end

  # ---------------------------------------------------------------------------
  # 837D Dental Claims
  # ---------------------------------------------------------------------------

  describe "837D mapping" do
    setup do
      {:ok, result: load_and_map!("003_837d_valid.x12")}
    end

    test "detects transaction type", %{result: result} do
      assert result.transaction_type == "837D"
    end

    test "extracts SV3 service lines", %{result: result} do
      lines = result.claim.service_lines
      assert length(lines) == 3

      line1 = Enum.at(lines, 0)
      assert line1.procedure_qualifier == "AD"
      assert line1.procedure_code == "D1110"
      assert line1.charge_amount == "75.00"
    end

    test "extracts tooth info on service lines", %{result: result} do
      lines = result.claim.service_lines

      # Line 1: TOO*JP*8
      tooth1 = Enum.at(lines, 0).tooth_info
      assert tooth1 != nil
      assert tooth1.tooth_code_qualifier == "JP"
      assert tooth1.tooth_number == "8"

      # Line 2: TOO*JP*19:MO
      tooth2 = Enum.at(lines, 1).tooth_info
      assert tooth2 != nil
      assert tooth2.tooth_number == "19"
      assert tooth2.tooth_surface == "MO"

      # Line 3: no TOO segment
      assert Enum.at(lines, 2).tooth_info == nil
    end

    test "attending provider is nil for 837D", %{result: result} do
      assert result.claim.attending_provider == nil
    end

    test "institutional claim is nil for 837D", %{result: result} do
      assert result.claim.institutional_claim == nil
    end
  end

  # ---------------------------------------------------------------------------
  # map_from_json convenience
  # ---------------------------------------------------------------------------

  describe "map_from_json/1" do
    test "maps from JSON string" do
      content = File.read!(Path.join(@fixtures_path, "001_837p_valid.x12"))
      {:ok, json} = Converter.convert_content(content)
      {:ok, result} = SegmentMapper.map_from_json(json)
      assert result.transaction_type == "837P"
      assert result.claim.claim_id == "CLAIM000183712"
    end

    test "returns error for missing all_segments" do
      assert {:error, "JSON missing all_segments key"} = SegmentMapper.map_from_json("{}")
    end

    test "returns error for invalid JSON" do
      assert {:error, "JSON decode failed:" <> _} = SegmentMapper.map_from_json("not json")
    end
  end

  # ---------------------------------------------------------------------------
  # Error cases
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "returns error for empty segment list" do
      assert {:error, "No segments provided"} = SegmentMapper.map_segments([])
    end

    test "handles segments with no CLM gracefully" do
      # Just an ISA segment, no claim
      segments = [%{"segment_id" => "ISA", "elements" => ["ISA", "00"], "raw" => "ISA*00", "line_number" => 1}]
      {:ok, result} = SegmentMapper.map_segments(segments)
      assert result.claim == nil
    end
  end
end
