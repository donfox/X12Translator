defmodule X12Bridge.X12.ParserTest do
  use ExUnit.Case, async: true

  alias X12Bridge.X12.Parser
  alias X12Bridge.X12.Parser.{Segment, Delimiters}

  describe "parse_delimiters/1" do
    test "extracts delimiters from valid ISA segment" do
      isa = "ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       *250101*1200*U*00401*000000001*0*P*:~"

      assert {:ok, %Delimiters{element: "*", sub_element: ":", segment: "~"}} =
               Parser.parse_delimiters(isa)
    end

    test "returns error for content too short" do
      assert {:error, "File too short to contain valid ISA segment"} =
               Parser.parse_delimiters("ISA*00")
    end

    test "returns error for content not starting with ISA" do
      # Content needs to be at least 106 bytes to pass length check
      content = "GS*HC*SENDER*RECEIVER*20250101*1200*1*X*004010X098A1" <> String.duplicate("X", 60) <> "~"
      assert {:error, "File must start with ISA segment"} = Parser.parse_delimiters(content)
    end
  end

  describe "parse_segments/2" do
    test "parses segments correctly" do
      content = "ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       *250101*1200*U*00401*000000001*0*P*:~GS*HC*SENDER*RECEIVER*20250101*1200*1*X*004010X098A1~ST*837*0001~"

      delimiters = %Delimiters{element: "*", sub_element: ":", segment: "~"}
      {:ok, segments} = Parser.parse_segments(content, delimiters)

      assert length(segments) == 3
      assert [%Segment{id: "ISA"}, %Segment{id: "GS"}, %Segment{id: "ST"}] = segments
    end
  end

  describe "get_element/2" do
    test "retrieves element by position" do
      segment = %Segment{
        id: "CLM",
        elements: ["CLM", "CLAIM123", "150.00", "", "", "11:B:1"],
        raw: "CLM*CLAIM123*150.00***11:B:1",
        line_number: 1
      }

      assert "CLAIM123" = Parser.get_element(segment, 1)
      assert "150.00" = Parser.get_element(segment, 2)
      assert "" = Parser.get_element(segment, 3)
    end

    test "returns empty string for out of bounds position" do
      segment = %Segment{id: "CLM", elements: ["CLM", "ID"], raw: "CLM*ID", line_number: 1}
      assert "" = Parser.get_element(segment, 10)
    end
  end

  describe "parse_composite/2" do
    test "splits composite element by sub-delimiter" do
      assert ["HC", "99213"] = Parser.parse_composite("HC:99213", ":")
      assert ["11", "B", "1"] = Parser.parse_composite("11:B:1", ":")
    end

    test "handles elements without sub-delimiter" do
      assert ["SIMPLE"] = Parser.parse_composite("SIMPLE", ":")
    end
  end

  describe "find_segments/2" do
    test "finds all segments with matching ID" do
      segments = [
        %Segment{id: "NM1", elements: ["NM1", "85"], raw: "", line_number: 1},
        %Segment{id: "CLM", elements: ["CLM"], raw: "", line_number: 2},
        %Segment{id: "NM1", elements: ["NM1", "IL"], raw: "", line_number: 3}
      ]

      nm1_segments = Parser.find_segments(segments, "NM1")
      assert length(nm1_segments) == 2
      assert Enum.all?(nm1_segments, fn s -> s.id == "NM1" end)
    end
  end

  describe "find_segment/2" do
    test "finds first segment with matching ID" do
      segments = [
        %Segment{id: "ISA", elements: ["ISA"], raw: "", line_number: 1},
        %Segment{id: "GS", elements: ["GS"], raw: "", line_number: 2}
      ]

      assert %Segment{id: "ISA"} = Parser.find_segment(segments, "ISA")
    end

    test "returns nil if not found" do
      segments = [%Segment{id: "ISA", elements: ["ISA"], raw: "", line_number: 1}]
      assert nil == Parser.find_segment(segments, "CLM")
    end
  end
end
