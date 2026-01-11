defmodule Mix.Tasks.GenerateBatch do
  @moduledoc """
  Generates mock X12 batch data for testing.

  ## Usage

      # Generate custom batch
      mix generate_batch custom --size 100 --name my_batch

  ## Batch Types

  - **custom**: Custom size and configuration

  ## Output Location

  Generates test batches in test/fixtures/x12/[batch_name]/

  Note: For standard testing, use the existing automated_test_data/ fixtures.
  This task is useful for generating custom test scenarios.
  """

  use Mix.Task

  @shortdoc "Generate mock X12 batch data"
  def run(args) do
    {opts, batch_type, _} = OptionParser.parse(args,
      strict: [size: :integer, name: :string, error_rate: :float],
      aliases: [s: :size, n: :name, e: :error_rate]
    )

    batch_config = case batch_type do
      ["custom"] ->
        %{
          size: opts[:size] || 10,
          error_rate: opts[:error_rate] || 0.10,
          description: "Custom batch"
        }
      _ ->
        Mix.shell().info("Usage: mix generate_batch custom --size N --name batch_name [--error_rate 0.1]")
        Mix.shell().info("\nFor standard testing, use existing fixtures: test/fixtures/x12/automated_test_data/")
        System.halt(1)
    end

    batch_name = opts[:name] || "custom_batch_#{:os.system_time(:millisecond)}"

    Mix.shell().info("Generating #{batch_name} with #{batch_config.size} files (#{batch_config.error_rate * 100}% error rate)...")

    generate_batch(batch_name, batch_config)

    Mix.shell().info("✓ Batch generated: test/fixtures/x12/#{batch_name}")
  end

  defp generate_batch(batch_name, config) do
    batch_dir = Path.join("test/fixtures/x12", batch_name)
    File.mkdir_p!(batch_dir)

    num_errors = round(config.size * config.error_rate)
    num_valid = config.size - num_errors

    Mix.shell().info("Generating #{num_valid} valid files and #{num_errors} error files...")

    files = []

    # Generate valid 837P files (60%)
    p_count = round(num_valid * 0.60)
    files = files ++ generate_files(batch_dir, "837P", p_count, :valid, 1)

    # Generate valid 837I files (25%)
    i_count = round(num_valid * 0.25)
    files = files ++ generate_files(batch_dir, "837I", i_count, :valid, p_count + 1)

    # Generate valid 837D files (15%)
    d_count = num_valid - p_count - i_count
    files = files ++ generate_files(batch_dir, "837D", d_count, :valid, p_count + i_count + 1)

    # Generate error files
    files = files ++ generate_files(batch_dir, "ERROR", num_errors, :error, num_valid + 1)

    # Generate manifest
    manifest = %{
      batch_id: "#{batch_name}_001",
      description: config.description,
      total_files: config.size,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      files: files
    }

    manifest_path = Path.join(batch_dir, "manifest.json")
    manifest_json = Jason.encode!(manifest, pretty: true)
    File.write!(manifest_path, manifest_json)
  end

  defp generate_files(batch_dir, file_type, count, validity, start_index) do
    Enum.map(1..count, fn i ->
      file_num = String.pad_leading(Integer.to_string(start_index + i - 1), 3, "0")
      filename = "#{file_num}_#{String.downcase(file_type)}_#{validity}.x12"
      file_path = Path.join(batch_dir, filename)

      content = case validity do
        :valid -> generate_valid_x12(file_type, file_num)
        :error -> generate_error_x12(file_num)
      end

      File.write!(file_path, content)

      %{
        filename: filename,
        type: file_type,
        description: "#{file_type} #{validity} claim",
        expected_status: if(validity == :valid, do: "success", else: "error"),
        expected_claims: if(validity == :valid, do: 1, else: 0)
      }
    end)
  end

  defp generate_valid_x12("837P", file_num) do
    control_num = String.pad_leading(file_num, 9, "0")
    claim_id = "CLAIM#{control_num}"

    """
    ISA*00*          *00*          *ZZ*SUBMITTER123   *ZZ*RECEIVER456    *250101*1200*U*00401*#{control_num}*0*P*:~
    GS*HC*SUBMITTER123*RECEIVER456*20250101*1200*1*X*004010X098A1~
    ST*837*0001~
    BHT*0019*00*BATCH#{control_num}*20250101*1200*CH~
    NM1*41*2*ACME MEDICAL BILLING*****46*SUB123~
    PER*IC*JOHN DOE*TE*5555551234~
    NM1*40*2*BLUE CROSS BLUE SHIELD*****46*REC456~
    HL*1**20*1~
    PRV*BI*PXC*207Q00000X~
    NM1*85*2*CITY HOSPITAL CLINIC*****XX*1234567890~
    N3*123 MAIN STREET~
    N4*ANYTOWN*CA*90210~
    REF*EI*123456789~
    HL*2*1*22*0~
    SBR*P*18*GROUP123******CI~
    NM1*IL*1*SMITH*JANE*M***MI*MEMBER123456~
    N3*456 ELM STREET~
    N4*ANYTOWN*CA*90210~
    DMG*D8*19800515*F~
    NM1*PR*2*BLUE CROSS BLUE SHIELD*****PI*54321~
    REF*G2*GROUP123~
    CLM*#{claim_id}*500.00***11:B:1*Y*A*Y*Y~
    DTP*431*D8*20241215~
    DTP*472*D8*20241215~
    HI*ABK:J189*ABK:E119~
    NM1*82*1*JOHNSON*ROBERT*A***XX*9876543210~
    PRV*PE*PXC*207Q00000X~
    LX*1~
    SV1*HC:99213*150.00*UN*1***1~
    DTP*472*D8*20241215~
    LX*2~
    SV1*HC:80053*200.00*UN*1***1~
    DTP*472*D8*20241215~
    LX*3~
    SV1*HC:93000*150.00*UN*1***1~
    DTP*472*D8*20241215~
    SE*34*0001~
    GE*1*1~
    IEA*1*#{control_num}~
    """
  end

  defp generate_valid_x12("837I", file_num) do
    control_num = String.pad_leading(file_num, 9, "0")
    claim_id = "CLAIM#{control_num}"

    """
    ISA*00*          *00*          *ZZ*SUBMITTER123   *ZZ*RECEIVER456    *250101*1200*U*00401*#{control_num}*0*P*:~
    GS*HC*SUBMITTER123*RECEIVER456*20250101*1200*1*X*005010X223A2~
    ST*837*0001~
    BHT*0019*00*BATCH#{control_num}*20250101*1200*CH~
    NM1*41*2*HOSPITAL BILLING CORP*****46*SUB789~
    PER*IC*MARY JONES*TE*5555555678~
    NM1*40*2*MEDICARE*****46*MEDICARE~
    HL*1**20*1~
    PRV*BI*PXC*282N00000X~
    NM1*85*2*GENERAL HOSPITAL*****XX*9876543210~
    N3*789 HOSPITAL ROAD~
    N4*METROPOLIS*NY*10001~
    REF*EI*987654321~
    HL*2*1*22*0~
    SBR*P*18*MEDICARE******MB~
    NM1*IL*1*DOE*JOHN*Q***MI*MEDICARE123~
    N3*999 PATIENT LANE~
    N4*METROPOLIS*NY*10001~
    DMG*D8*19450320*M~
    NM1*PR*2*MEDICARE*****PI*MEDICARE~
    CLM*#{claim_id}*2500.00***13::1*Y*A*Y*I~
    DTP*434*RD8*20241210-20241215~
    DTP*435*D8*20241210~
    HI*ABK:I10*ABK:E785~
    LX*1~
    SV2*0450*HC:99223*1500.00*UN*1~
    DTP*472*D8*20241210~
    LX*2~
    SV2*0250*HC:J0180*1000.00*UN*10~
    DTP*472*D8*20241211~
    SE*30*0001~
    GE*1*1~
    IEA*1*#{control_num}~
    """
  end

  defp generate_valid_x12("837D", file_num) do
    control_num = String.pad_leading(file_num, 9, "0")
    claim_id = "CLAIM#{control_num}"

    """
    ISA*00*          *00*          *ZZ*SUBMITTER123   *ZZ*RECEIVER456    *250101*1200*U*00401*#{control_num}*0*P*:~
    GS*HC*SUBMITTER123*RECEIVER456*20250101*1200*1*X*004010X097A1~
    ST*837*0001~
    BHT*0019*00*BATCH#{control_num}*20250101*1200*CH~
    NM1*41*2*DENTAL BILLING SERVICE*****46*DENT123~
    PER*IC*SARAH SMITH*TE*5555559999~
    NM1*40*2*DELTA DENTAL*****46*DELTA~
    HL*1**20*1~
    PRV*BI*PXC*1223G0001X~
    NM1*85*2*SMILE DENTAL CLINIC*****XX*5556667777~
    N3*321 DENTAL AVE~
    N4*TOOTH CITY*TX*75001~
    REF*EI*556667777~
    HL*2*1*22*0~
    SBR*P*18*DELTAGRP******CI~
    NM1*IL*1*PATIENT*SALLY*R***MI*DELTA987654~
    N3*111 SMILE STREET~
    N4*TOOTH CITY*TX*75001~
    DMG*D8*19900707*F~
    NM1*PR*2*DELTA DENTAL*****PI*DELTA~
    CLM*#{claim_id}*350.00***12:B:1*Y*A*Y*Y~
    DTP*472*D8*20241220~
    HI*ABK:K021~
    LX*1~
    SV3*AD:D1110*100.00*11***1~
    DTP*472*D8*20241220~
    TOO*JP*2*M~
    LX*2~
    SV3*AD:D0120*50.00*11***1~
    DTP*472*D8*20241220~
    TOO*JP*3*O~
    LX*3~
    SV3*AD:D2740*200.00*11***1~
    DTP*472*D8*20241220~
    TOO*JP*14~
    SE*31*0001~
    GE*1*1~
    IEA*1*#{control_num}~
    """
  end

  defp generate_error_x12(file_num) do
    # Intentionally malformed - missing ISA segment and too short
    "INVALID X12 FILE #{file_num}\nThis file is intentionally broken for testing error handling.\n"
  end
end
