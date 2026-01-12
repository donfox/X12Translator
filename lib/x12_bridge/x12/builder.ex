defmodule X12Bridge.X12.Builder do
  @moduledoc """
  X12 Builder - Reconstructs X12 EDI from JSON

  Takes the structured JSON output from Converter and rebuilds
  the original X12 file format. Used for round-trip validation
  to ensure no data loss during conversion.

  The goal is to produce an X12 file that, when normalized for
  whitespace, matches the original input exactly.
  """

  alias X12Bridge.X12.Parser

  @doc """
  Build X12 content from structured JSON data

  Takes the structured map produced by Converter.build_structure/2
  and reconstructs the X12 file content.

  Returns {:ok, x12_content} or {:error, reason}
  """
  def build_from_structure(structured_data, delimiters \\ %Parser.Delimiters{
    element: "*",
    sub_element: ":",
    segment: "~"
  }) do
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
      %Parser.Delimiters{
        element: element_sep,
        sub_element: sub_element_sep,
        segment: segment_term
      }
    else
      %Parser.Delimiters{
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
end
