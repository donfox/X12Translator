# Remote Batch Test Data

This directory contains test ZIP files for testing the Remote Import functionality.

## Test Files

### test_batch_3files.zip
- **Contents**: 3 X12 files (837P, 837I, 837D)
- **Purpose**: Standard remote batch import test
- **Expected**: Successful import of all 3 files

### test_batch_with_manifest.zip
- **Contents**: 2 X12 files (837P, 837I) + manifest.json
- **Purpose**: Test ZIP with optional manifest file
- **Expected**: Successful import of 2 files, manifest loaded

### test_batch_invalid.zip
- **Contents**: Non-X12 files (document.txt, readme.md)
- **Purpose**: Test error handling for invalid file types
- **Expected**: Error `:no_x12_files`

## Usage in Tests

These files can be used with the `file://` protocol for local testing:

```elixir
url = "file:///Users/donfox1/Work/X12Bridge/priv/test_data/remote_batches/test_batch_3files.zip"
RemoteFetcher.fetch_and_extract(url)
```

Or hosted on a web server for HTTP testing:

```bash
# Start a simple HTTP server in this directory
python3 -m http.server 8000

# Access via: http://localhost:8000/test_batch_3files.zip
```

## Creating Additional Test Files

To create more test batches:

```bash
cd priv/test_data/remote_batches

# Create temporary directory with X12 files
mkdir temp
cp ../single/*.x12 temp/

# Create ZIP
zip -j my_test_batch.zip temp/*.x12

# Cleanup
rm -rf temp
```
