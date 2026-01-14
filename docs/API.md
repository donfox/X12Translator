# X12Bridge API & Configuration Reference

Complete reference for database schema, error codes, configuration, remote import, and module functions.

---

## Database Schema

### conversion_batches

Tracks batch processing sessions.

```sql
CREATE TABLE conversion_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar NOT NULL,
  total_files integer NOT NULL DEFAULT 0,
  completed_files integer NOT NULL DEFAULT 0,
  failed_files integer NOT NULL DEFAULT 0,
  status varchar NOT NULL DEFAULT 'uploaded',
  
  -- Verification fields
  verified_files integer DEFAULT 0,
  failed_verification_files integer DEFAULT 0,
  
  -- Translation fields
  translated_files integer DEFAULT 0,
  failed_translation_files integer DEFAULT 0,
  total_claims integer DEFAULT 0,
  total_claims_charged integer DEFAULT 0,
  
  inserted_at timestamp NOT NULL DEFAULT NOW(),
  updated_at timestamp NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_batches_status ON conversion_batches(status);
CREATE INDEX idx_batches_inserted_at ON conversion_batches(inserted_at DESC);
```

**Statuses:**
- `uploaded` - Initial state, files staged
- `verifying` - Running verification checks
- `verified` - Verification complete (may have some failures)
- `translating` - Running translation on verified files
- `translated` - Translation complete
- `processing` - Legacy single-stage processing

---

### conversion_jobs

Tracks individual files within a batch.

```sql
CREATE TABLE conversion_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES conversion_batches(id) ON DELETE CASCADE,
  
  -- File info
  original_filename varchar NOT NULL,
  file_size integer NOT NULL,
  
  -- Processing status
  status varchar NOT NULL DEFAULT 'uploaded',
  progress integer DEFAULT 0,
  processing_time_ms integer,
  
  -- Results
  x12_content text,          -- Original X12 content
  json_result text,          -- Converted JSON
  error_message text,
  
  -- Verification (Stage 1)
  verification_result jsonb,
  verification_error text,
  verified_at timestamp,
  claim_count integer DEFAULT 0,
  
  -- Translation (Stage 2)
  claims_charged integer DEFAULT 0,
  translated_at timestamp,
  
  -- Round-trip validation
  roundtrip_valid boolean,
  roundtrip_diff text,
  roundtrip_error text,
  
  inserted_at timestamp NOT NULL DEFAULT NOW(),
  updated_at timestamp NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_jobs_batch_id ON conversion_jobs(batch_id);
CREATE INDEX idx_jobs_status ON conversion_jobs(status);
CREATE INDEX idx_jobs_batch_status ON conversion_jobs(batch_id, status);
```

**Statuses:**
- `uploaded` - File staged
- `verifying` - Running verification check
- `verified` - Passed verification
- `failed_verification` - Failed verification check
- `translating` - Running translation
- `translated` - Successfully translated
- `failed_translation` - Translation failed
- `pending`, `processing`, `completed`, `failed` - Legacy statuses

---

## Error Codes & Messages

### Verification Errors (Stage 1)

| Code | Message | Resolution |
|------|---------|-----------|
| `FILE_TOO_SHORT` | File too short to contain valid ISA segment | File must be ≥106 bytes |
| `NO_ISA_SEGMENT` | File does not start with ISA segment | Must be valid X12 format |
| `INVALID_EXTENSION` | File must be .x12, .edi, or .txt | Rename file extension |
| `INVALID_ENVELOPE` | Missing ISA/GS/ST envelope | Corrupted X12 structure |
| `INVALID_DELIMITERS` | Invalid or undetectable delimiters | Check file format |
| `MISSING_REQUIRED_SEGMENT` | Missing required segment: {segment_id} | Add required segment (BHT, NM1, CLM) |
| `INVALID_SEGMENT_SYNTAX` | Segment {id} has invalid syntax | Check segment format |
| `NO_CLAIMS_FOUND` | No CLM segments found | File must contain at least one claim |

### Translation Errors (Stage 2)

