defmodule X12Bridge.X12.VerifierTest do
  use ExUnit.Case, async: true

  alias X12Bridge.X12.Verifier

  describe "verify/1" do
    test "returns valid result for well-formed X12 file with CLM segments" do
      x12_content = """
      ISA*00*          *00*          *ZZ*SUBMITTER      *ZZ*RECEIVER       *230101*1200*^*00501*000000001*0*P*:~
      GS*HC*SENDER*RECEIVER*20230101*1200*1*X*005010X222A1~
      ST*837*0001*005010X222A1~
      BHT*0019*00*123456*20230101*1200*CH~
      NM1*41*2*PROVIDER*****46*12345~
      CLM*CLAIM001*100***11:B:1*Y*A*Y*Y~
      SE*6*0001~
      GE*1*1~
      IEA*1*000000001~
      """

      result = Verifier.verify(x12_content)

      assert result.valid? == true
      assert result.claim_count == 1
      assert result.errors == []
      assert result.segment_delimiter == "~"
      assert result.element_delimiter == "*"
      assert result.transaction_type == "837"
      assert result.total_segments > 0
    end

    test "returns invalid result for X12 missing ISA segment" do
      x12_content = """
      GS*HC*SENDER*RECEIVER*20230101*1200*1*X*005010X222A1~
      ST*837*0001*005010X222A1~
      """

      result = Verifier.verify(x12_content)

      assert result.valid? == false
      assert Enum.any?(result.errors, fn err -> String.contains?(err, "Missing ISA segment") end)
    end

    test "returns invalid result for X12 missing required segments" do
      x12_content = """
      ISA*00*          *00*          *ZZ*SUBMITTER      *ZZ*RECEIVER       *230101*1200*^*00501*000000001*0*P*:~
      GS*HC*SENDER*RECEIVER*20230101*1200*1*X*005010X222A1~
      ST*837*0001*005010X222A1~
      SE*3*0001~
      GE*1*1~
      IEA*1*000000001~
      """

      result = Verifier.verify(x12_content)

      assert result.valid? == false
      assert Enum.any?(result.errors, fn err -> String.contains?(err, "Missing required segment: BHT") end)
      assert Enum.any?(result.errors, fn err -> String.contains?(err, "Missing required segment: NM1") end)
      assert Enum.any?(result.errors, fn err -> String.contains?(err, "Missing required segment: CLM") end)
    end

    test "returns invalid result for empty content" do
      result = Verifier.verify("")

      assert result.valid? == false
      assert String.contains?(hd(result.errors), "File is empty")
    end

    test "counts multiple claims correctly" do
      x12_content = """
      ISA*00*          *00*          *ZZ*SUBMITTER      *ZZ*RECEIVER       *230101*1200*^*00501*000000001*0*P*:~
      GS*HC*SENDER*RECEIVER*20230101*1200*1*X*005010X222A1~
      ST*837*0001*005010X222A1~
      BHT*0019*00*123456*20230101*1200*CH~
      NM1*41*2*PROVIDER*****46*12345~
      CLM*CLAIM001*100***11:B:1*Y*A*Y*Y~
      CLM*CLAIM002*200***11:B:1*Y*A*Y*Y~
      CLM*CLAIM003*300***11:B:1*Y*A*Y*Y~
      SE*8*0001~
      GE*1*1~
      IEA*1*000000001~
      """

      result = Verifier.verify(x12_content)

      assert result.valid? == true
      assert result.claim_count == 3
    end

    test "detects unmatched envelope segments" do
      x12_content = """
      ISA*00*          *00*          *ZZ*SUBMITTER      *ZZ*RECEIVER       *230101*1200*^*00501*000000001*0*P*:~
      GS*HC*SENDER*RECEIVER*20230101*1200*1*X*005010X222A1~
      ST*837*0001*005010X222A1~
      BHT*0019*00*123456*20230101*1200*CH~
      NM1*41*2*PROVIDER*****46*12345~
      CLM*CLAIM001*100***11:B:1*Y*A*Y*Y~
      ST*837*0002*005010X222A1~
      SE*3*0002~
      GE*1*1~
      IEA*1*000000001~
      """

      result = Verifier.verify(x12_content)

      assert result.valid? == false
      assert Enum.any?(result.errors, fn err -> String.contains?(err, "Unmatched ST/SE") end)
    end
  end

  describe "format_result/1" do
    test "formats valid result with claims" do
      result = %{valid?: true, claim_count: 3, warnings: []}
      formatted = Verifier.format_result(result)

      assert formatted =~ "✓ VERIFIED"
      assert formatted =~ "3 claim(s) found"
    end

    test "formats invalid result with errors" do
      result = %{
        valid?: false,
        errors: ["Missing ISA segment", "Missing GS segment"]
      }

      formatted = Verifier.format_result(result)

      assert formatted =~ "✗ VERIFICATION FAILED"
      assert formatted =~ "Missing ISA segment"
      assert formatted =~ "Missing GS segment"
    end

    test "includes warnings in valid result" do
      result = %{
        valid?: true,
        claim_count: 1,
        warnings: ["Non-standard delimiter detected"]
      }

      formatted = Verifier.format_result(result)

      assert formatted =~ "✓ VERIFIED"
      assert formatted =~ "Warnings:"
      assert formatted =~ "Non-standard delimiter"
    end
  end
end
