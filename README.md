# X12Bridge

**Convert X12 EDI healthcare claims (837P/I/D) to clean, semantic JSON.**

A focused, single-purpose Elixir application that parses and validates X12 EDI files, converting them into developer-friendly JSON format.

---

## Quick Start

```bash
# 1. Install dependencies and setup database
mix setup

# 2. Start the server
mix phx.server

# 3. Open in browser
open http://localhost:4000/converter
```

That's it! Load a sample file and convert to JSON.

---

## What X12Bridge Does

✅ **Parse** X12 837 files (Professional, Institutional, Dental)
✅ **Validate** structure, syntax, and business rules
✅ **Convert** to hierarchical, semantic JSON
✅ **Batch process** multiple files concurrently
✅ **Import** from remote servers (SFTP, S3, HTTP)

---

## Features

### Web Interface
- Drag-and-drop file upload
- Real-time validation feedback
- Sample files for testing
- Download/copy JSON output
- Batch processing with progress tracking

### Core Capabilities
- Supports 837P (Professional), 837I (Institutional), 837D (Dental)
- Concurrent batch processing (10+ files simultaneously)
- Comprehensive validation (structural, syntactical, business rules)
- Remote file import (SFTP, S3, HTTP)
- Hot folder monitoring for automated processing

### What It Doesn't Do
- ❌ No provider lookup or validation
- ❌ No fraud detection
- ❌ No claims payment processing
- ❌ **Just translation** - keeps it simple

---

## Documentation

All documentation is in the [`docs/`](docs/) directory:

| Document | Purpose |
|----------|---------|
| [**GUIDE.md**](docs/GUIDE.md) | **Complete guide** - Installation, usage, and Elixir fundamentals |
| [**ARCHITECTURE.md**](docs/ARCHITECTURE.md) | System design with 7 Mermaid diagrams |
| [**DATABASE.md**](docs/DATABASE.md) | Schema, ERD, queries, migrations |
| [**BATCH_PROCESSING.md**](docs/BATCH_PROCESSING.md) | Batch processing and remote import |
| [**API_REFERENCE.md**](docs/API_REFERENCE.md) | Module and function documentation |

### Quick Links

- **New to X12Bridge?** → [GUIDE.md](docs/GUIDE.md) - Start here!
- **Understanding the system?** → [ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Database schema?** → [DATABASE.md](docs/DATABASE.md)
- **Batch processing?** → [BATCH_PROCESSING.md](docs/BATCH_PROCESSING.md)
- **API functions?** → [API_REFERENCE.md](docs/API_REFERENCE.md)

---

## Project Structure

```
x12_bridge/
├── lib/
│   ├── x12_bridge/
│   │   ├── x12/              # Core X12 parsing, conversion, validation
│   │   ├── conversions/      # Batch and job management
│   │   └── batch_processor.ex # Hot folder processing
│   └── x12_bridge_web/       # LiveView UI
├── docs/                     # All documentation
├── priv/
│   ├── batch_processing/     # Hot folder directories
│   ├── repo/migrations/      # Database migrations
│   └── test_data/            # Sample X12 files
└── test/                     # Tests
```

---

## Technology Stack

- **Elixir 1.15+** - Functional language perfect for parsing
- **Phoenix 1.8+** - Web framework
- **LiveView** - Real-time UI without JavaScript
- **PostgreSQL** - Database for job tracking
- **Ecto** - Database queries and migrations
- **Tailwind CSS** - Styling

---

## Example Usage

### Web Interface

1. Visit [http://localhost:4000/converter](http://localhost:4000/converter)
2. Click "Load 837P Sample"
3. Click "Validate & Convert to JSON"
4. Download or copy the JSON output

### Programmatic

```elixir
# Parse X12 file
{:ok, result} = X12Bridge.X12.Parser.parse(x12_content)

# Validate
validation = X12Bridge.X12.Validator.validate_content(x12_content)

# Convert to JSON
{:ok, json} = X12Bridge.X12.Converter.convert_content(x12_content)

# Batch process local files
{:ok, result} = X12Bridge.BatchProcessor.process_input_directory()

# Import from remote SFTP server
{:ok, result} = X12Bridge.RemoteImport.import_from_sftp(config)
```

---

## Example JSON Output

```json
{
  "transaction": {
    "type": "837",
    "control_number": "0001",
    "submitter": { "name": {...}, "identification": {...} }
  },
  "claims": [
    {
      "claim_id": "CLAIM123",
      "total_charge": 150.00,
      "subscriber": {...},
      "diagnosis_codes": [...],
      "service_lines": [
        {
          "line_number": "1",
          "procedure": { "qualifier": "HC", "code": "99213" },
          "charge": 75.00,
          "quantity": 1
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

---

## Common Commands

```bash
# Development
mix setup                    # Install deps, setup DB, build assets
mix phx.server              # Start server
mix test                    # Run tests

# Database
mix ecto.create             # Create database
mix ecto.migrate            # Run migrations
mix ecto.reset              # Drop, create, and migrate

# Code Quality
mix format                  # Format code
mix compile --warnings-as-errors  # Strict compilation
mix precommit               # Run all checks (format, compile, test)

# Production
MIX_ENV=prod mix assets.deploy    # Build production assets
MIX_ENV=prod mix release          # Build release
```

---

## Development

### Prerequisites
- Elixir 1.15+
- PostgreSQL 14+
- Node.js 18+ (for assets)

See [GUIDE.md](docs/GUIDE.md) for detailed installation instructions.

### Running Tests

```bash
mix test                    # All tests
mix test --only unit        # Unit tests only
mix test path/to/test.exs   # Specific file
```

### Interactive Development

```bash
iex -S mix phx.server

# Try functions interactively
iex> content = File.read!("priv/test_data/single/sample_837p.x12")
iex> {:ok, json} = X12Bridge.X12.Converter.convert_content(content)
```

---

## Deployment

### Recommended Platform: Fly.io

```bash
fly launch
fly secrets set SECRET_KEY_BASE=<secret>
fly deploy
```

See [GUIDE.md](docs/GUIDE.md) for Docker, Railway, and other deployment options.

---

## License

This project is currently unlicensed. Contact the owner for usage rights.

---

## Project Status

**Current Status:** Core translation engine complete and production-ready

**What's Working:**
- ✅ X12 parsing for 837P/I/D
- ✅ Comprehensive validation
- ✅ JSON conversion
- ✅ Web interface with LiveView
- ✅ Batch processing
- ✅ Remote server import (SFTP, HTTP)

**Not Yet Implemented:**
- ⏳ User authentication
- ⏳ Subscription management
- ⏳ Payment processing
- ⏳ REST API endpoints
- ⏳ Background job processing (Oban)

See [CODE_REVIEW_REPORT.md](docs/archive/CODE_REVIEW_REPORT.md) for detailed assessment.

---

## Contributing

This is currently a solo project. If you'd like to contribute or use this commercially, please contact the owner.

---

## Learn More

- **Phoenix Framework:** https://www.phoenixframework.org/
- **Elixir Language:** https://elixir-lang.org/
- **X12 Standards:** https://x12.org/
- **HIPAA 837 Guide:** https://www.cms.gov/regulations-and-guidance/administrative-simplification/hipaa-aba

---

**Built with Elixir** 🧪 | **Powered by Phoenix** 🔥 | **Focused on simplicity** ✨