| Code | Message | Resolution |
|------|---------|-----------|
| `PARSING_FAILED` | Parsing failed: {reason} | Check X12 syntax |
| `CONVERSION_FAILED` | Conversion failed: {reason} | See detailed error message |
| `ROUNDTRIP_INVALID` | X12 cannot be perfectly reconstructed from JSON | Data integrity issue, contact support |
| `PROCESSING_TIMEOUT` | File took longer than 30 seconds to process | File too complex, reduce size |
| `FILE_TOO_LARGE` | File size 75.5 MB exceeds maximum of 50.0 MB | Split into smaller files |
| `UNEXPECTED_ERROR` | Unexpected error: {reason} | Contact support with file and error |

### System Errors

| Code | Message | Resolution |
|------|---------|-----------|
| `DATABASE_ERROR` | Failed to update database | Retry operation |
| `PUBSUB_ERROR` | Real-time updates unavailable | Page refresh may show progress |
| `REMOTE_FETCH_FAILED` | Failed to fetch remote file | Check URL or file permissions |
| `INVALID_URL` | Invalid URL format | Use http://, https://, local path, or /mnt/ path |
| `DOWNLOAD_TIMEOUT` | Download took longer than 60 seconds | Try again or check network |
| `INVALID_ZIP` | Not a valid ZIP file | File must be standard ZIP format |
| `NO_X12_FILES` | ZIP contains no X12 files | ZIP must contain .x12, .edi, or .txt files |

---

## Configuration Reference

### Environment Variables

```bash
# Database
DATABASE_URL=ecto://user:password@localhost:5432/x12_bridge_dev

# Phoenix
PHX_HOST=localhost
PHX_HTTP_PORT=4000
SECRET_KEY_BASE=your-secret-key-here

# Remote Import (Optional)
DATABRICKS_HOST=https://workspace.cloud.databricks.com
DATABRICKS_TOKEN=dapi1234567890abcdef

# Batch Processing
BATCH_MAX_CONCURRENCY=10
BATCH_TIMEOUT_MS=30000
```

### Config Files

#### config/config.exs (All Environments)

```elixir
import Config

# Application settings
config :x12_bridge,
  ecto_repos: [X12Bridge.Repo],
  generators: [timestamp_type: :utc_datetime]

# Batch retention (auto-cleanup old batches)
config :x12_bridge, :batch_retention,
  max_batches: 50  # Keep only 50 most recent

# Converter limits
config :x12_bridge, :converter,
  max_file_size_mb: 50,
  processing_timeout_ms: 30_000

# Batch processor concurrency
config :x12_bridge, :batch_processor,
  max_concurrency: 10,
  timeout_per_file_ms: 30_000

# Remote fetcher timeouts
config :x12_bridge, :remote_fetcher,
  timeout_ms: 60_000,
  max_file_size_bytes: 100 * 1024 * 1024

# JSON library
config :phoenix, :json_library, Jason

# MIME types
config :mime, :types, %{
  "application/x12" => ["x12"],
  "application/edi" => ["edi"],
  "text/plain" => ["txt"]
}
```

#### config/dev.exs (Development)

```elixir
import Config

# Database
config :x12_bridge, X12Bridge.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "x12_bridge_dev",
  stacktrace: true,
  show_sensitive_data_on_error: true,
  pool_size: 10

# Endpoint
config :x12_bridge, X12BridgeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:x12_bridge, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:x12_bridge, ~w(--watch)]}
  ]

# Logger
config :logger, :console, format: "[$level] $message\n"

# LiveView
config :phoenix_live_view, :debug_heex_annotations, true
```

#### config/prod.exs (Production)

```elixir
import Config

# Database (use DATABASE_URL environment variable)
config :x12_bridge, X12Bridge.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true

# Endpoint
config :x12_bridge, X12BridgeWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST"), port: 443, scheme: "https"],
  http: [port: String.to_integer(System.get_env("PORT") || "8080")],
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
  server: true,
  code_reloader: false,
  check_origin: false,
  watchers: []

# Logger
config :logger,
  level: :info,
  backends: [{:console, [format: "[$level] $message"]}]
```

---

## Remote Import Configuration

### Supported Sources

#### 1. HTTP/HTTPS URLs

```elixir
X12Bridge.RemoteFetcher.fetch_and_extract("https://example.com/batches/claims.zip")
# or
X12Bridge.RemoteFetcher.fetch_and_extract("http://localhost:8000/test.zip")
```

