# X12Bridge API Reference

Complete reference for the X12Bridge parsing, conversion, and validation modules.

---

## Table of Contents

- [X12.Parser](#x12parser) - Low-level X12 parsing utilities
- [X12.Converter](#x12converter) - X12 to JSON conversion
- [X12.Validator](#x12validator) - X12 validation framework
- [Conversions](#conversions) - Batch and job management

---

## X12.Parser

Low-level parsing utilities for X12 EDI files. Handles delimiter extraction, segment parsing, and loop identification.

### Data Structures

#### `Delimiters`

```elixir
%Delimiters{
  element: "*",       # Element separator (typically *)
  sub_element: ":",   # Sub-element separator (typically :)
  segment: "~"        # Segment terminator (typically ~)
}
```

#### `Segment`

```elixir
%Segment{
  id: "CLM",                    # Segment identifier
  elements: ["CLM", "123", ...], # All elements including ID
  raw: "CLM*123*150.00~",       # Original raw segment string
  line_number: 42               # Line number in file
}
```

### Core Functions

#### `parse/1`

Parse X12 content and return structured segments.

```elixir
{:ok, %{delimiters: %Delimiters{}, segments: [%Segment{}]}} = Parser.parse(content)
```

**Parameters:**
- `content` - Binary string containing X12 EDI data

**Returns:**
- `{:ok, %{delimiters: delimiters, segments: segments}}` on success
- `{:error, reason}` if parsing fails

---

#### `parse_delimiters/1`

Extract delimiters from ISA segment.

```elixir
{:ok, %Delimiters{}} = Parser.parse_delimiters(content)
```

**Parameters:**
- `content` - Binary string starting with ISA segment

**Returns:**
- `{:ok, %Delimiters{}}` on success
- `{:error, reason}` if ISA segment is invalid or missing

**Notes:**
- Requires minimum 106 bytes for valid ISA segment
- Element separator at position 3
- Sub-element separator at position 104
- Segment terminator at end of ISA line

---

#### `parse_segments/2`

Parse all segments from X12 content using provided delimiters.

```elixir
{:ok, segments} = Parser.parse_segments(content, delimiters)
```

**Parameters:**
- `content` - Binary string containing X12 data
- `delimiters` - `%Delimiters{}` struct

**Returns:**
- `{:ok, [%Segment{}]}` - List of parsed segments

---

#### `get_element/2`

Get element value from segment by position (0-indexed).

```elixir
claim_id = Parser.get_element(segment, 1)
```

**Parameters:**
- `segment` - `%Segment{}` struct or list of elements
- `position` - Integer index (0-based)

**Returns:**
- Element value as string, or empty string if position doesn't exist

**Example:**
```elixir
segment = %Segment{elements: ["CLM", "CLAIM123", "150.00"]}
Parser.get_element(segment, 1)  # => "CLAIM123"
Parser.get_element(segment, 2)  # => "150.00"
Parser.get_element(segment, 99) # => ""
```

---

#### `get_elements/2`

Get multiple elements from segment.

```elixir
[entity_id, entity_type, name] = Parser.get_elements(segment, [1, 2, 3])
```

**Parameters:**
- `segment` - `%Segment{}` struct
- `positions` - List of integer positions

**Returns:**
- List of element values

---

#### `parse_composite/2`

Parse composite element (sub-elements separated by sub-delimiter).

```elixir
["HC", "99213"] = Parser.parse_composite("HC:99213", ":")
```

**Parameters:**
- `element` - String containing composite element
- `sub_delimiter` - Sub-element separator (usually ":")

**Returns:**
- List of sub-element values

---

#### `find_segments/2`

Find all segments with a specific ID.

```elixir
clm_segments = Parser.find_segments(segments, "CLM")
```

**Parameters:**
- `segments` - List of `%Segment{}` structs
- `segment_id` - String segment identifier (e.g., "CLM", "NM1")

**Returns:**
- List of matching segments

---

#### `find_segment/2`

Find first segment with specific ID.

```elixir
isa = Parser.find_segment(segments, "ISA")
```

**Parameters:**
- `segments` - List of `%Segment{}` structs
- `segment_id` - String segment identifier

**Returns:**
- First matching `%Segment{}` or `nil`

---

#### `identify_loops/1`

Group segments into hierarchical loops (837P/I/D specific).

```elixir
loops = Parser.identify_loops(segments)
```

**Parameters:**
- `segments` - List of `%Segment{}` structs

**Returns:**
- List of loop structures with nested service lines

**Loop Structure:**
```elixir
[
  %{
    claim_segment: %Segment{id: "CLM"},
    claim_segments: [%Segment{}, ...],
    service_lines: [
      %{
        line_segment: %Segment{id: "LX"},
        line_segments: [%Segment{}, ...]
      }
    ]
  }
]
```

**Notes:**
- 2300 loop (Claim level) starts with CLM segment
- 2400 loop (Service line level) starts with LX segment
- Automatically nests SV1/SV2/SV3 segments within service lines

---

#### `extract_envelopes/1`

Extract envelope information (ISA, GS, ST headers and trailers).

```elixir
%{isa: isa, gs: gs, st: st, iea: iea, ge: ge, se: se} = Parser.extract_envelopes(segments)
```

**Parameters:**
- `segments` - List of `%Segment{}` structs

**Returns:**
- Map with envelope segments (values may be `nil` if not found)

---

## X12.Converter

Converts X12 837 (Healthcare Claims) EDI files into semantic, hierarchical JSON format.

### Supported Transaction Types

- **837P** - Professional Claims (uses SV1 segments)
- **837I** - Institutional Claims (uses SV2 segments)
- **837D** - Dental Claims (uses SV3 segments)

### Core Functions

#### `convert_file/1`

Convert X12 file to JSON.

```elixir
{:ok, json_string} = Converter.convert_file("path/to/file.x12")
```

**Parameters:**
- `filepath` - Path to X12 file

**Returns:**
- `{:ok, json_string}` - Formatted JSON string
- `{:error, reason}` - Error message

---

#### `convert_content/1`

Convert X12 content string to JSON.

```elixir
{:ok, json_string} = Converter.convert_content(x12_content)
```

**Parameters:**
- `content` - Binary string containing X12 EDI data

**Returns:**
- `{:ok, json_string}` - Formatted JSON (pretty-printed)
- `{:error, reason}` - Error message

---

#### `build_structure/2`

Build structured data from parsed segments.

```elixir
{:ok, structured_data} = Converter.build_structure(segments, delimiters)
```

**Parameters:**
- `segments` - List of `%Segment{}` structs
- `delimiters` - `%Delimiters{}` struct

**Returns:**
- `{:ok, map}` - Structured map ready for JSON encoding

---

### Output JSON Structure

```json
{
  "transaction": {
    "type": "837",
    "control_number": "0001",
    "interchange_control": "000000001",
    "functional_group_control": "1",
    "submitter": { ... },
    "receiver": { ... },
    "primary_billing_provider": { ... }
  },
  "claims": [
    {
      "claim_id": "CLAIM123",
      "total_charge": 150.00,
      "claim_filing_indicator": "MB",
      "subscriber": {
        "entity_identifier": "IL",
        "entity_type": "Person",
        "name": {
          "first": "JOHN",
          "last": "DOE",
          "middle": "Q",
          "full": "JOHN Q DOE"
        },
        "identification": {
          "qualifier": "MI",
          "code": "123456789"
        }
      },
      "patient": { ... },
      "rendering_provider": { ... },
      "dates": [
        {
          "qualifier": "472",
          "qualifier_name": "Service",
          "format": "D8",
          "value": "2024-01-15"
        }
      ],
      "diagnosis_codes": [
        {
          "qualifier": "ABK",
          "code": "M79.3"
        }
      ],
      "service_lines": [
        {
          "service_type": "professional",
          "line_number": "1",
          "procedure": {
            "qualifier": "HC",
            "code": "99213"
          },
          "charge": 75.00,
          "unit_or_basis": "UN",
          "quantity": 1,
          "diagnosis_code_pointers": [1],
          "dates": [ ... ]
        }
      ]
    }
  ],
  "summary": {
    "total_claims": 1,
    "total_service_lines": 2
  }
}
```

### Service Line Types

#### Professional (837P - SV1)
```json
{
  "service_type": "professional",
  "procedure": { "qualifier": "HC", "code": "99213" },
  "charge": 75.00,
  "unit_or_basis": "UN",
  "quantity": 1,
  "diagnosis_code_pointers": [1, 2]
}
```

#### Institutional (837I - SV2)
```json
{
  "service_type": "institutional",
  "revenue_code": "0450",
  "procedure": { "qualifier": "HC", "code": "G0463" },
  "charge": 500.00,
  "unit_or_basis": "UN",
  "quantity": 1
}
```

#### Dental (837D - SV3)
```json
{
  "service_type": "dental",
  "procedure": { "qualifier": "AD", "code": "D0120" },
  "charge": 50.00,
  "place_of_service": "11",
  "oral_cavity_designation": {
    "area": "00",
    "tooth_number": "1",
    "surface": "O"
  },
  "tooth_information": {
    "code_list_qualifier": "JP",
    "tooth_codes": ["1", "2"],
    "tooth_surfaces": ["O", "M"]
  }
}
```

---

## X12.Validator

Comprehensive validation framework for X12 837 files.

### Validation Levels

- **Error** - Must be fixed for valid X12
- **Warning** - Should be reviewed but may be acceptable
- **Info** - Informational messages

### Data Structures

#### `ValidationIssue`

```elixir
%ValidationIssue{
  level: :error | :warning | :info,
  segment_id: "CLM",
  segment_number: 42,
  element_position: 2,
  message: "Claim amount is not a valid number",
  context: "Additional context..."
}
```

#### `ValidationResult`

```elixir
%ValidationResult{
  valid?: true | false,
  issues: [%ValidationIssue{}],
  segment_count: 156
}
```

### Core Functions

#### `validate_file/1`

Validate an X12 file from file path.

```elixir
result = Validator.validate_file("path/to/file.x12")
```

**Parameters:**
- `filepath` - Path to X12 file

**Returns:**
- `%ValidationResult{}` struct

---

#### `validate_content/1`

Validate X12 content string.

```elixir
result = Validator.validate_content(x12_content)
```

**Parameters:**
- `content` - Binary string containing X12 EDI data

**Returns:**
- `%ValidationResult{}` struct

---

### Validation Checks

#### Structural Validation
- ISA segment format and length (minimum 106 bytes)
- Valid segment identifiers
- Sufficient elements per segment
- Recognized segment IDs for 837 transactions

#### Envelope Validation
- ISA/IEA matching control numbers
- GS/GE matching control numbers
- ST/SE matching control numbers
- Transaction set type is "837"
- Correct segment counts in trailers

#### Syntactical Validation
- **NM1 (Name)**: Valid entity codes, entity types, required names
- **CLM (Claim)**: Valid claim amounts (positive numbers)
- **DTP (Date)**: CCYYMMDD format, valid dates, reasonable years
- **HI (Diagnosis)**: Valid qualifiers, non-empty codes
- **SV1/SV2/SV3 (Service Lines)**: Valid charges, positive units/quantities

#### Business Rules Validation
- Required entities present:
  - Billing Provider (NM1*85)
  - Subscriber/Insured (NM1*IL)
  - Claim Information (CLM)
- Claim total matches service line sum (within $0.01 tolerance)

### Example Usage

```elixir
# Validate and check results
result = Validator.validate_content(x12_content)

# Check if valid
if result.valid? do
  IO.puts("X12 file is valid!")
else
  IO.puts("X12 file has errors")
end

# Get summary
summary = ValidationResult.get_summary(result)
# => %{error: 2, warning: 5, info: 1}

# Iterate through issues
Enum.each(result.issues, fn issue ->
  IO.puts("[#{issue.level}] #{issue.segment_id}:#{issue.segment_number} - #{issue.message}")
end)
```

---

## Conversions

Context for managing batches and conversion jobs.

### Data Structures

#### `Batch`

```elixir
%Batch{
  id: UUID,
  name: "Batch 2025-01-01",
  total_files: 10,
  completed_files: 8,
  failed_files: 2,
  status: "completed",
  inserted_at: ~N[2025-01-01 12:00:00],
  jobs: [%Job{}]
}
```

#### `Job`

```elixir
%Job{
  id: UUID,
  batch_id: UUID,
  original_filename: "claim_001.x12",
  file_size: 4096,
  status: "completed",
  json_result: "{...}",
  error_message: nil,
  processing_time_ms: 123,
  progress: 100
}
```

### Functions

#### Batch Management

```elixir
# Create batch
{:ok, batch} = Conversions.create_batch(%{name: "Morning Batch"})

# Get batch with jobs
batch = Conversions.get_batch!(batch_id)

# List recent batches
batches = Conversions.list_batches(limit: 10)

# Update batch
{:ok, batch} = Conversions.update_batch(batch, %{status: "completed"})
```

#### Job Management

```elixir
# Create job
{:ok, job} = Conversions.create_job(%{
  batch_id: batch_id,
  original_filename: "file.x12",
  file_size: 4096,
  status: "pending"
})

# Get job
job = Conversions.get_job!(job_id)

# Update job
{:ok, job} = Conversions.update_job(job, %{
  status: "completed",
  json_result: json_string,
  processing_time_ms: 150
})

# List jobs for batch
jobs = Conversions.list_batch_jobs(batch_id)
```

#### Processing

```elixir
# Process single file
{:ok, result} = Conversions.process_file_sync(content, filename)
# Returns: %{status: "completed", json_result: "...", processing_time_ms: 123}

# Process entire batch
{:ok, batch} = Conversions.process_batch_sync(batch_id, uploaded_files)
# Broadcasts progress updates via PubSub
```

### PubSub Events

The Conversions context broadcasts events for real-time updates:

```elixir
# Subscribe to batch updates
Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch:#{batch_id}")

# Received events:
{:job_completed, job_id, "completed"}
{:batch_completed, batch_id}
```

---

## Complete Example Workflow

```elixir
# 1. Parse X12 file
{:ok, %{delimiters: delimiters, segments: segments}} = X12Bridge.X12.Parser.parse(content)

# 2. Validate
validation_result = X12Bridge.X12.Validator.validate_content(content)

if validation_result.valid? do
  # 3. Convert to JSON
  {:ok, json} = X12Bridge.X12.Converter.convert_content(content)

  # 4. Save to database
  {:ok, batch} = X12Bridge.Conversions.create_batch(%{name: "Batch 1"})
  {:ok, job} = X12Bridge.Conversions.create_job(%{
    batch_id: batch.id,
    original_filename: "claim.x12",
    status: "completed",
    json_result: json
  })

  IO.puts("Conversion successful!")
else
  # Handle errors
  Enum.each(validation_result.issues, fn issue ->
    if issue.level == :error do
      IO.puts("[ERROR] #{issue.message}")
    end
  end)
end
```

---

## Error Handling

All parsing and conversion functions return tuples:

```elixir
# Success
{:ok, result}

# Failure
{:error, reason}
```

Common error reasons:
- `"File too short to contain valid ISA segment"`
- `"File must start with ISA segment"`
- `"File not found: ..."`
- `"Conversion failed: ..."`

Always pattern match on results:

```elixir
case Converter.convert_file(path) do
  {:ok, json} ->
    # Success handling
  {:error, reason} ->
    # Error handling
end
```

---

## Performance Considerations

- **Large files**: For files > 1MB, consider chunking or streaming
- **Batch processing**: Use `BatchProcessor` for multiple files
- **Concurrent processing**: BatchProcessor uses `Task.async_stream` with configurable concurrency
- **Memory**: Parser loads entire file into memory - monitor for very large files

---

## Additional Resources

- [X12 837P Implementation Guide](https://www.cms.gov/regulations-and-guidance/administrative-simplification/hipaa-aba/downloads/claims837p.pdf)
- [HIPAA X12 Standards](https://x12.org/)
- Project README and architecture docs

---

**Version:** 1.0
**Last Updated:** January 2025
