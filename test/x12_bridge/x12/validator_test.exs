defmodule X12Bridge.X12.ValidatorTest do
  use ExUnit.Case, async: true

  alias X12Bridge.X12.Validator
  alias X12Bridge.X12.Validator.{ValidationResult, ValidationIssue}

  @valid_simple_x12 """
  ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       *250101*1200*U*00401*000000001*0*P*:~
  GS*HC*SENDER*RECEIVER*20250101*1200*1*X*004010X098A1~
  ST*837*0001~
  BHT*0019*00*BATCH123*20250101*1200*CH~
  NM1*41*2*SUBMITTER CLINIC*****46*SUBMITTER123~
  NM1*40*2*RECEIVER PAYER*****46*RECEIVER456~
  HL*1**20*1~
  NM1*85*2*BILLING PROVIDER CLINIC*****XX*1234567890~
  HL*2*1*22*0~
  SBR*P*18*GROUP123******CI~
  NM1*IL*1*DOE*JOHN****MI*MEMBERID123~
  NM1*QC*1*DOE*JOHN~
  CLM*CLAIM123*150.00***11:B:1~
  HI*ABK:R1010~
  LX*1~
  SV1*HC:99213*75.00*UN*1***1~
  SE*17*0001~
  GE*1*1~
  IEA*1*000000001~
  """

  describe "validate_content/1" do
    test "validates a valid X12 file" do
      result = Validator.validate_content(@valid_simple_x12)

      assert %ValidationResult{valid?: true} = result
      assert result.segment_count > 0
    end

    test "detects missing ISA segment" do
      # Content needs to be at least 106 bytes to pass length check
      invalid_x12 = "GS*HC*SENDER*RECEIVER*20250101*1200*1*X*004010X098A1" <> String.duplicate("X", 60) <> "~"
      result = Validator.validate_content(invalid_x12)

      assert %ValidationResult{valid?: false} = result
      assert Enum.any?(result.issues, fn issue -> issue.message =~ "File must start with ISA" end)
    end

    test "detects content too short" do
      result = Validator.validate_content("ISA*00")

      assert %ValidationResult{valid?: false} = result

      assert Enum.any?(result.issues, fn issue ->
               issue.message =~ "File too short to contain valid ISA segment"
             end)
    end

    test "detects missing required segments" do
      # Missing billing provider (NM1*85)
      invalid_x12 = """
      ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       *250101*1200*U*00401*000000001*0*P*:~
      GS*HC*SENDER*RECEIVER*20250101*1200*1*X*004010X098A1~
      ST*837*0001~
      NM1*IL*1*DOE*JOHN****MI*MEMBERID123~
      SE*4*0001~
      GE*1*1~
      IEA*1*000000001~
      """

      result = Validator.validate_content(invalid_x12)

      assert %ValidationResult{valid?: false} = result

      assert Enum.any?(result.issues, fn issue ->
               issue.message =~ "Missing required Billing Provider"
             end)
    end

    test "detects invalid transaction type" do
      # Wrong transaction type (850 instead of 837)
      invalid_x12 = """
      ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       *250101*1200*U*00401*000000001*0*P*:~
      GS*HC*SENDER*RECEIVER*20250101*1200*1*X*004010X098A1~
      ST*850*0001~
      SE*3*0001~
      GE*1*1~
      IEA*1*000000001~
      """

      result = Validator.validate_content(invalid_x12)

      assert %ValidationResult{valid?: false} = result

      assert Enum.any?(result.issues, fn issue ->
               issue.message =~ "Expected transaction set '837' but found '850'"
             end)
    end

    test "detects invalid date format" do
      invalid_x12 = """
      ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       *250101*1200*U*00401*000000001*0*P*:~
      GS*HC*SENDER*RECEIVER*20250101*1200*1*X*004010X098A1~
      ST*837*0001~
      NM1*85*2*BILLING PROVIDER*****XX*1234567890~
      NM1*IL*1*DOE*JOHN****MI*MEMBERID123~
      CLM*CLAIM123*150.00***11:B:1~
      DTP*472*D8*20251399~
      SE*7*0001~
      GE*1*1~
      IEA*1*000000001~
      """

      result = Validator.validate_content(invalid_x12)

      assert %ValidationResult{valid?: false} = result
      assert Enum.any?(result.issues, fn issue -> issue.message =~ "Date month 13 is invalid" end)
    end

    test "detects invalid claim amount" do
      invalid_x12 = """
      ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       *250101*1200*U*00401*000000001*0*P*:~
      GS*HC*SENDER*RECEIVER*20250101*1200*1*X*004010X098A1~
      ST*837*0001~
      NM1*85*2*BILLING PROVIDER*****XX*1234567890~
      NM1*IL*1*DOE*JOHN****MI*MEMBERID123~
      CLM*CLAIM123*INVALID***11:B:1~
      SE*6*0001~
      GE*1*1~
      IEA*1*000000001~
      """

      result = Validator.validate_content(invalid_x12)

      assert %ValidationResult{valid?: false} = result

      assert Enum.any?(result.issues, fn issue ->
               issue.message =~ "Claim amount 'INVALID' is not a valid number"
             end)
    end
  end

  describe "ValidationResult.get_summary/1" do
    test "counts issues by level" do
      result = %ValidationResult{
        valid?: false,
        issues: [
          %ValidationIssue{level: :error, segment_id: "CLM", segment_number: 1, element_position: nil, message: "Error 1", context: ""},
          %ValidationIssue{level: :error, segment_id: "NM1", segment_number: 2, element_position: nil, message: "Error 2", context: ""},
          %ValidationIssue{level: :warning, segment_id: "DTP", segment_number: 3, element_position: nil, message: "Warning 1", context: ""}
        ],
        segment_count: 10
      }

      summary = ValidationResult.get_summary(result)

      assert summary.error == 2
      assert summary.warning == 1
      assert summary.info == 0
    end
  end
end
