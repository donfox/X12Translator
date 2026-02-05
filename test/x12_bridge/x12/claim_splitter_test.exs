defmodule X12Bridge.X12.ClaimSplitterTest do
  use ExUnit.Case, async: true

  alias X12Bridge.X12.ClaimSplitter
  alias X12Bridge.X12.Parser

  @fixtures_path "test/fixtures/batch_input"

  describe "split_claims/1 with multi-claim professional file" do
    setup do
      content = File.read!(Path.join(@fixtures_path, "multi_claim_837p.x12"))
      {:ok, content: content}
    end

    test "splits into individual claims", %{content: content} do
      assert {:ok, claims} = ClaimSplitter.split_claims(content)
      assert length(claims) == 3
    end

    test "extracts correct claim IDs", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)
      claim_ids = Enum.map(claims, & &1.claim_id)

      assert "CLM-900001" in claim_ids
      assert "CLM-900002" in claim_ids
      assert "CLM-900003" in claim_ids
    end

    test "each claim has valid JSON output", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)

      for claim <- claims do
        assert {:ok, _decoded} = Jason.decode(claim.json)
      end
    end

    test "each claim has segment count", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)

      for claim <- claims do
        assert is_integer(claim.segment_count)
        assert claim.segment_count > 0
      end
    end
  end

  describe "split_claims/1 with mixed claim types (837P, 837I, 837D)" do
    setup do
      content = File.read!(Path.join(@fixtures_path, "multi_claim_mixed_types.x12"))
      {:ok, content: content}
    end

    test "splits mixed claim types into individual claims", %{content: content} do
      assert {:ok, claims} = ClaimSplitter.split_claims(content)
      assert length(claims) == 3
    end

    test "extracts correct claim IDs for mixed types", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)
      claim_ids = Enum.map(claims, & &1.claim_id)

      assert "CLM-MIX-P001" in claim_ids
      assert "CLM-MIX-I001" in claim_ids
      assert "CLM-MIX-D001" in claim_ids
    end

    test "each mixed claim produces valid JSON", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)

      for claim <- claims do
        assert {:ok, decoded} = Jason.decode(claim.json)
        assert Map.has_key?(decoded, "all_segments")
      end
    end

    test "professional claim contains SV1 segments", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)
      p_claim = Enum.find(claims, &(&1.claim_id == "CLM-MIX-P001"))

      {:ok, decoded} = Jason.decode(p_claim.json)
      segments = decoded["all_segments"]
      segment_ids = Enum.map(segments, & &1["segment_id"])

      assert "SV1" in segment_ids
      refute "SV2" in segment_ids
      refute "SV3" in segment_ids
    end

    test "institutional claim contains SV2 segments and CL1", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)
      i_claim = Enum.find(claims, &(&1.claim_id == "CLM-MIX-I001"))

      {:ok, decoded} = Jason.decode(i_claim.json)
      segments = decoded["all_segments"]
      segment_ids = Enum.map(segments, & &1["segment_id"])

      assert "SV2" in segment_ids
      assert "CL1" in segment_ids
      refute "SV1" in segment_ids
      refute "SV3" in segment_ids
    end

    test "dental claim contains SV3 and TOO segments", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)
      d_claim = Enum.find(claims, &(&1.claim_id == "CLM-MIX-D001"))

      {:ok, decoded} = Jason.decode(d_claim.json)
      segments = decoded["all_segments"]
      segment_ids = Enum.map(segments, & &1["segment_id"])

      assert "SV3" in segment_ids
      assert "TOO" in segment_ids
      refute "SV1" in segment_ids
      refute "SV2" in segment_ids
    end
  end

  describe "split_claims/1 with faulty claims" do
    setup do
      content = File.read!(Path.join(@fixtures_path, "multi_claim_with_faults.x12"))
      {:ok, content: content}
    end

    test "splits file with faulty claims", %{content: content} do
      assert {:ok, claims} = ClaimSplitter.split_claims(content)
      # Should return all 5 claims (splitter doesn't validate amounts)
      # 3 valid + 2 faulty = 5 claims
      assert length(claims) == 5
    end

    test "extracts all claim IDs including faulty ones", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)
      claim_ids = Enum.map(claims, & &1.claim_id)

      # Valid claims
      assert "CLM-VALID-001" in claim_ids
      assert "CLM-VALID-002" in claim_ids
      assert "CLM-VALID-003" in claim_ids

      # Faulty claims (splitter still extracts them)
      assert "CLM-FAULT-001" in claim_ids
      assert "CLM-FAULT-002" in claim_ids
    end

    test "faulty claims have JSON with invalid amounts preserved", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)

      fault_001 = Enum.find(claims, &(&1.claim_id == "CLM-FAULT-001"))
      {:ok, decoded} = Jason.decode(fault_001.json)

      # Find the CLM segment
      clm_seg = Enum.find(decoded["all_segments"], &(&1["segment_id"] == "CLM"))
      # Amount is in element position 2 (index 2 in elements array)
      assert Enum.at(clm_seg["elements"], 2) == "INVALID"
    end

    test "negative amount claim is still parsed", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims(content)

      fault_002 = Enum.find(claims, &(&1.claim_id == "CLM-FAULT-002"))
      {:ok, decoded} = Jason.decode(fault_002.json)

      clm_seg = Enum.find(decoded["all_segments"], &(&1["segment_id"] == "CLM"))
      assert Enum.at(clm_seg["elements"], 2) == "-500.00"
    end
  end

  describe "split_claims_to_x12/1 with mixed claim types" do
    setup do
      content = File.read!(Path.join(@fixtures_path, "multi_claim_mixed_types.x12"))
      {:ok, content: content}
    end

    test "produces standalone X12 files for each claim", %{content: content} do
      assert {:ok, claims} = ClaimSplitter.split_claims_to_x12(content)
      assert length(claims) == 3

      for claim <- claims do
        assert Map.has_key?(claim, :claim_id)
        assert Map.has_key?(claim, :x12_content)
        assert String.starts_with?(claim.x12_content, "ISA*")
      end
    end

    test "each split X12 is parseable", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims_to_x12(content)

      for claim <- claims do
        assert {:ok, %{segments: segments}} = Parser.parse(claim.x12_content)
        assert length(segments) > 0

        # Verify envelope segments present
        segment_ids = Enum.map(segments, & &1.id)
        assert "ISA" in segment_ids
        assert "GS" in segment_ids
        assert "ST" in segment_ids
        assert "SE" in segment_ids
        assert "GE" in segment_ids
        assert "IEA" in segment_ids
      end
    end

    test "each split X12 has exactly one CLM segment", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims_to_x12(content)

      for claim <- claims do
        {:ok, %{segments: segments}} = Parser.parse(claim.x12_content)
        clm_count = Enum.count(segments, &(&1.id == "CLM"))
        assert clm_count == 1
      end
    end

    test "split X12 has correct SE segment count", %{content: content} do
      {:ok, claims} = ClaimSplitter.split_claims_to_x12(content)

      for claim <- claims do
        {:ok, %{segments: segments}} = Parser.parse(claim.x12_content)

        se_seg = Enum.find(segments, &(&1.id == "SE"))
        st_idx = Enum.find_index(segments, &(&1.id == "ST"))
        se_idx = Enum.find_index(segments, &(&1.id == "SE"))

        expected_count = se_idx - st_idx + 1
        actual_count = String.to_integer(Parser.get_element(se_seg, 1))

        assert actual_count == expected_count
      end
    end
  end

  describe "split_claims/1 with single claim file" do
    test "returns nil for single-claim file" do
      content = File.read!("test/fixtures/automated_test_data/001_837p_valid.x12")
      assert {:ok, nil} = ClaimSplitter.split_claims(content)
    end
  end

  describe "split_claims/1 error handling" do
    test "returns error for invalid X12 content" do
      assert {:error, _reason} = ClaimSplitter.split_claims("not valid x12")
    end

    test "returns error for empty content" do
      assert {:error, _reason} = ClaimSplitter.split_claims("")
    end
  end

  describe "partition_segments/1" do
    test "correctly partitions multi-claim file", %{} do
      content = File.read!(Path.join(@fixtures_path, "multi_claim_837p.x12"))
      {:ok, %{segments: segments}} = Parser.parse(content)

      {shared_header, claim_blocks, trailers} = ClaimSplitter.partition_segments(segments)

      # Shared header should contain ISA through first HL*2
      header_ids = Enum.map(shared_header, & &1.id)
      assert "ISA" in header_ids
      assert "GS" in header_ids
      assert "ST" in header_ids
      assert "NM1" in header_ids

      # Should have 3 claim blocks
      assert length(claim_blocks) == 3

      # Each claim block should have a CLM segment
      for block <- claim_blocks do
        block_ids = Enum.map(block, & &1.id)
        assert "CLM" in block_ids
      end

      # Trailers should have SE, GE, IEA
      trailer_ids = Enum.map(trailers, & &1.id)
      assert "SE" in trailer_ids
      assert "GE" in trailer_ids
      assert "IEA" in trailer_ids
    end
  end
end
