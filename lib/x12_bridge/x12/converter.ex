defmodule X12Bridge.X12.Converter do
  @moduledoc """
  X12 to JSON Converter & Builder

  Converts X12 837 (Healthcare Claims) EDI files into semantic,
  hierarchical JSON format, and reconstructs X12 from JSON.

  Supports:
  - 837P (Professional Claims) - uses SV1 segments
  - 837I (Institutional Claims) - uses SV2 segments
  - 837D (Dental Claims) - uses SV3 segments

  The output structure organizes claims with nested service lines,
  making the data easier to work with for developers.

  The Builder functionality reconstructs X12 EDI from the JSON
  output for round-trip validation to ensure data integrity.
  """

  alias X12Bridge.X12.Parser

  # Maximum file size: 50MB (configurable)
  @max_file_size_bytes 50 * 1024 * 1024

  # Processing timeout: 30 seconds (configurable)
  @processing_timeout_ms 30_000

  @doc """
  Convert X12 file to JSON with timeout protection

  ## Examples

      iex> Converter.convert_file("sample.x12")
      {:ok, json_string}
  """
  def convert_file(filepath) do
    case File.stat(filepath) do
      {:ok, %File.Stat{size: size}} when size > @max_file_size_bytes ->
        size_mb = Float.round(size / (1024 * 1024), 2)
        max_mb = Float.round(@max_file_size_bytes / (1024 * 1024), 2)
        {:error, "File too large: #{size_mb} MB exceeds maximum of #{max_mb} MB"}

      {:ok, _stat} ->
        case File.read(filepath) do
          {:ok, content} ->
            do_convert_content(content)

          {:error, :enoent} ->
            {:error, "File not found: #{filepath}"}

          {:error, reason} ->
            {:error, "Failed to read file: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to access file: #{inspect(reason)}"}
    end
  end

  @doc """
  Convert X12 content string to JSON with timeout protection

  Returns {:ok, json_string} or {:error, reason}
  """
  def convert_content(content) when is_binary(content) do
    do_convert_content(content)
  end

  # Internal function with timeout wrapper and error handling
  defp do_convert_content(content) do
    task = Task.async(fn ->
      try do
        case Parser.parse(content) do
          {:ok, %{delimiters: delimiters, segments: segments}} ->
            # build_structure always returns {:ok, ...}, so we can pattern match directly
            {:ok, structured_data} = build_structure(segments, delimiters)
            Jason.encode(structured_data, pretty: true)
          {:error, reason} ->
            {:error, "Parsing failed: #{inspect(reason)}"}
        end
      rescue
        e in ArgumentError ->
          {:error, "Invalid X12 format: #{Exception.message(e)}"}
        e in RuntimeError ->
          {:error, "Processing error: #{Exception.message(e)}"}
        e ->
          {:error, "Unexpected error: #{Exception.message(e)}"}
      end
    end)

    case Task.yield(task, @processing_timeout_ms) || Task.shutdown(task) do
      {:ok, result} ->
        result
      nil ->
        timeout_sec = div(@processing_timeout_ms, 1000)
        {:error, "Processing timeout: File took longer than #{timeout_sec} seconds to process"}
      {:exit, reason} ->
        {:error, "Processing crashed: #{inspect(reason)}"}
    end
  end

  @doc """
  Build structured data from parsed segments
  """
  def build_structure(segments, delimiters) when is_list(segments) do
    envelopes = Parser.extract_envelopes(segments)
    loops = Parser.identify_loops(segments)

    # Collect warnings
    warnings = []

    # Validate envelope segments
    warnings =
      warnings
      |> add_warning_if_nil(envelopes.isa, "Missing ISA (Interchange Control Header) segment")
      |> add_warning_if_nil(envelopes.gs, "Missing GS (Functional Group Header) segment")
      |> add_warning_if_nil(envelopes.st, "Missing ST (Transaction Set Header) segment")
      |> add_warning_if_nil(envelopes.se, "Missing SE (Transaction Set Trailer) segment")
      |> add_warning_if_nil(envelopes.ge, "Missing GE (Functional Group Trailer) segment")
      |> add_warning_if_nil(envelopes.iea, "Missing IEA (Interchange Control Trailer) segment")

    # Extract file info
    file_info = extract_file_info(envelopes)

    # Extract envelope details
    interchange_header = extract_interchange_header(envelopes.isa)
    functional_group = extract_functional_group(envelopes.gs)
    transaction_set = extract_transaction_set(envelopes.st, segments)

    # Extract entities
    billing_provider = extract_billing_provider(segments)
    subscriber = extract_subscriber(segments)

    # Check for missing entities
    warnings = warnings |> add_warning_if_nil(billing_provider, "No billing provider (NM1*85) found")

    # Extract claims
    claims = Enum.map(loops, &extract_claim(&1, delimiters))

    # Check for claims without service lines
    warnings =
      claims
      |> Enum.reduce(warnings, fn claim, acc ->
        if length(Map.get(claim, :service_lines, [])) == 0 do
          add_warning(acc, "Claim #{claim.claim_id} has no service lines")
        else
          acc
        end
      end)

    # Extract flat segments list
    all_segments = extract_all_segments(segments)

    # Extract groupings
    other_entities = extract_other_entities(segments)
    contacts = extract_contacts(segments)
    hierarchical_levels = extract_hierarchical_levels(segments)
    header_references = extract_header_references(segments)

    # Calculate summary
    total_service_lines =
      Enum.reduce(claims, 0, fn claim, acc ->
        acc + length(Map.get(claim, :service_lines, []))
      end)

    structured = %{
      file_info: file_info,
      interchange_header: interchange_header,
      functional_group: functional_group,
      transaction_set: transaction_set,
      billing_provider: billing_provider,
      subscriber: subscriber,
      claims: claims,
      all_segments: all_segments,
      other_entities: other_entities,
      contacts: contacts,
      hierarchical_levels: hierarchical_levels,
      header_references: header_references,
      warnings: warnings,
      summary: %{
        total_segments: length(segments),
        total_claims: length(claims),
        total_service_lines: total_service_lines,
        warnings_count: length(warnings)
      }
    }

    {:ok, structured}
  end

  # Helper functions for warnings
  defp add_warning(warnings, message) do
    warnings ++ [message]
  end

  defp add_warning_if_nil(warnings, value, message) do
    if is_nil(value) do
      add_warning(warnings, message)
    else
      warnings
    end
  end

  # Extract claim information from a loop
  defp extract_claim(%{claim_segment: clm_segment, claim_segments: claim_segs, service_lines: service_lines}, delimiters) do
    # Extract basic claim info from CLM segment
    claim_id = Parser.get_element(clm_segment, 1)
    total_charge = Parser.get_element(clm_segment, 2)
    claim_filing_code = Parser.get_element(clm_segment, 5)

    # Find related segments (get raw segment, not processed entity)
    patient_nm1_segment = Enum.find(claim_segs, fn seg ->
      seg.id == "NM1" && Parser.get_element(seg, 1) == "QC"
    end)

    # Extract dates with full structure
    dates = claim_segs
    |> Enum.filter(fn seg -> seg.id == "DTP" end)
    |> Enum.map(fn dtp ->
      qualifier = Parser.get_element(dtp, 1)
      %{
        segment_id: "DTP",
        date_qualifier: qualifier,
        date_qualifier_desc: date_qualifier(qualifier),
        date_format: Parser.get_element(dtp, 2),
        date_value: Parser.get_element(dtp, 3),
        all_elements: dtp.elements
      }
    end)

    # Extract references with full structure
    references = claim_segs
    |> Enum.filter(fn seg -> seg.id == "REF" end)
    |> Enum.map(fn ref ->
      qualifier = Parser.get_element(ref, 1)
      %{
        segment_id: "REF",
        reference_id_qualifier: qualifier,
        reference_id_qualifier_desc: reference_qualifier(qualifier),
        reference_id: Parser.get_element(ref, 2),
        description: Parser.get_element(ref, 3),
        all_elements: ref.elements
      }
    end)

    # Extract diagnosis codes with full structure
    diagnosis_codes_data = claim_segs
    |> Enum.filter(fn seg -> seg.id == "HI" end)
    |> List.first()
    |> case do
      nil -> nil
      hi ->
        codes = hi.elements
        |> Enum.drop(1)
        |> Enum.reject(fn el -> el == "" end)

        %{
          segment_id: "HI",
          codes: codes,
          all_elements: hi.elements
        }
    end

    # Extract patient info if present
    patient = if patient_nm1_segment do
      entity_code = Parser.get_element(patient_nm1_segment, 1)
      %{
        segment_id: "NM1",
        entity_id_code: entity_code,
        entity_id_code_desc: entity_code(entity_code),
        entity_type_qualifier: Parser.get_element(patient_nm1_segment, 2),
        name_last_or_organization: Parser.get_element(patient_nm1_segment, 3),
        name_first: Parser.get_element(patient_nm1_segment, 4),
        name_middle: Parser.get_element(patient_nm1_segment, 5),
        name_prefix: Parser.get_element(patient_nm1_segment, 6),
        name_suffix: Parser.get_element(patient_nm1_segment, 7),
        id_code_qualifier: Parser.get_element(patient_nm1_segment, 8),
        id_code: Parser.get_element(patient_nm1_segment, 9),
        all_elements: patient_nm1_segment.elements
      }
    else
      nil
    end

    # Extract service lines
    service_lines_data = Enum.map(service_lines, &extract_service_line(&1, delimiters))

    base_claim = %{
      segment_id: "CLM",
      claim_id: claim_id,
      total_charge: total_charge,
      claim_filing_indicator: claim_filing_code,
      claim_filing_indicator_desc: claim_filing_indicator(claim_filing_code),
      provider_signature_indicator: Parser.get_element(clm_segment, 6),
      assignment_plan: Parser.get_element(clm_segment, 7),
      benefits_assignment: Parser.get_element(clm_segment, 8),
      release_info: Parser.get_element(clm_segment, 9),
      all_elements: clm_segment.elements,
      dates: dates,
      references: references,
      diagnosis_codes: diagnosis_codes_data,
      service_lines: service_lines_data
    }

    if patient do
      Map.put(base_claim, :patient, patient)
    else
      base_claim
    end
  end

  # Extract service line information
  defp extract_service_line(%{line_segment: lx_segment, line_segments: line_segs}, delimiters) do
    # Find SV1 (Professional), SV2 (Institutional), or SV3 (Dental) segment
    sv1 = Enum.find(line_segs, fn seg -> seg.id == "SV1" end)
    sv2 = Enum.find(line_segs, fn seg -> seg.id == "SV2" end)
    sv3 = Enum.find(line_segs, fn seg -> seg.id == "SV3" end)

    cond do
      sv1 ->
        extract_professional_service_line(lx_segment, sv1, line_segs, delimiters)

      sv2 ->
        extract_institutional_service_line(lx_segment, sv2, line_segs, delimiters)

      sv3 ->
        extract_dental_service_line(lx_segment, sv3, line_segs, delimiters)

      true ->
        # No service segment found
        if lx_segment do
          %{
            line_number: Parser.get_element(lx_segment, 1),
            error: "SV1, SV2, or SV3 segment not found for service line"
          }
        else
          %{
            error: "No service segment (SV1/SV2/SV3) found for implicit service line"
          }
        end
    end
  end

  # Extract professional service line (837P - SV1)
  defp extract_professional_service_line(lx_segment, sv1, _line_segs, delimiters) do
    # Extract procedure code (composite element)
    procedure_composite = Parser.get_element(sv1, 1)
    _procedure_parts = Parser.parse_composite(procedure_composite, delimiters.sub_element)

    # Extract other elements
    line_charge = Parser.get_element(sv1, 2)
    unit_type = Parser.get_element(sv1, 3)
    quantity = Parser.get_element(sv1, 4)
    diagnosis_pointer = Parser.get_element(sv1, 7)

    place_of_service_code = Parser.get_element(sv1, 5)
    base_result = %{
      service_info: %{
        segment_id: "SV1",
        procedure_info: procedure_composite,
        line_charge: line_charge,
        unit_basis: unit_type,
        unit_count: quantity,
        place_of_service: place_of_service_code,
        place_of_service_desc: place_of_service(place_of_service_code),
        diagnosis_pointer: diagnosis_pointer,
        all_elements: sv1.elements
      }
    }

    # Add LX info if present (some files may lack LX segments)
    if lx_segment do
      Map.merge(base_result, %{
        segment_id: "LX",
        line_number: Parser.get_element(lx_segment, 1),
        all_elements: lx_segment.elements
      })
    else
      base_result
    end
  end

  # Extract institutional service line (837I - SV2)
  defp extract_institutional_service_line(lx_segment, sv2, line_segs, delimiters) do
    # Extract revenue code
    revenue_code = Parser.get_element(sv2, 1)

    # Extract procedure code (composite element)
    procedure_composite = Parser.get_element(sv2, 2)
    procedure_parts = Parser.parse_composite(procedure_composite, delimiters.sub_element)

    procedure_qualifier = Enum.at(procedure_parts, 0, "")
    procedure_code = Enum.at(procedure_parts, 1, "")
    procedure_modifiers = Enum.drop(procedure_parts, 2)

    # Extract other elements
    line_charge = Parser.get_element(sv2, 3)
    unit_type = Parser.get_element(sv2, 4)
    quantity = Parser.get_element(sv2, 5)

    # Extract dates for this service line
    dates = line_segs
    |> Enum.filter(fn seg -> seg.id == "DTP" end)
    |> Enum.map(fn dtp ->
      %{
        segment_id: "DTP",
        date_qualifier: Parser.get_element(dtp, 1),
        date_format: Parser.get_element(dtp, 2),
        date_value: Parser.get_element(dtp, 3),
        all_elements: dtp.elements
      }
    end)

    base_result = %{
      service_info: %{
        segment_id: "SV2",
        revenue_code: revenue_code,
        procedure_info: procedure_composite,
        procedure_qualifier: procedure_qualifier,
        procedure_code: procedure_code,
        procedure_modifiers: procedure_modifiers,
        line_charge: line_charge,
        unit_basis: unit_type,
        unit_count: quantity,
        all_elements: sv2.elements
      },
      dates: dates
    }

    # Add LX info if present (some 837I files have LX segments)
    if lx_segment do
      Map.merge(base_result, %{
        segment_id: "LX",
        line_number: Parser.get_element(lx_segment, 1),
        all_elements: lx_segment.elements
      })
    else
      base_result
    end
  end

  # Extract dental service line (837D - SV3)
  defp extract_dental_service_line(lx_segment, sv3, _line_segs, delimiters) do
    # Extract procedure code (composite element)
    procedure_composite = Parser.get_element(sv3, 1)
    _procedure_parts = Parser.parse_composite(procedure_composite, delimiters.sub_element)

    # Extract other elements
    line_charge = Parser.get_element(sv3, 2)
    service_code = Parser.get_element(sv3, 3)

    base_result = %{
      service_info: %{
        segment_id: "SV3",
        procedure_info: procedure_composite,
        line_charge: line_charge,
        service_code: service_code,
        all_elements: sv3.elements
      }
    }

    # Add LX info if present (some files may lack LX segments)
    if lx_segment do
      Map.merge(base_result, %{
        segment_id: "LX",
        line_number: Parser.get_element(lx_segment, 1),
        all_elements: lx_segment.elements
      })
    else
      base_result
    end
  end

  # EXTRACTION FUNCTIONS

  defp extract_file_info(envelopes) do
    st = envelopes.st
    gs = envelopes.gs

    transaction_type = if st, do: Parser.get_element(st, 1), else: "837"
    version = if gs, do: Parser.get_element(gs, 8), else: ""

    # Detect X12 version (4010 vs 5010)
    {x12_version, x12_version_desc} = detect_x12_version(version)

    file_type = case version do
      v when is_binary(v) and byte_size(v) > 0 ->
        cond do
          String.contains?(v, "222") -> "X12 837P Professional Healthcare Claim"
          String.contains?(v, "223") -> "X12 837I Institutional Healthcare Claim"
          String.contains?(v, "224") -> "X12 837D Dental Healthcare Claim"
          true -> "X12 #{transaction_type} Healthcare Claim"
        end
      _ -> "X12 #{transaction_type} Healthcare Claim"
    end

    %{
      source_file: "uploaded_file",
      file_type: file_type,
      x12_version: x12_version,
      x12_version_description: x12_version_desc,
      implementation_guide: version
    }
  end

  defp detect_x12_version(version_code) when is_binary(version_code) do
    cond do
      String.starts_with?(version_code, "00401") or String.contains?(version_code, "4010") ->
        {"4010", "Version 4010 (Legacy HIPAA Standard)"}

      String.starts_with?(version_code, "00501") or String.contains?(version_code, "5010") ->
        {"5010", "Version 5010 (Current HIPAA Standard)"}

      String.starts_with?(version_code, "00701") or String.contains?(version_code, "7030") ->
        {"7030", "Version 7030 (Future Standard)"}

      byte_size(version_code) > 0 ->
        {"Unknown", "Unrecognized version: #{version_code}"}

      true ->
        {"Unknown", "No version information"}
    end
  end

  defp detect_x12_version(_), do: {"Unknown", "No version information"}

  defp extract_interchange_header(nil), do: %{}
  defp extract_interchange_header(isa) do
    %{
      segment_id: "ISA",
      authorization_info_qualifier: Parser.get_element(isa, 1),
      authorization_info: Parser.get_element(isa, 2),
      security_info_qualifier: Parser.get_element(isa, 3),
      security_info: Parser.get_element(isa, 4),
      sender_id_qualifier: Parser.get_element(isa, 5),
      sender_id: Parser.get_element(isa, 6),
      receiver_id_qualifier: Parser.get_element(isa, 7),
      receiver_id: Parser.get_element(isa, 8),
      interchange_date: Parser.get_element(isa, 9),
      interchange_time: Parser.get_element(isa, 10),
      standards_id: Parser.get_element(isa, 11),
      version_number: Parser.get_element(isa, 12),
      interchange_control_number: Parser.get_element(isa, 13),
      acknowledgment_requested: Parser.get_element(isa, 14),
      usage_indicator: Parser.get_element(isa, 15),
      all_elements: isa.elements
    }
  end

  defp extract_functional_group(nil), do: %{}
  defp extract_functional_group(gs) do
    %{
      segment_id: "GS",
      functional_id_code: Parser.get_element(gs, 1),
      application_sender_code: Parser.get_element(gs, 2),
      application_receiver_code: Parser.get_element(gs, 3),
      date: Parser.get_element(gs, 4),
      time: Parser.get_element(gs, 5),
      group_control_number: Parser.get_element(gs, 6),
      responsible_agency_code: Parser.get_element(gs, 7),
      version_code: Parser.get_element(gs, 8),
      all_elements: gs.elements
    }
  end

  defp extract_transaction_set(nil, _segments), do: %{}
  defp extract_transaction_set(st, segments) do
    # Find BHT segment
    bht = Parser.find_segments(segments, "BHT") |> List.first()

    bht_data = if bht do
      %{
        segment_id: "BHT",
        hierarchical_structure_code: Parser.get_element(bht, 1),
        transaction_set_purpose_code: Parser.get_element(bht, 2),
        reference_id: Parser.get_element(bht, 3),
        date: Parser.get_element(bht, 4),
        time: Parser.get_element(bht, 5),
        claim_type: Parser.get_element(bht, 6),
        all_elements: bht.elements
      }
    else
      nil
    end

    %{
      segment_id: "ST",
      transaction_set_id: Parser.get_element(st, 1),
      transaction_control_number: Parser.get_element(st, 2),
      implementation_convention_ref: Parser.get_element(st, 3),
      all_elements: st.elements,
      beginning_hierarchical_transaction: bht_data
    }
  end

  defp extract_billing_provider(segments) do
    # Find NM1*85 (billing provider)
    nm1_85 = segments
    |> Parser.find_segments("NM1")
    |> Enum.find(fn seg -> Parser.get_element(seg, 1) == "85" end)

    if nm1_85 do
      # Find associated address segments after this NM1 (within next 10 segments to avoid crossing entity boundaries)
      nm1_index = Enum.find_index(segments, fn seg -> seg == nm1_85 end)
      following_segments =
        segments
        |> Enum.drop(nm1_index + 1)
        |> Enum.take(10)  # Limit search to avoid crossing into different entity

      n3 = Enum.find(following_segments, fn seg -> seg.id == "N3" end)
      n4 = Enum.find(following_segments, fn seg -> seg.id == "N4" end)

      address = if n3 do
        %{
          segment_id: "N3",
          address_line_1: Parser.get_element(n3, 1),
          address_line_2: Parser.get_element(n3, 2),
          all_elements: n3.elements
        }
      else
        nil
      end

      geographic_location = if n4 do
        %{
          segment_id: "N4",
          city: Parser.get_element(n4, 1),
          state: Parser.get_element(n4, 2),
          postal_code: Parser.get_element(n4, 3),
          country_code: Parser.get_element(n4, 4),
          all_elements: n4.elements
        }
      else
        nil
      end

      entity_code = Parser.get_element(nm1_85, 1)
      %{
        segment_id: "NM1",
        entity_id_code: entity_code,
        entity_id_code_desc: entity_code(entity_code),
        entity_type_qualifier: Parser.get_element(nm1_85, 2),
        name_last_or_organization: Parser.get_element(nm1_85, 3),
        name_first: Parser.get_element(nm1_85, 4),
        name_middle: Parser.get_element(nm1_85, 5),
        name_prefix: Parser.get_element(nm1_85, 6),
        name_suffix: Parser.get_element(nm1_85, 7),
        id_code_qualifier: Parser.get_element(nm1_85, 8),
        id_code: Parser.get_element(nm1_85, 9),
        all_elements: nm1_85.elements,
        address: address,
        geographic_location: geographic_location
      }
    else
      nil
    end
  end

  defp extract_subscriber(segments) do
    # Find NM1*IL (subscriber/insured)
    nm1_il = segments
    |> Parser.find_segments("NM1")
    |> Enum.find(fn seg -> Parser.get_element(seg, 1) == "IL" end)

    if nm1_il do
      entity_code = Parser.get_element(nm1_il, 1)
      %{
        segment_id: "NM1",
        entity_id_code: entity_code,
        entity_id_code_desc: entity_code(entity_code),
        entity_type_qualifier: Parser.get_element(nm1_il, 2),
        name_last_or_organization: Parser.get_element(nm1_il, 3),
        name_first: Parser.get_element(nm1_il, 4),
        name_middle: Parser.get_element(nm1_il, 5),
        name_prefix: Parser.get_element(nm1_il, 6),
        name_suffix: Parser.get_element(nm1_il, 7),
        id_code_qualifier: Parser.get_element(nm1_il, 8),
        id_code: Parser.get_element(nm1_il, 9),
        all_elements: nm1_il.elements
      }
    else
      nil
    end
  end

  defp extract_all_segments(segments) do
    Enum.map(segments, fn seg ->
      %{
        segment_id: seg.id,
        elements: seg.elements
      }
    end)
  end

  defp extract_other_entities(segments) do
    # Extract NM1 segments for entities 41 (submitter) and 40 (receiver)
    segments
    |> Parser.find_segments("NM1")
    |> Enum.filter(fn seg ->
      entity_code = Parser.get_element(seg, 1)
      entity_code == "41" or entity_code == "40"
    end)
    |> Enum.map(fn nm1 ->
      entity_code = Parser.get_element(nm1, 1)
      %{
        segment_id: "NM1",
        entity_id_code: entity_code,
        entity_id_code_desc: entity_code(entity_code),
        entity_type_qualifier: Parser.get_element(nm1, 2),
        name_last_or_organization: Parser.get_element(nm1, 3),
        name_first: Parser.get_element(nm1, 4),
        name_middle: Parser.get_element(nm1, 5),
        name_prefix: Parser.get_element(nm1, 6),
        name_suffix: Parser.get_element(nm1, 7),
        id_code_qualifier: Parser.get_element(nm1, 8),
        id_code: Parser.get_element(nm1, 9),
        all_elements: nm1.elements
      }
    end)
  end

  defp extract_contacts(segments) do
    segments
    |> Parser.find_segments("PER")
    |> Enum.map(fn per ->
      %{
        segment_id: "PER",
        contact_function_code: Parser.get_element(per, 1),
        name: Parser.get_element(per, 2),
        communication_number_qualifier_1: Parser.get_element(per, 3),
        communication_number_1: Parser.get_element(per, 4),
        communication_number_qualifier_2: Parser.get_element(per, 5),
        communication_number_2: Parser.get_element(per, 6),
        all_elements: per.elements
      }
    end)
  end

  defp extract_hierarchical_levels(segments) do
    segments
    |> Parser.find_segments("HL")
    |> Enum.map(fn hl ->
      %{
        segment_id: "HL",
        hierarchical_id: Parser.get_element(hl, 1),
        parent_id: Parser.get_element(hl, 2),
        level_code: Parser.get_element(hl, 3),
        child_code: Parser.get_element(hl, 4),
        all_elements: hl.elements
      }
    end)
  end

  defp extract_header_references(segments) do
    # Find REF segments that appear before the first CLM segment (header level)
    clm_index = Enum.find_index(segments, fn seg -> seg.id == "CLM" end)

    header_segments = if clm_index do
      Enum.take(segments, clm_index)
    else
      segments
    end

    header_segments
    |> Enum.filter(fn seg -> seg.id == "REF" end)
    |> Enum.map(fn ref ->
      %{
        segment_id: "REF",
        reference_id_qualifier: Parser.get_element(ref, 1),
        reference_id: Parser.get_element(ref, 2),
        description: Parser.get_element(ref, 3),
        all_elements: ref.elements
      }
    end)
  end

  # ============================================================================
  # BUILDER FUNCTIONS - Reconstruct X12 from JSON (formerly X12.Builder)
  # ============================================================================

  @doc """
  Build X12 content from structured JSON data

  Takes the structured map produced by build_structure/2
  and reconstructs the X12 file content.

  Returns {:ok, x12_content} or {:error, reason}
  """
  def build_from_structure(structured_data, delimiters \\ nil) do
    delimiters = delimiters || %{element: "*", sub_element: ":", segment: "~"}
    try do
      # OPTIMIZATION: If all_segments is available, use it for perfect reconstruction
      # This ensures we don't lose any segments during round-trip
      if all_segments = Map.get(structured_data, :all_segments) || Map.get(structured_data, "all_segments") do
        if is_list(all_segments) and length(all_segments) > 0 do
          # Build from all_segments for perfect reconstruction
          segments_list =
            all_segments
            |> Enum.map(fn seg ->
              elements = Map.get(seg, :elements) || Map.get(seg, "elements") || []
              build_segment_from_elements(elements, delimiters)
            end)

          x12_content = Enum.join(segments_list, delimiters.segment)

          # Add final segment terminator if not already present
          x12_content = if String.ends_with?(x12_content, delimiters.segment) do
            x12_content
          else
            x12_content <> delimiters.segment
          end

          {:ok, x12_content}
        else
          build_from_semantic_structure(structured_data, delimiters)
        end
      else
        build_from_semantic_structure(structured_data, delimiters)
      end
    rescue
      e ->
        {:error, "Failed to build X12: #{Exception.message(e)}"}
    end
  end

  # Build from semantic structure (used when all_segments not available)
  defp build_from_semantic_structure(structured_data, delimiters) do
    try do

      # Fallback: Build from semantic structure (may not include all segments)
      segments = []

      # Build segments in order: ISA, GS, ST, BHT, entities, claims, SE, GE, IEA
      segments = segments ++ build_isa_segment(structured_data.interchange_header, delimiters)
      segments = segments ++ build_gs_segment(structured_data.functional_group, delimiters)
      segments = segments ++ build_st_segment(structured_data.transaction_set, delimiters)

      # Build BHT segment if present
      segments = case get_in(structured_data, [:transaction_set, :beginning_hierarchical_transaction]) do
        nil -> segments
        bht -> segments ++ build_bht_segment(bht, delimiters)
      end

      # Build header references
      segments = segments ++ build_header_references(structured_data.header_references, delimiters)

      # Build hierarchical levels
      segments = segments ++ build_hierarchical_levels(structured_data.hierarchical_levels, delimiters)

      # Build entities (submitter, receiver, billing provider, subscriber)
      segments = segments ++ build_other_entities(structured_data.other_entities, delimiters)

      # Build billing provider if present
      segments = if structured_data.billing_provider do
        segments ++ build_billing_provider(structured_data.billing_provider, delimiters)
      else
        segments
      end

      # Build subscriber if present
      segments = if structured_data.subscriber do
        segments ++ build_subscriber(structured_data.subscriber, delimiters)
      else
        segments
      end

      # Build contacts
      segments = segments ++ build_contacts(structured_data.contacts, delimiters)

      # Build claims
      segments = segments ++ build_claims(structured_data.claims, delimiters)

      # Calculate SE segment count (number of segments from ST to SE, inclusive)
      segment_count = length(segments) - 2 + 2  # Exclude ISA/GS, include ST and SE itself

      # Build trailers
      segments = segments ++ build_se_segment(structured_data.transaction_set, segment_count, delimiters)
      segments = segments ++ build_ge_segment(structured_data.functional_group, delimiters)
      segments = segments ++ build_iea_segment(structured_data.interchange_header, delimiters)

      # Join segments with segment terminator
      x12_content = Enum.join(segments, delimiters.segment)

      # Add final segment terminator if not already present
      x12_content = if String.ends_with?(x12_content, delimiters.segment) do
        x12_content
      else
        x12_content <> delimiters.segment
      end

      {:ok, x12_content}
    rescue
      e ->
        {:error, "Failed to build X12 (semantic): #{Exception.message(e)}"}
    end
  end

  @doc """
  Build X12 content from JSON string

  Parses JSON string and builds X12 content
  """
  def build_from_json(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} ->
        # Convert string keys to atoms for internal processing
        structured_data = atomize_keys(data)

        # Extract delimiters from interchange header
        delimiters = extract_delimiters_from_data(structured_data)

        build_from_structure(structured_data, delimiters)

      {:error, reason} ->
        {:error, "Invalid JSON: #{inspect(reason)}"}
    end
  end

  # Private helper functions for building individual segments

  defp build_isa_segment(nil, _delimiters), do: []
  defp build_isa_segment(isa, delimiters) do
    elements = Map.get(isa, :all_elements) || Map.get(isa, "all_elements") || []

    if length(elements) > 0 do
      [build_segment_from_elements(elements, delimiters)]
    else
      # Fallback: manually construct from individual fields
      [build_segment([
        "ISA",
        Map.get(isa, :authorization_info_qualifier) || Map.get(isa, "authorization_info_qualifier") || "00",
        Map.get(isa, :authorization_info) || Map.get(isa, "authorization_info") || "          ",
        Map.get(isa, :security_info_qualifier) || Map.get(isa, "security_info_qualifier") || "00",
        Map.get(isa, :security_info) || Map.get(isa, "security_info") || "          ",
        Map.get(isa, :sender_id_qualifier) || Map.get(isa, "sender_id_qualifier") || "ZZ",
        Map.get(isa, :sender_id) || Map.get(isa, "sender_id") || "",
        Map.get(isa, :receiver_id_qualifier) || Map.get(isa, "receiver_id_qualifier") || "ZZ",
        Map.get(isa, :receiver_id) || Map.get(isa, "receiver_id") || "",
        Map.get(isa, :interchange_date) || Map.get(isa, "interchange_date") || "",
        Map.get(isa, :interchange_time) || Map.get(isa, "interchange_time") || "",
        Map.get(isa, :standards_id) || Map.get(isa, "standards_id") || "^",
        Map.get(isa, :version_number) || Map.get(isa, "version_number") || "00501",
        Map.get(isa, :interchange_control_number) || Map.get(isa, "interchange_control_number") || "000000001",
        Map.get(isa, :acknowledgment_requested) || Map.get(isa, "acknowledgment_requested") || "0",
        Map.get(isa, :usage_indicator) || Map.get(isa, "usage_indicator") || "P"
      ], delimiters)]
    end
  end

  defp build_gs_segment(nil, _delimiters), do: []
  defp build_gs_segment(gs, delimiters) do
    elements = Map.get(gs, :all_elements) || Map.get(gs, "all_elements") || []

    if length(elements) > 0 do
      [build_segment_from_elements(elements, delimiters)]
    else
      []
    end
  end

  defp build_st_segment(nil, _delimiters), do: []
  defp build_st_segment(st, delimiters) do
    elements = Map.get(st, :all_elements) || Map.get(st, "all_elements") || []

    if length(elements) > 0 do
      [build_segment_from_elements(elements, delimiters)]
    else
      []
    end
  end

  defp build_bht_segment(nil, _delimiters), do: []
  defp build_bht_segment(bht, delimiters) do
    elements = Map.get(bht, :all_elements) || Map.get(bht, "all_elements") || []

    if length(elements) > 0 do
      [build_segment_from_elements(elements, delimiters)]
    else
      []
    end
  end

  defp build_se_segment(st, segment_count, delimiters) do
    # SE segment: SE*count*transaction_control_number~
    transaction_control =
      get_in(st, [:transaction_control_number]) ||
      get_in(st, ["transaction_control_number"]) ||
      "0001"

    [build_segment(["SE", to_string(segment_count), transaction_control], delimiters)]
  end

  defp build_ge_segment(nil, _delimiters), do: []
  defp build_ge_segment(gs, delimiters) do
    # GE segment: GE*1*group_control_number~
    group_control =
      Map.get(gs, :group_control_number) ||
      Map.get(gs, "group_control_number") ||
      "1"

    [build_segment(["GE", "1", group_control], delimiters)]
  end

  defp build_iea_segment(nil, _delimiters), do: []
  defp build_iea_segment(isa, delimiters) do
    # IEA segment: IEA*1*interchange_control_number~
    interchange_control =
      Map.get(isa, :interchange_control_number) ||
      Map.get(isa, "interchange_control_number") ||
      "000000001"

    [build_segment(["IEA", "1", interchange_control], delimiters)]
  end

  defp build_header_references(nil, _delimiters), do: []
  defp build_header_references(refs, delimiters) when is_list(refs) do
    Enum.flat_map(refs, fn ref ->
      elements = Map.get(ref, :all_elements) || Map.get(ref, "all_elements") || []
      if length(elements) > 0 do
        [build_segment_from_elements(elements, delimiters)]
      else
        []
      end
    end)
  end
  defp build_header_references(_, _delimiters), do: []

  defp build_hierarchical_levels(nil, _delimiters), do: []
  defp build_hierarchical_levels(levels, delimiters) when is_list(levels) do
    Enum.flat_map(levels, fn level ->
      elements = Map.get(level, :all_elements) || Map.get(level, "all_elements") || []
      if length(elements) > 0 do
        [build_segment_from_elements(elements, delimiters)]
      else
        []
      end
    end)
  end
  defp build_hierarchical_levels(_, _delimiters), do: []

  defp build_other_entities(nil, _delimiters), do: []
  defp build_other_entities(entities, delimiters) when is_list(entities) do
    Enum.flat_map(entities, fn entity ->
      elements = Map.get(entity, :all_elements) || Map.get(entity, "all_elements") || []
      if length(elements) > 0 do
        [build_segment_from_elements(elements, delimiters)]
      else
        []
      end
    end)
  end
  defp build_other_entities(_, _delimiters), do: []

  defp build_billing_provider(nil, _delimiters), do: []
  defp build_billing_provider(provider, delimiters) do
    segments = []

    # NM1 segment
    elements = Map.get(provider, :all_elements) || Map.get(provider, "all_elements") || []
    segments = if length(elements) > 0 do
      segments ++ [build_segment_from_elements(elements, delimiters)]
    else
      segments
    end

    # N3 segment (address)
    segments = case Map.get(provider, :address) || Map.get(provider, "address") do
      nil -> segments
      address ->
        addr_elements = Map.get(address, :all_elements) || Map.get(address, "all_elements") || []
        if length(addr_elements) > 0 do
          segments ++ [build_segment_from_elements(addr_elements, delimiters)]
        else
          segments
        end
    end

    # N4 segment (geographic location)
    segments = case Map.get(provider, :geographic_location) || Map.get(provider, "geographic_location") do
      nil -> segments
      geo ->
        geo_elements = Map.get(geo, :all_elements) || Map.get(geo, "all_elements") || []
        if length(geo_elements) > 0 do
          segments ++ [build_segment_from_elements(geo_elements, delimiters)]
        else
          segments
        end
    end

    segments
  end

  defp build_subscriber(nil, _delimiters), do: []
  defp build_subscriber(subscriber, delimiters) do
    elements = Map.get(subscriber, :all_elements) || Map.get(subscriber, "all_elements") || []
    if length(elements) > 0 do
      [build_segment_from_elements(elements, delimiters)]
    else
      []
    end
  end

  defp build_contacts(nil, _delimiters), do: []
  defp build_contacts(contacts, delimiters) when is_list(contacts) do
    Enum.flat_map(contacts, fn contact ->
      elements = Map.get(contact, :all_elements) || Map.get(contact, "all_elements") || []
      if length(elements) > 0 do
        [build_segment_from_elements(elements, delimiters)]
      else
        []
      end
    end)
  end
  defp build_contacts(_, _delimiters), do: []

  defp build_claims(nil, _delimiters), do: []
  defp build_claims(claims, delimiters) when is_list(claims) do
    Enum.flat_map(claims, fn claim -> build_claim(claim, delimiters) end)
  end
  defp build_claims(_, _delimiters), do: []

  defp build_claim(claim, delimiters) do
    segments = []

    # CLM segment
    clm_elements = Map.get(claim, :all_elements) || Map.get(claim, "all_elements") || []
    segments = if length(clm_elements) > 0 do
      segments ++ [build_segment_from_elements(clm_elements, delimiters)]
    else
      segments
    end

    # Patient NM1 if present
    segments = case Map.get(claim, :patient) || Map.get(claim, "patient") do
      nil -> segments
      patient ->
        patient_elements = Map.get(patient, :all_elements) || Map.get(patient, "all_elements") || []
        if length(patient_elements) > 0 do
          segments ++ [build_segment_from_elements(patient_elements, delimiters)]
        else
          segments
        end
    end

    # DTP segments (dates)
    dates = Map.get(claim, :dates) || Map.get(claim, "dates") || []
    segments = segments ++ build_dates(dates, delimiters)

    # REF segments (references)
    refs = Map.get(claim, :references) || Map.get(claim, "references") || []
    segments = segments ++ build_references(refs, delimiters)

    # HI segment (diagnosis codes)
    segments = case Map.get(claim, :diagnosis_codes) || Map.get(claim, "diagnosis_codes") do
      nil -> segments
      diag ->
        diag_elements = Map.get(diag, :all_elements) || Map.get(diag, "all_elements") || []
        if length(diag_elements) > 0 do
          segments ++ [build_segment_from_elements(diag_elements, delimiters)]
        else
          segments
        end
    end

    # Service lines
    service_lines = Map.get(claim, :service_lines) || Map.get(claim, "service_lines") || []
    segments = segments ++ build_service_lines(service_lines, delimiters)

    segments
  end

  defp build_dates(nil, _delimiters), do: []
  defp build_dates(dates, delimiters) when is_list(dates) do
    Enum.flat_map(dates, fn date ->
      elements = Map.get(date, :all_elements) || Map.get(date, "all_elements") || []
      if length(elements) > 0 do
        [build_segment_from_elements(elements, delimiters)]
      else
        []
      end
    end)
  end
  defp build_dates(_, _delimiters), do: []

  defp build_references(nil, _delimiters), do: []
  defp build_references(refs, delimiters) when is_list(refs) do
    Enum.flat_map(refs, fn ref ->
      elements = Map.get(ref, :all_elements) || Map.get(ref, "all_elements") || []
      if length(elements) > 0 do
        [build_segment_from_elements(elements, delimiters)]
      else
        []
      end
    end)
  end
  defp build_references(_, _delimiters), do: []

  defp build_service_lines(nil, _delimiters), do: []
  defp build_service_lines(lines, delimiters) when is_list(lines) do
    Enum.flat_map(lines, fn line -> build_service_line(line, delimiters) end)
  end
  defp build_service_lines(_, _delimiters), do: []

  defp build_service_line(line, delimiters) do
    segments = []

    # LX segment if present
    lx_elements = Map.get(line, :all_elements) || Map.get(line, "all_elements") || []
    segments = if length(lx_elements) > 0 do
      segments ++ [build_segment_from_elements(lx_elements, delimiters)]
    else
      segments
    end

    # Service info (SV1/SV2/SV3)
    segments = case Map.get(line, :service_info) || Map.get(line, "service_info") do
      nil -> segments
      service_info ->
        sv_elements = Map.get(service_info, :all_elements) || Map.get(service_info, "all_elements") || []
        if length(sv_elements) > 0 do
          segments ++ [build_segment_from_elements(sv_elements, delimiters)]
        else
          segments
        end
    end

    # DTP segments (dates) for service line
    dates = Map.get(line, :dates) || Map.get(line, "dates") || []
    segments = segments ++ build_dates(dates, delimiters)

    segments
  end

  # Helper: Build segment from list of elements
  defp build_segment(elements, delimiters) do
    Enum.join(elements, delimiters.element)
  end

  # Helper: Build segment from stored all_elements array
  defp build_segment_from_elements(elements, delimiters) when is_list(elements) do
    Enum.join(elements, delimiters.element)
  end

  # Helper: Extract delimiters from structured data
  defp extract_delimiters_from_data(data) do
    # Try to extract from ISA segment all_elements
    isa = Map.get(data, :interchange_header) || Map.get(data, "interchange_header") || %{}

    # Default delimiters
    element_sep = "*"
    sub_element_sep = ":"
    segment_term = "~"

    # Try to detect from ISA if available
    if _isa_elements = Map.get(isa, :all_elements) || Map.get(isa, "all_elements") do
      # ISA segment format: ISA*00*...*...:...~
      # Element separator is position 3 in raw content
      # For now, use defaults (we could enhance this later)
      %{
        element: element_sep,
        sub_element: sub_element_sep,
        segment: segment_term
      }
    else
      %{
        element: element_sep,
        sub_element: sub_element_sep,
        segment: segment_term
      }
    end
  end

  # Helper: Convert string keys to atoms recursively
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value

  # ============================================================
  # Qualifiers: X12 Code and Qualifier Lookups (Nested Module)
  # ============================================================
  # Provides human-readable descriptions for X12 qualifiers and codes.
  # Returns the code itself if no description is found (defensive approach).

  defp entity_code(code) do
    case code do
      "40" -> "Receiver"
      "41" -> "Submitter"
      "71" -> "Attending Physician"
      "72" -> "Operating Physician"
      "77" -> "Service Location"
      "82" -> "Rendering Provider"
      "85" -> "Billing Provider"
      "87" -> "Pay-to Provider"
      "DN" -> "Referring Provider"
      "DQ" -> "Supervising Provider"
      "IL" -> "Insured/Subscriber"
      "P3" -> "Primary Care Provider"
      "PR" -> "Payer"
      "QC" -> "Patient"
      "X3" -> "Dependent"
      _ -> code  # Return code if unknown
    end
  end

  defp date_qualifier(code) do
    case code do
      "096" -> "Discharge Date"
      "097" -> "Discharge Hour"
      "098" -> "Admission Date"
      "291" -> "Statement From Date"
      "292" -> "Statement To Date"
      "304" -> "Last Visit Date"
      "318" -> "Symptom Date"
      "319" -> "Last X-Ray Date"
      "431" -> "Onset of Current Symptoms"
      "435" -> "Admission Date/Hour"
      "439" -> "Accident Date"
      "453" -> "Acute Manifestation Date"
      "454" -> "Initial Treatment Date"
      "455" -> "Last Seen Date"
      "471" -> "Prescription Date"
      "472" -> "Service Date"
      "573" -> "Certification Date"
      "607" -> "Disability From Date"
      "610" -> "Disability Through Date"
      _ -> code
    end
  end

  defp reference_qualifier(code) do
    case code do
      "0B" -> "State License Number"
      "1A" -> "Blue Cross Provider Number"
      "1B" -> "Blue Shield Provider Number"
      "1C" -> "Medicare Provider Number"
      "1D" -> "Medicaid Provider Number"
      "1G" -> "Provider UPIN Number"
      "1H" -> "CHAMPUS Identification Number"
      "1J" -> "Facility ID Number"
      "4A" -> "Investigation Number"
      "6R" -> "Provider Control Number"
      "9A" -> "Repriced Claim Number"
      "9C" -> "Repriced Line Item Reference"
      "D3" -> "Membership Number"
      "D9" -> "Prior Authorization Number"
      "EA" -> "Medical Record Identification Number"
      "EI" -> "Employer ID Number"
      "F5" -> "Medicare Version Code"
      "F8" -> "Original Reference Number"
      "G1" -> "Referral Number"
      "G3" -> "Location Number"
      "LU" -> "Location Number"
      "SY" -> "Social Security Number"
      "X4" -> "Clinical Laboratory Improvement Amendment Number"
      "Y4" -> "Agency Claim Number"
      _ -> code
    end
  end

  defp claim_filing_indicator(code) do
    case code do
      "09" -> "Self Pay"
      "11" -> "Other Non-Federal Programs"
      "12" -> "Preferred Provider Organization (PPO)"
      "13" -> "Point of Service (POS)"
      "14" -> "Exclusive Provider Organization (EPO)"
      "15" -> "Indemnity Insurance"
      "16" -> "Health Maintenance Organization (HMO) Medicare Risk"
      "AM" -> "Automobile Medical"
      "BL" -> "Blue Cross/Blue Shield"
      "CH" -> "CHAMPUS"
      "CI" -> "Commercial Insurance Co."
      "DS" -> "Disability"
      "FI" -> "Federal Employees Program"
      "HM" -> "Health Maintenance Organization"
      "LM" -> "Liability Medical"
      "MA" -> "Medicare Part A"
      "MB" -> "Medicare Part B"
      "MC" -> "Medicaid"
      "OF" -> "Other Federal Program"
      "TV" -> "Title V"
      "VA" -> "Veterans Affairs Plan"
      "WC" -> "Workers Compensation Health Claim"
      "ZZ" -> "Mutually Defined"
      _ -> code
    end
  end

  defp place_of_service(code) do
    case code do
      "01" -> "Pharmacy"
      "02" -> "Telehealth Provided Other than in Patient's Home"
      "10" -> "Telehealth Provided in Patient's Home"
      "11" -> "Office"
      "12" -> "Home"
      "21" -> "Inpatient Hospital"
      "22" -> "On Campus-Outpatient Hospital"
      "23" -> "Emergency Room - Hospital"
      "24" -> "Ambulatory Surgical Center"
      "31" -> "Skilled Nursing Facility"
      "32" -> "Nursing Facility"
      "33" -> "Custodial Care Facility"
      "34" -> "Hospice"
      "41" -> "Ambulance - Land"
      "42" -> "Ambulance - Air or Water"
      "49" -> "Independent Clinic"
      "50" -> "Federally Qualified Health Center"
      "51" -> "Inpatient Psychiatric Facility"
      "52" -> "Psychiatric Facility-Partial Hospitalization"
      "53" -> "Community Mental Health Center"
      "54" -> "Intermediate Care Facility/Individuals with Intellectual Disabilities"
      "55" -> "Residential Substance Abuse Treatment Facility"
      "56" -> "Psychiatric Residential Treatment Center"
      "57" -> "Non-residential Substance Abuse Treatment Facility"
      "60" -> "Mass Immunization Center"
      "61" -> "Comprehensive Inpatient Rehabilitation Facility"
      "62" -> "Comprehensive Outpatient Rehabilitation Facility"
      "65" -> "End-Stage Renal Disease Treatment Facility"
      "71" -> "Public Health Clinic"
      "72" -> "Rural Health Clinic"
      "81" -> "Independent Laboratory"
      "99" -> "Other Place of Service"
      _ -> code
    end
  end
end
