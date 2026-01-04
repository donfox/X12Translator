# X12Bridge Test Data

This directory contains test data for X12 EDI file processing.

## Directory Structure

```
test_data/
├── single/              # Single file samples for UI testing
│   ├── sample_837p.x12  # Professional claim sample
│   ├── sample_837i.x12  # Institutional claim sample
│   └── sample_837d.x12  # Dental claim sample
│
└── batches/             # Batch processing test data
    ├── batch_quick/          # 5 files - Quick smoke tests
    ├── batch_realistic/      # 25 files - Realistic user scenario
    ├── batch_performance/    # 100 files - Performance testing
    └── batch_edge_cases/     # Error conditions and edge cases
```

## Generating Batch Data

Use the Mix task to generate batch test data:

```bash
# Generate specific batch
mix gen_batch_data quick
mix gen_batch_data realistic
mix gen_batch_data performance
mix gen_batch_data edge_cases

# Generate all batches
mix gen_batch_data all
```

## Batch Descriptions

### batch_quick (5 files)
- **Purpose:** Quick smoke tests, CI/CD pipeline
- **Files:** 3 valid (837P, 837I, 837D), 1 multi-claim, 1 error
- **Use case:** Fast validation during development

### batch_realistic (25 files)
- **Purpose:** Simulates typical user workflow
- **Distribution:** 60% 837P, 30% 837I, 10% 837D
- **Use case:** Integration testing, user acceptance

### batch_performance (100 files)
- **Purpose:** Stress testing, concurrency validation
- **Distribution:** Even mix of all types
- **Use case:** Performance benchmarking, load testing

### batch_edge_cases (4+ files)
- **Purpose:** Error handling validation
- **Files:** Invalid delimiters, missing segments, corrupt data
- **Use case:** Error handling, validation testing

## Manifest Files

Each batch includes a `manifest.json` with metadata:

```json
{
  "batch_id": "batch_quick_001",
  "description": "Quick batch for smoke tests",
  "total_files": 5,
  "files": [
    {
      "filename": "001_837p_valid.x12",
      "type": "837P",
      "expected_status": "success",
      "expected_claims": 1,
      "description": "Valid professional claim"
    }
  ]
}
```

## File Naming Convention

```
{sequence}_{type}_{description}.x12

Examples:
001_837p_valid.x12       - Valid 837P single claim
002_837i_multi.x12       - 837I with multiple claims
003_837d_error.x12       - 837D with validation errors
```

## Usage in Tests

```elixir
# Load batch data in tests
alias X12Bridge.TestSupport.BatchLoader

{:ok, batch} = BatchLoader.load_batch("batch_quick")

Enum.each(batch.files, fn file ->
  # Process file
  result = X12Bridge.X12.Converter.convert_content(file.content)

  # Assert against expected values
  assert file.expected_status == get_status(result)
end)
```

## Updating Test Data

When updating test data:

1. **Single files:** Manually edit files in `single/` directory
2. **Batch files:** Regenerate using `mix gen_batch_data`
3. **Custom batches:** Create new directory and manifest manually

## Notes

- All files use realistic X12 837 format
- Sample data based on HIPAA 5010 implementation guides
- Error files are intentionally malformed for testing
- Batch files have unique control numbers to avoid conflicts
