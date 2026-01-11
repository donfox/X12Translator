# Real X12 Data Archives

This directory stores large batches of real X12 EDI files in ZIP format, primarily sourced from production systems like Databricks.

## Purpose

- **Storage**: Keep large collections of real X12 data organized and compressed
- **Testing**: Use for integration tests, batch processing validation, and edge case discovery
- **Documentation**: Track provenance of real-world data samples

## Directory Structure

```
archives/
├── README.md (this file)
├── databricks_batch_YYYY-MM-DD.zip
├── production_sample_YYYY-MM-DD.zip
└── [other ZIP archives...]
```

## Usage

### 1. Uploading ZIP Archives via Web Interface

Use the **Remote Import** feature in the batch processing UI:

1. Navigate to the batch processing page
2. Click "Remote Import" tab
3. Paste Databricks file path or URL
4. System will:
   - Download the ZIP file
   - Extract X12 files
   - Process each file to JSON
   - Display results in real-time

### 2. Manual Testing with Archives

Extract and process files from command line:

```bash
# Extract ZIP
unzip test/fixtures/x12/manual_test_data/archives/databricks_batch_2026-01-09.zip -d /tmp/test_batch

# Process with iex
iex -S mix
iex> X12Bridge.BatchProcessor.process_directory("/tmp/test_batch")
```

### 3. Automated Testing

Load archives in ExUnit tests:

```elixir
test "processes large batch from archive" do
  archive_path = "test/fixtures/x12/manual_test_data/archives/databricks_batch_2026-01-09.zip"

  # Extract to temp directory
  {:ok, files} = :zip.unzip(archive_path, [{:cwd, '/tmp/test'}])

  # Process batch
  result = BatchProcessor.process_directory("/tmp/test")

  assert result.total_files > 0
  assert result.successful_files > 0
end
```

## Naming Convention

Use descriptive names that include:
- **Source**: Where the data came from (databricks, production, qa)
- **Date**: When the archive was created (YYYY-MM-DD)
- **Optional descriptor**: Type or purpose (claims, eligibility, mixed)

Examples:
- `databricks_batch_2026-01-09.zip` (Databricks export from Jan 9, 2026)
- `production_837p_2026-01-15.zip` (Production 837P claims from Jan 15)
- `qa_mixed_transactions_2026-01-20.zip` (QA environment mixed types)

## Data Source Attribution

### Databricks Exports
- **Source**: Databricks production database
- **Method**: Export via file path (e.g., `/mnt/data/x12/export_*.txt`)
- **Format**: X12 EDI files (837P, 837I, 837D)
- **Version**: Primarily 005010
- **Privacy**: Anonymized/de-identified data only

### Production Samples
- **Source**: Live production system extracts
- **Method**: Controlled sampling from processing pipeline
- **Privacy**: Must be fully anonymized before archiving

## Important Notes

### Privacy and Security
- ⚠️ **NEVER** commit archives containing real PHI (Protected Health Information)
- All data must be anonymized/de-identified before storage
- Add `*.zip` to `.gitignore` if archives contain sensitive data
- Use secure transfer methods for production data

### File Size Considerations
- Large ZIP files (>10MB) should NOT be committed to git
- Store large archives externally (S3, cloud storage) with references here
- Consider using Git LFS for medium-sized archives (1-10MB)

### Real vs Synthetic Data
- Files in this directory contain **real X12 structure** from production systems
- These differ from `test/fixtures/x12/unit/` which has synthetic test data
- Real data includes:
  - Production formatting (single-line, no pretty-printing)
  - Real-world edge cases and variations
  - Complex nested loop structures
  - Actual payer/provider patterns (anonymized)

## Adding New Archives

When adding a new ZIP archive:

1. **Verify Privacy**: Ensure all PHI is removed/anonymized
2. **Name Consistently**: Follow naming convention above
3. **Document Below**: Add entry to the archive inventory

## Archive Inventory

| Filename | Date Added | Source | File Count | Description |
|----------|------------|--------|------------|-------------|
| _(empty - add entries as archives are added)_ | | | | |

---

**Last Updated**: 2026-01-10
**Maintained By**: X12Bridge Development Team
