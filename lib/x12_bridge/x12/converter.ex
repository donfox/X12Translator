defmodule X12Bridge.X12.Converter do
  @moduledoc """
  X12 to JSON Converter

  Converts X12 837 (Healthcare Claims) EDI files into semantic,
  hierarchical JSON format.

  Supports:
  - 837P (Professional Claims) - uses SV1 segments
  - 837I (Institutional Claims) - uses SV2 segments
  - 837D (Dental Claims) - uses SV3 segments

  The output structure organizes claims with nested service lines,
  making the data easier to work with for developers.
  """

  alias X12Bridge.X12.Parser
  alias X12Bridge.X12.Parser.Segment

  @doc """
  Convert X12 file to JSON

  ## Examples

      iex> Converter.convert_file("sample.x12")
      {:ok, json_string}
  """
  def convert_file(filepath) do
    case File.read(filepath) do
      {:ok, content} ->
        convert_content(content)

      {:error, :enoent} ->
        {:error, "File not found: #{filepath}"}

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  @doc """
  Convert X12 content string to JSON

  Returns {:ok, json_string} or {:error, reason}
  """
  def convert_content(content) when is_binary(content) do
    with {:ok, %{delimiters: delimiters, segments: segments}} <- Parser.parse(content),
         {:ok, structured_data} <- build_structure(segments, delimiters) do
      Jason.encode(structured_data, pretty: true)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Build structured data from parsed segments
  """
  def build_structure(segments, delimiters) when is_list(segments) do
    envelopes = Parser.extract_envelopes(segments)
    loops = Parser.identify_loops(segments)

    # Extract file info
    file_info = extract_file_info(envelopes)

    # Extract envelope details
    interchange_header = extract_interchange_header(envelopes.isa)
    functional_group = extract_functional_group(envelopes.gs)
    transaction_set = extract_transaction_set(envelopes.st, segments)

    # Extract entities
    billing_provider = extract_billing_provider(segments)
    subscriber = extract_subscriber(segments)

    # Extract claims
    claims = Enum.map(loops, &extract_claim(&1, delimiters))

    # Extract flat segments list
    all_segments = extract_all_segments(segments)

    # Extract groupings
    other_entities = extract_other_entities(segments)
    contacts = extract_contacts(segments)
    hierarchical_levels = extract_hierarchical_levels(segments)
    header_references = extract_header_references(segments)

    # Calculate summary
    total_service_lines = Enum.reduce(claims, 0, fn claim, acc ->
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
      summary: %{
        total_segments: length(segments),
        total_claims: length(claims),
        total_service_lines: total_service_lines
      }
    }

    {:ok, structured}
  end

  # Extract transaction-level information
  defp extract_transaction_info(segments, envelopes) do
    st_segment = envelopes.st
    isa_segment = envelopes.isa
    gs_segment = envelopes.gs

    # Find submitter and receiver
    submitter = find_entity(segments, "41")
    receiver = find_entity(segments, "40")
    billing_provider = find_entity(segments, "85")

    %{
      type: if(st_segment, do: Parser.get_element(st_segment, 1), else: "837"),
      control_number: if(st_segment, do: Parser.get_element(st_segment, 2), else: ""),
      interchange_control: if(isa_segment, do: Parser.get_element(isa_segment, 13), else: ""),
      functional_group_control: if(gs_segment, do: Parser.get_element(gs_segment, 6), else: ""),
      submitter: submitter,
      receiver: receiver,
      primary_billing_provider: billing_provider
    }
  end

  # Extract claim information from a loop
  defp extract_claim(%{claim_segment: clm_segment, claim_segments: claim_segs, service_lines: service_lines}, delimiters) do
    # Extract basic claim info from CLM segment
    claim_id = Parser.get_element(clm_segment, 1)
    total_charge = Parser.get_element(clm_segment, 2)
    claim_filing_code = Parser.get_element(clm_segment, 5)

    # Find related segments
    patient_nm1 = find_entity_in_segments(claim_segs, "QC")

    # Extract dates with full structure
    dates = claim_segs
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

    # Extract references with full structure
    references = claim_segs
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
    patient = if patient_nm1 do
      %{
        segment_id: "NM1",
        entity_id_code: Parser.get_element(patient_nm1, 1),
        entity_type_qualifier: Parser.get_element(patient_nm1, 2),
        name_last_or_organization: Parser.get_element(patient_nm1, 3),
        name_first: Parser.get_element(patient_nm1, 4),
        name_middle: Parser.get_element(patient_nm1, 5),
        name_prefix: Parser.get_element(patient_nm1, 6),
        name_suffix: Parser.get_element(patient_nm1, 7),
        id_code_qualifier: Parser.get_element(patient_nm1, 8),
        id_code: Parser.get_element(patient_nm1, 9),
        all_elements: patient_nm1.elements
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
        %{
          line_number: Parser.get_element(lx_segment, 1),
          error: "SV1, SV2, or SV3 segment not found for service line"
        }
    end
  end

  # Extract professional service line (837P - SV1)
  defp extract_professional_service_line(lx_segment, sv1, line_segs, delimiters) do
    # Extract procedure code (composite element)
    procedure_composite = Parser.get_element(sv1, 1)
    procedure_parts = Parser.parse_composite(procedure_composite, delimiters.sub_element)

    procedure_qualifier = Enum.at(procedure_parts, 0, "")
    procedure_code = Enum.at(procedure_parts, 1, "")

    # Extract other elements
    line_charge = Parser.get_element(sv1, 2)
    unit_type = Parser.get_element(sv1, 3)
    quantity = Parser.get_element(sv1, 4)
    diagnosis_pointer = Parser.get_element(sv1, 7)

    %{
      segment_id: "LX",
      line_number: Parser.get_element(lx_segment, 1),
      all_elements: lx_segment.elements,
      service_info: %{
        segment_id: "SV1",
        procedure_info: procedure_composite,
        line_charge: line_charge,
        unit_basis: unit_type,
        unit_count: quantity,
        place_of_service: Parser.get_element(sv1, 5),
        diagnosis_pointer: diagnosis_pointer,
        all_elements: sv1.elements
      }
    }
  end

  # Extract institutional service line (837I - SV2)
  defp extract_institutional_service_line(lx_segment, sv2, _line_segs, _delimiters) do
    %{
      segment_id: "LX",
      line_number: Parser.get_element(lx_segment, 1),
      all_elements: lx_segment.elements
    }
  end

  # Extract dental service line (837D - SV3)
  defp extract_dental_service_line(lx_segment, sv3, _line_segs, _delimiters) do
    %{
      segment_id: "LX",
      line_number: Parser.get_element(lx_segment, 1),
      all_elements: lx_segment.elements
    }
  end

  # Find entity (NM1) by entity identifier code
  defp find_entity(segments, entity_code) when is_list(segments) do
    segments
    |> Parser.find_segments("NM1")
    |> Enum.find(fn seg -> Parser.get_element(seg, 1) == entity_code end)
    |> extract_entity()
  end

  defp find_entity_in_segments(segments, entity_code) do
    segments
    |> Enum.filter(fn seg -> seg.id == "NM1" end)
    |> Enum.find(fn seg -> Parser.get_element(seg, 1) == entity_code end)
    |> extract_entity()
  end

  # Extract entity details from NM1 segment
  defp extract_entity(nil), do: nil

  defp extract_entity(%Segment{} = nm1) do
    entity_code = Parser.get_element(nm1, 1)
    entity_type = Parser.get_element(nm1, 2)
    last_name = Parser.get_element(nm1, 3)
    first_name = Parser.get_element(nm1, 4)
    middle_name = Parser.get_element(nm1, 5)
    id_qualifier = Parser.get_element(nm1, 8)
    id_code = Parser.get_element(nm1, 9)

    %{
      entity_identifier: entity_code,
      entity_type: entity_type_name(entity_type),
      name: build_name(entity_type, last_name, first_name, middle_name),
      identification: %{
        qualifier: id_qualifier,
        code: id_code
      }
    }
  end

  # Build name based on entity type (person vs organization)
  defp build_name("1", last_name, first_name, middle_name) do
    # Person
    %{
      last: last_name,
      first: first_name,
      middle: middle_name,
      full: Enum.join([first_name, middle_name, last_name], " ") |> String.trim()
    }
  end

  defp build_name("2", organization_name, _, _) do
    # Non-person entity (organization)
    %{
      organization: organization_name
    }
  end

  defp build_name(_, name, _, _), do: %{raw: name}

  defp entity_type_name("1"), do: "Person"
  defp entity_type_name("2"), do: "Non-Person Entity"
  defp entity_type_name(_), do: "Unknown"

  # Extract dates from DTP segments
  defp extract_dates(segments) do
    segments
    |> Enum.filter(fn seg -> seg.id == "DTP" end)
    |> Enum.map(fn dtp ->
      date_qualifier = Parser.get_element(dtp, 1)
      date_format = Parser.get_element(dtp, 2)
      date_value = Parser.get_element(dtp, 3)

      %{
        qualifier: date_qualifier,
        qualifier_name: date_qualifier_name(date_qualifier),
        format: date_format,
        value: format_date(date_value, date_format)
      }
    end)
  end

  # Extract diagnosis codes from HI segments
  defp extract_diagnosis_codes(segments, delimiters) do
    segments
    |> Enum.filter(fn seg -> seg.id == "HI" end)
    |> Enum.flat_map(fn hi ->
      hi.elements
      |> Enum.drop(1)
      |> Enum.map(fn element ->
        parts = Parser.parse_composite(element, delimiters.sub_element)
        qualifier = Enum.at(parts, 0, "")
        code = Enum.at(parts, 1, "")

        %{
          qualifier: qualifier,
          code: code
        }
      end)
    end)
  end

  # Date qualifier names (common ones)
  defp date_qualifier_name("431"), do: "Onset of Current Symptoms"
  defp date_qualifier_name("454"), do: "Initial Treatment"
  defp date_qualifier_name("304"), do: "Latest Visit or Consultation"
  defp date_qualifier_name("453"), do: "Acute Manifestation"
  defp date_qualifier_name("439"), do: "Accident"
  defp date_qualifier_name("455"), do: "Last X-Ray"
  defp date_qualifier_name("471"), do: "Prescription"
  defp date_qualifier_name("472"), do: "Service"
  defp date_qualifier_name("096"), do: "Discharge"
  defp date_qualifier_name("434"), do: "Statement"
  defp date_qualifier_name(_), do: "Other"

  # Format date from CCYYMMDD to YYYY-MM-DD
  defp format_date(date_string, "D8") when byte_size(date_string) == 8 do
    year = String.slice(date_string, 0, 4)
    month = String.slice(date_string, 4, 2)
    day = String.slice(date_string, 6, 2)
    "#{year}-#{month}-#{day}"
  end

  defp format_date(date_string, _), do: date_string

  # Parse amount to float
  defp parse_amount(""), do: nil
  defp parse_amount(nil), do: nil

  defp parse_amount(amount_string) when is_binary(amount_string) do
    case Float.parse(amount_string) do
      {amount, _} -> amount
      :error -> amount_string
    end
  end

  # Parse number (could be int or float)
  defp parse_number(""), do: nil
  defp parse_number(nil), do: nil

  defp parse_number(num_string) when is_binary(num_string) do
    cond do
      String.contains?(num_string, ".") ->
        case Float.parse(num_string) do
          {num, _} -> num
          :error -> num_string
        end

      true ->
        case Integer.parse(num_string) do
          {num, _} -> num
          :error -> num_string
        end
    end
  end

  # Parse diagnosis code pointers (e.g., "1:2:3" -> [1, 2, 3])
  defp parse_diagnosis_pointers(""), do: []
  defp parse_diagnosis_pointers(nil), do: []

  defp parse_diagnosis_pointers(pointer_string) when is_binary(pointer_string) do
    pointer_string
    |> String.split(":")
    |> Enum.map(fn p ->
      case Integer.parse(p) do
        {num, _} -> num
        :error -> p
      end
    end)
  end

  # NEW EXTRACTION FUNCTIONS

  defp extract_file_info(envelopes) do
    st = envelopes.st
    gs = envelopes.gs

    transaction_type = if st, do: Parser.get_element(st, 1), else: "837"
    version = if gs, do: Parser.get_element(gs, 8), else: ""

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
      file_type: file_type
    }
  end

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
      # Find associated address segments after this NM1
      nm1_index = Enum.find_index(segments, fn seg -> seg == nm1_85 end)
      following_segments = Enum.drop(segments, nm1_index + 1)

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

      %{
        segment_id: "NM1",
        entity_id_code: Parser.get_element(nm1_85, 1),
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
      %{
        segment_id: "NM1",
        entity_id_code: Parser.get_element(nm1_il, 1),
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
      %{
        segment_id: "NM1",
        entity_id_code: Parser.get_element(nm1, 1),
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
end