**Options:**
```elixir
X12Bridge.RemoteFetcher.fetch_and_extract(url, 
  timeout: 120_000,           # 2 minutes (default: from config)
  max_size: 200 * 1024 * 1024 # 200 MB (default: from config)
)
```

#### 2. Local File Paths

```elixir
# Absolute paths
X12Bridge.RemoteFetcher.fetch_and_extract("/Users/name/Downloads/batch.zip")
X12Bridge.RemoteFetcher.fetch_and_extract("C:\\Users\\name\\Downloads\\batch.zip")

# Relative paths from project root
X12Bridge.RemoteFetcher.fetch_and_extract("test/fixtures/sample.zip")
```

#### 3. Databricks Paths

**Prerequisites:**
1. Generate Databricks Personal Access Token
2. Configure environment variables

```bash
# .env.local (development) or as system variables (production)
DATABRICKS_HOST=https://workspace.cloud.databricks.com
DATABRICKS_TOKEN=dapi1234567890abcdef
```

**Usage:**
```elixir
X12Bridge.RemoteFetcher.fetch_and_extract("/mnt/data/x12/batch.zip")
X12Bridge.RemoteFetcher.fetch_and_extract("dbfs:/FileStore/x12_batches/export.zip")
```

### Response Format

**Success:**
```elixir
{:ok, %{
  files: ["/tmp/x12bridge_remote_123/file1.x12", "/tmp/x12bridge_remote_456/file2.x12"],
  manifest: %{
    "batch_id" => "2026-01-09",
    "file_count" => 2
  },
  temp_dir: "/tmp/x12bridge_remote_123"
}}
```

**Errors:**
```elixir
{:error, :invalid_url}
{:error, :invalid_path}
{:error, :download_failed}
{:error, {:http_error, 404}}
{:error, :invalid_zip}
{:error, :no_x12_files}
{:error, :file_too_large}
{:error, :databricks_not_configured}
```

---

## Module Function Reference

### X12.Verifier

```elixir
@spec verify(binary) :: %{
  valid?: boolean,
  claim_count: non_neg_integer,
  errors: [String.t()],
  warnings: [String.t()],
  segment_delimiter: String.t(),
  element_delimiter: String.t(),
  transaction_type: String.t(),
  total_segments: non_neg_integer,
  checked_at: DateTime.t()
}
def verify(x12_content) do
  # Verify X12 file structure and count claims
end
```

### X12.Converter

```elixir
@spec convert_file(String.t()) :: {:ok, String.t()} | {:error, String.t()}
def convert_file(filepath) do
  # Convert X12 file to JSON string
end

@spec convert_content(binary) :: {:ok, String.t()} | {:error, String.t()}
def convert_content(content) do
  # Convert X12 content string to JSON
end
```

### X12.RoundtripValidator

```elixir
@spec validate(binary) :: %{
  valid?: boolean,
  error_message: String.t() | nil
}
def validate(x12_content) do
  # Validate that JSON→X12 reconstruction matches original
end

@spec format_result(map) :: String.t()
def format_result(result) do
  # Format validation result for display
end
```

### Conversions

```elixir
@spec verify_batch_sync(binary, map) :: {:ok, Batch.t()}
def verify_batch_sync(batch_id, uploaded_files) do
  # Stage 1: Verify all files in batch (FREE)
  # uploaded_files: %{job_id => file_content}
end

@spec translate_batch_sync(binary, map) :: {:ok, Batch.t()}
def translate_batch_sync(batch_id, uploaded_files) do
  # Stage 2: Translate verified files (BILLED)
end

@spec process_batch_sync(binary, map) :: {:ok, Batch.t()}
def process_batch_sync(batch_id, uploaded_files) do
  # Legacy: Both verify & translate in one call
end

@spec create_batch(map) :: {:ok, Batch.t()} | {:error, Ecto.Changeset.t()}
def create_batch(attrs) do
  # Create new batch with initial attributes
end

@spec get_batch!(binary) :: Batch.t()
def get_batch!(id) do
  # Fetch batch by ID (raises if not found)
end

@spec list_batches(keyword) :: [Batch.t()]
def list_batches(opts \\ []) do
  # List batches, paginated
  # Options: limit: 50 (default)
end

@spec cleanup_old_batches(keyword) :: {:ok, non_neg_integer}
def cleanup_old_batches(opts \\ []) do
  # Delete old batches, keep only N most recent
  # Options: keep: 50 (default from config)
end
```

