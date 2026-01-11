# Remote Import - Multiple Source Support

The Remote Import feature in X12Bridge allows you to fetch and process X12 batch files from multiple sources without drag-and-drop upload.

## Supported Sources

### 1. HTTP/HTTPS URLs
Fetch files from any publicly accessible web server.

**Examples:**
```
https://example.com/batches/claims_2026-01.zip
http://localhost:8000/test_batch.zip
```

**Use cases:**
- Public file sharing services
- Internal web servers
- Testing with local HTTP server (see below)

### 2. Local File Paths
Read ZIP files directly from your local filesystem.

**Examples:**
```
# Absolute paths (Mac/Linux)
/Users/yourname/Downloads/batch.zip
/tmp/x12_files/production_batch.zip

# Absolute paths (Windows)
C:\Users\yourname\Downloads\batch.zip
D:\data\x12\batch.zip

# Relative paths (from project root)
test/fixtures/manual_test_data/databricks_sample_2026-01-09.zip
priv/batches/import.zip
```

**Use cases:**
- Processing files from local directories
- Importing previously downloaded batches
- Development and testing

### 3. Databricks Paths
Fetch files directly from Databricks File System (DBFS).

**Examples:**
```
/mnt/data/x12/export_2026-01-09.zip
/mnt/production/claims/batch_123.zip
dbfs:/FileStore/x12_batches/monthly_export.zip
```

**Requirements:**
- Databricks workspace credentials must be configured (see Configuration below)

**Use cases:**
- Direct import from Databricks data pipelines
- Processing files stored in cloud storage mounted to DBFS
- Automated batch workflows

## Configuration

### Databricks Integration

To enable Databricks file import, you need to configure your Databricks workspace credentials.

#### Step 1: Generate Databricks Personal Access Token

