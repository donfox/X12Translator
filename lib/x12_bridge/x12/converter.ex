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

    transaction_info = extract_transaction_info(segments, envelopes)
    claims = Enum.map(loops, &extract_claim(&1, delimiters))

    structured = %{
      transaction: transaction_info,
      claims: claims,
      summary: %{
        total_claims: length(claims),
        total_service_lines: Enum.reduce(claims, 0, fn claim, acc ->
          acc + length(Map.get(claim, :service_lines, []))
        end)
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
    subscriber = find_entity_in_segments(claim_segs, "IL")
    patient = find_entity_in_segments(claim_segs, "QC")
    rendering_provider = find_entity_in_segments(claim_segs, "82")

    # Extract dates
    dates = extract_dates(claim_segs)

    # Extract diagnosis codes
    diagnosis_codes = extract_diagnosis_codes(claim_segs, delimiters)

    # Extract service lines
    service_lines_data = Enum.map(service_lines, &extract_service_line(&1, delimiters))

    %{
      claim_id: claim_id,
      total_charge: parse_amount(total_charge),
      claim_filing_indicator: claim_filing_code,
      subscriber: subscriber,
      patient: patient,
      rendering_provider: rendering_provider,
      dates: dates,
      diagnosis_codes: diagnosis_codes,
      service_lines: service_lines_data
    }
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

    # Extract line-level dates
    dates = extract_dates(line_segs)

    %{
      service_type: "professional",
      line_number: Parser.get_element(lx_segment, 1),
      procedure: %{
        qualifier: procedure_qualifier,
        code: procedure_code
      },
      charge: parse_amount(line_charge),
      unit_or_basis: unit_type,
      quantity: parse_number(quantity),
      diagnosis_code_pointers: parse_diagnosis_pointers(diagnosis_pointer),
      dates: dates
    }
  end

  # Extract institutional service line (837I - SV2)
  defp extract_institutional_service_line(lx_segment, sv2, line_segs, delimiters) do
    # SV2 structure: SV201 (revenue code), SV202 (procedure code composite), SV203 (line charge), SV204 (unit), SV205 (quantity)
    revenue_code = Parser.get_element(sv2, 1)

    # Extract procedure code (composite element)
    procedure_composite = Parser.get_element(sv2, 2)
    procedure_parts = Parser.parse_composite(procedure_composite, delimiters.sub_element)

    procedure_qualifier = Enum.at(procedure_parts, 0, "")
    procedure_code = Enum.at(procedure_parts, 1, "")

    # Extract other elements
    line_charge = Parser.get_element(sv2, 3)
    unit_type = Parser.get_element(sv2, 4)
    quantity = Parser.get_element(sv2, 5)

    # Extract line-level dates
    dates = extract_dates(line_segs)

    %{
      service_type: "institutional",
      line_number: Parser.get_element(lx_segment, 1),
      revenue_code: revenue_code,
      procedure: %{
        qualifier: procedure_qualifier,
        code: procedure_code
      },
      charge: parse_amount(line_charge),
      unit_or_basis: unit_type,
      quantity: parse_number(quantity),
      dates: dates
    }
  end

  # Extract dental service line (837D - SV3)
  defp extract_dental_service_line(lx_segment, sv3, line_segs, delimiters) do
    # SV3 structure: SV301 (procedure code composite), SV302 (line charge), SV303 (place of service),
    # SV304 (oral cavity designation composite), SV305 (prosthesis/crown/inlay code)

    # Extract procedure code (composite element)
    procedure_composite = Parser.get_element(sv3, 1)
    procedure_parts = Parser.parse_composite(procedure_composite, delimiters.sub_element)

    procedure_qualifier = Enum.at(procedure_parts, 0, "")
    procedure_code = Enum.at(procedure_parts, 1, "")

    # Extract other elements
    line_charge = Parser.get_element(sv3, 2)
    place_of_service = Parser.get_element(sv3, 3)

    # Extract oral cavity designation (tooth numbers/surfaces)
    oral_cavity_composite = Parser.get_element(sv3, 4)
    oral_cavity_parts = Parser.parse_composite(oral_cavity_composite, delimiters.sub_element)

    # Extract prosthesis/crown/inlay code
    prosthesis_code = Parser.get_element(sv3, 5)

    # Extract quantity (typically number of teeth or procedures)
    quantity = Parser.get_element(sv3, 6)

    # Extract line-level dates
    dates = extract_dates(line_segs)

    # Extract tooth number/surface from TOO segment if present
    too_segment = Enum.find(line_segs, fn seg -> seg.id == "TOO" end)
    tooth_info = if too_segment, do: extract_tooth_information(too_segment, delimiters), else: nil

    %{
      service_type: "dental",
      line_number: Parser.get_element(lx_segment, 1),
      procedure: %{
        qualifier: procedure_qualifier,
        code: procedure_code
      },
      charge: parse_amount(line_charge),
      place_of_service: place_of_service,
      oral_cavity_designation: %{
        area: Enum.at(oral_cavity_parts, 0, ""),
        tooth_number: Enum.at(oral_cavity_parts, 1, ""),
        surface: Enum.at(oral_cavity_parts, 2, "")
      },
      prosthesis_crown_inlay: prosthesis_code,
      quantity: parse_number(quantity),
      tooth_information: tooth_info,
      dates: dates
    }
  end

  # Extract tooth information from TOO segment (Tooth Information)
  defp extract_tooth_information(too_segment, delimiters) do
    # TOO01: Code list qualifier code
    code_list_qualifier = Parser.get_element(too_segment, 1)

    # TOO02: Tooth code (composite - can have multiple tooth numbers)
    tooth_code_composite = Parser.get_element(too_segment, 2)
    tooth_codes = Parser.parse_composite(tooth_code_composite, delimiters.sub_element)

    # TOO03: Tooth surface (composite)
    surface_composite = Parser.get_element(too_segment, 3)
    surfaces = Parser.parse_composite(surface_composite, delimiters.sub_element)

    %{
      code_list_qualifier: code_list_qualifier,
      tooth_codes: tooth_codes,
      tooth_surfaces: surfaces
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
end