### RemoteFetcher

```elixir
@spec fetch_and_extract(String.t(), keyword) ::
  {:ok, %{files: [String.t()], manifest: map | nil, temp_dir: String.t()}}
  | {:error, atom}
def fetch_and_extract(source, opts \\ []) do
  # Fetch ZIP from HTTP, local file, or Databricks
  # Returns list of extracted X12 files
end

@spec detect_source_type(String.t()) :: :http_url | :local_file | :databricks_path | :invalid
def detect_source_type(source) do
  # Detect source type from string
end

@spec cleanup_temp_files(String.t()) :: :ok
def cleanup_temp_files(temp_dir) do
  # Delete temporary directory and all files
end
```

---

## PubSub Events

### Batch Channel: `batch:#{batch_id}`

```elixir
# When a verification is completed
{:job_verified, job_id}

# When a verification fails
{:job_verification_failed, job_id, error_message}

# When batch verification completes
{:batch_verified, batch_id}

# When a translation completes
{:job_translated, job_id}

# When a translation fails
{:job_translation_failed, job_id, error_message}

# When batch translation completes
{:batch_translated, batch_id}

# Legacy: When a job completes (single-stage)
{:job_completed, job_id, status}

# Legacy: When batch completes (single-stage)
{:batch_completed, batch_id}
```

### Global Channel: `batches`

```elixir
# When remote import completes
{:remote_import_completed, {:ok, batch} | {:error, reason}}
```

---

## Testing Fixtures

### Test Data Location

```
test/fixtures/
├── automated_test_data/
│   ├── 001_837p_valid.x12         # Professional claim
│   ├── 002_837i_valid.x12         # Institutional claim
│   ├── 003_837d_valid.x12         # Dental claim
│   ├── 004_837p_multi.x12         # Multiple claims
│   ├── 005_837p_error.x12         # Invalid X12
│   └── manifest.json              # Batch metadata
└── manual_test_data/
    ├── README.md
    └── archives/
        ├── databricks_sample_*.zip
        └── ... other samples
```

### Running Tests

```bash
# All tests
mix test

# Specific test file
mix test test/x12_bridge/x12/parser_test.exs

# Tests with coverage
mix test --cover

# Watch mode (requires file_system)
mix test.watch
```

---

## Performance Tuning

### Database Connection Pool

```elixir
# In dev.exs / prod.exs
config :x12_bridge, X12Bridge.Repo,
  pool_size: 10  # Default: 10 connections
```

**Adjust based on:** Concurrent users, batch processing concurrency

### Batch Processing Concurrency

```elixir
# In config.exs
config :x12_bridge, :batch_processor,
  max_concurrency: 10  # Default: 10 files at once
```

**Adjust based on:** CPU cores (typically cores × 1.5), available RAM

### Processing Timeouts

```elixir
# In config.exs
config :x12_bridge, :converter,
  processing_timeout_ms: 30_000  # Default: 30 seconds

config :x12_bridge, :batch_processor,
  timeout_per_file_ms: 30_000    # Default: 30 seconds
```

**Increase if:** Processing large or complex X12 files

### File Size Limits

```elixir
# In config.exs
config :x12_bridge, :converter,
  max_file_size_mb: 50  # Default: 50 MB

config :x12_bridge, :remote_fetcher,
  max_file_size_bytes: 100 * 1024 * 1024  # Default: 100 MB
```

---

## Troubleshooting

### Batch Processing Hangs

- Check `processing_timeout_ms` setting
- Verify database connection pool size
- Check system memory availability

### Verification Passes but Translation Fails

- Usually due to round-trip validation issue
- Check `roundtrip_diff` field in job record
- Contact support with file and error message

### Remote Import Fails

- Verify URL is accessible
- Check firewall/network settings
- For Databricks: verify token and host configuration
- Ensure ZIP contains X12 files

### High CPU Usage During Batch Processing

- Reduce `max_concurrency` setting
- Split large batches into smaller ones
- Monitor system load: `top`, `htop`

### Database Connection Errors

- Verify DATABASE_URL is correct
- Check PostgreSQL is running
- Increase `pool_size` if many concurrent batches

---

## Related Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design, module responsibilities, data flow
- **[README.md](../README.md)** - Quick start, features, setup