1. Log into your Databricks workspace
2. Click your username in the top-right corner → **User Settings**
3. Go to **Access Tokens** tab
4. Click **Generate New Token**
5. Give it a name (e.g., "X12Bridge Import") and set expiration
6. Copy the token immediately (you won't see it again!)

#### Step 2: Find Your Databricks Host

Your Databricks host is the domain of your workspace URL:

- **AWS**: `https://<workspace-name>.cloud.databricks.com` → Host is `<workspace-name>.cloud.databricks.com`
- **Azure**: `https://adb-<workspace-id>.<random-number>.azuredatabricks.net` → Host is `adb-<workspace-id>.<random-number>.azuredatabricks.net`
- **GCP**: `https://<workspace-id>.gcp.databricks.com` → Host is `<workspace-id>.gcp.databricks.com`

**Example:**
If your workspace URL is `https://my-company.cloud.databricks.com`, your host is `my-company.cloud.databricks.com` (without `https://`)

#### Step 3: Configure Environment Variables

Add these environment variables to your system or `.env` file:

```bash
export DATABRICKS_HOST="your-workspace.cloud.databricks.com"
export DATABRICKS_TOKEN="dapi1234567890abcdef..."
```

**For development**, you can add them to `config/runtime.exs`:

```elixir
config :x12_bridge, :databricks,
  host: System.get_env("DATABRICKS_HOST"),
  token: System.get_env("DATABRICKS_TOKEN")
```

#### Step 4: Verify Configuration

Test your Databricks connection:

```bash
mix run -e '
path = "/mnt/data/x12/test_file.zip"
case X12Bridge.RemoteFetcher.fetch_and_extract(path) do
  {:ok, result} ->
    IO.puts("✓ Success! Extracted #{length(result.files)} files")
    X12Bridge.RemoteFetcher.cleanup_temp_files(result.temp_dir)
  {:error, :databricks_not_configured} ->
    IO.puts("✗ Databricks not configured")
  {:error, reason} ->
    IO.puts("✗ Error: #{inspect(reason)}")
end
'
```

## Testing with Local HTTP Server

For testing Remote Import with HTTP URLs, you can serve test files locally:

```bash
# Navigate to test data directory
cd test/fixtures/manual_test_data

# Start Python HTTP server
python3 -m http.server 8000
```

Then use these URLs in Remote Import:
```
http://localhost:8000/test_batch_3files.zip
http://localhost:8000/databricks_sample_2026-01-09.zip
http://localhost:8000/synthetic_50files_2026-01-11.zip
```

## Usage in Web Interface

1. Navigate to the **Batch Processing** page
2. Click the **Remote Import** tab
3. In the "ZIP File Source" field, paste one of:
   - HTTP/HTTPS URL
   - Local file path (absolute or relative)
   - Databricks path
4. Click **Fetch & Process**

The system will:
- Automatically detect the source type
- Download or read the file
- Extract X12 files from the ZIP
- Process each file to JSON
- Display real-time results

## File Requirements

All sources must provide a ZIP archive containing X12 files with these extensions:
- `.x12`
- `.edi`
- `.txt`

Optional: Include a `manifest.json` file in the ZIP for batch metadata.

## Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| "Invalid source" | Source format not recognized | Check URL/path format |
| "File not found" | Local file doesn't exist | Verify file path |
| "Databricks not configured" | Missing credentials | Set DATABRICKS_HOST and DATABRICKS_TOKEN |
| "Databricks API error" | Authentication or path issue | Check credentials and file path in Databricks |
| "No X12 files found" | ZIP has no .x12/.edi/.txt files | Check ZIP contents |
| "File exceeds maximum size" | File > 100MB | Split into smaller batches |

## Limits

- **Maximum file size**: 100 MB (configurable)
- **Allowed extensions**: .x12, .edi, .txt (configurable)
- **Download timeout**: 60 seconds (configurable)

## Configuration Options

In `config/config.exs` or `config/runtime.exs`:

```elixir
config :x12_bridge, :remote_fetcher,
  download_timeout_ms: 60_000,      # 60 seconds
  max_file_size_bytes: 100_000_000, # 100 MB
  allowed_extensions: [".x12", ".edi", ".txt"]

config :x12_bridge, :databricks,
  host: System.get_env("DATABRICKS_HOST"),
  token: System.get_env("DATABRICKS_TOKEN")
```

## Security Considerations

### Databricks Tokens
- Use personal access tokens with **limited scope** (read-only if possible)
- Set token **expiration dates**
- Store tokens in **environment variables**, never in code
- Rotate tokens regularly

### Local File Access
- The application can read any file the server process has access to
- Be cautious when deploying to production
- Consider restricting file path patterns if needed

### HTTP Downloads
- HTTP URLs are supported but **HTTPS is recommended** for security
- SSL certificate verification is disabled by default (configurable)
- Be cautious with untrusted sources

## Programmatic Usage

You can also use the RemoteFetcher module directly:

```elixir
# HTTP URL
{:ok, result} = X12Bridge.RemoteFetcher.fetch_and_extract("https://example.com/batch.zip")

# Local file
{:ok, result} = X12Bridge.RemoteFetcher.fetch_and_extract("/path/to/batch.zip")

# Databricks
{:ok, result} = X12Bridge.RemoteFetcher.fetch_and_extract("/mnt/data/x12/batch.zip")

# Process results
IO.inspect(result.files)        # List of extracted file paths
IO.inspect(result.manifest)     # Optional manifest data
IO.inspect(result.temp_dir)     # Temporary directory path

# Clean up when done
X12Bridge.RemoteFetcher.cleanup_temp_files(result.temp_dir)
```

## Troubleshooting

### "Databricks not configured" but I set the environment variables

Make sure you:
1. **Restart the Phoenix server** after setting environment variables
2. Check the variables are actually set: `System.get_env("DATABRICKS_HOST")`
3. Verify the config is loaded: `Application.get_env(:x12_bridge, :databricks)`

### Databricks files not found

1. Verify the file exists in Databricks:
   ```python
   # In Databricks notebook
   dbutils.fs.ls("/mnt/data/x12/")
   ```
2. Check file permissions
3. Ensure the path starts with `/mnt/` or `dbfs:/`

### Local file permission denied

The Phoenix application runs as a specific user. Ensure:
1. The file is readable by the app user
2. All parent directories have execute permissions

### Downloads timeout

For large files over slow connections:
1. Increase the timeout in config
2. Consider using local file paths instead
3. Download manually first, then use local path

---

**Last Updated**: 2026-01-11
**Author**: X12Bridge Development Team
