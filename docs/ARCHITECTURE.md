# X12Translator Architecture

A focused, single-purpose Elixir application for converting X12 EDI healthcare claims to semantic JSON.

## Summary

**Core Module Count:** 28 modules (reduced from 30)

**Recent Consolidations (Phase 2 Simplification):**
- **JobStatus** - Centralized all job status definitions (atoms, validation, helpers)
- **Builder** - Merged into Converter as private reconstruction functions
- **Qualifiers** - Merged into Converter as private code lookup helpers

---

## System Overview

X12Translator uses a **two-stage verification + translation pipeline** to provide cost transparency and quality gates:

```
Stage 1: Verify (FREE)     Stage 2: Translate (BILLED)
├─ File validation        ├─ Full X12→JSON conversion
├─ Claim counting         ├─ Round-trip validation
├─ Fast (~5-20ms)         └─ Detailed JSON output
└─ No cost
```

### What X12Translator Does

✓ Parse X12 EDI files (837P/I/D)
✓ Validate X12 structure (fast pre-flight checks)
✓ Convert to semantic JSON with data integrity guarantee
✓ Track batch processing jobs with two-stage workflow
✓ Provide real-time web interface with cost transparency

### What X12Translator Does NOT Do

✗ Provider validation or lookup
✗ Fraud detection
✗ Payment processing
✗ Complete claims processing system

---

## User Workflow

```
1. Upload X12 files → 2. Click "Verify" (FREE)
                         ↓
                    See claim count & cost estimate
                         ↓
3. Click "Translate" (ONLY verified files) → Billed per claim
```

---

## Core Architecture

```
┌─────────────────────────────────────────────────────┐
│              Web Interface (Phoenix LiveView)         │
│         - File upload / Remote import                │
│         - Real-time progress updates                 │
│         - JSON preview & download                    │
└────────────┬────────────────────────────────────────┘
             │
┌────────────┴────────────────────────────────────────┐
│          Conversions Context (Business Logic)       │
│                                                      │
│  ├─ verify_batch_sync/2    (Stage 1: FREE)         │
│  ├─ translate_batch_sync/2 (Stage 2: BILLED)       │
│  ├─ process_batch_sync/2   (Legacy: both stages)   │
│  └─ Job/Batch tracking via Ecto                    │
└────────────┬────────────────────────────────────────┘
             │
┌────────────┴────────────────────────────────────────┐
│               X12 Pipeline Modules                   │
│                                                      │
│  Parser (370 lines)           ← Parse X12 segments │
│    ↓                                                 │
│  Converter (~1,450 lines)     ← X12→JSON, Builder, │
│                                  Qualifiers         │
│    ↓                                                 │
│  Verifier (365 lines)         ← Fast lightweight    │
│                                  check              │
│                                                      │
│  Supporting: RoundtripValidator, JobStatus          │
└────────────┬────────────────────────────────────────┘
             │
┌────────────┴────────────────────────────────────────┐
│           PostgreSQL Database                        │
│                                                      │
│  ├─ conversion_batches    (batch metadata)          │
│  └─ conversion_jobs       (file + result tracking)  │
└──────────────────────────────────────────────────────┘
```

---

## Stage 1: Verification (FREE)

Fast pre-flight checks to catch invalid X12 files **before** translation, preventing wasted processing.

### What It Checks (~5-20ms per file)

| Check | Example Error | Severity |
|-------|---|---|
| File extension | "File must be .x12, .edi, or .txt" | ERROR |
| Envelope structure | "Missing ISA/GS/ST segments" | ERROR |
| Delimiters valid | "Invalid delimiter: ^ (expected *)" | ERROR |
| Required segments | "Missing required BHT segment" | ERROR |
| Claim counting | "Found 15 CLM segments" | INFO |
| Segment syntax | "ISA segment malformed" | ERROR |

### Return Value
```elixir
%{
  valid?: true,
  claim_count: 15,
  errors: [],
  warnings: [],
  segment_delimiter: "~",
  element_delimiter: "*",
  transaction_type: "837P",
  total_segments: 240,
  checked_at: ~U[2026-01-14 10:30:00Z]
}
```

---

## Stage 2: Translation (BILLED)

Full X12→JSON conversion with round-trip validation to ensure data fidelity.

### Process

1. **Parse X12** - Extract delimiters, segments, hierarchical structure
2. **Build JSON** - Claims with service lines, metadata
3. **Validate** - Round-trip reconstruction must match original byte-for-byte
4. **Charge** - Billed per successfully translated claim

### Output
```json
{
  "transaction": {
    "type": "837P",
    "version": "005010X222",
    "control_number": "000000001"
  },
  "claims": [
    {
      "claim_id": "CLM001",
      "subscriber": { "name": "...", "dob": "..." },
      "provider": { "npi": "...", "name": "..." },
      "services": [
        {
          "procedure_code": "99213",
          "amount": "150.00",
          "units": "1"
        }
      ]
    }
  ],
  "summary": {
    "total_claims": 1,
    "total_claims_charged": 1,
    "total_services": 1
  }
}
```

---

## Job Status Flow

```
                    ┌─ failed_verification
                    │  (verify error)
uploaded → verifying ┤
                    └─ verified → translating ┐
                                              ├─ translated ✓
                                              └─ failed_translation ✗
                                                 (conversion/round-trip error)

Legend:
✓ = Billable
✗ = Not billable
```

---

## Module Responsibilities

### X12.Parser (370 lines)
**Responsibility:** Low-level X12 parsing

- Extract delimiters from ISA segment (`*`, `:`, `~`)
- Split X12 into segments
- Parse elements within segments
- Identify hierarchical loops (2300 claim, 2400 service lines)
- Extract envelope (ISA/GS/ST headers)

---

### X12.Converter (~1,450 lines)
**Responsibility:** X12→JSON conversion, reconstruction, and code lookups

**Integrated Functionality (Previously Separate Modules):**
- **Builder (merged)** - Reconstructs X12 from JSON for round-trip validation
- **Qualifiers (merged)** - Provides human-readable code descriptions (entity codes, date qualifiers, place of service, etc.)

**Core Functions:**
- Build hierarchical JSON structure from X12 segments
- Extract transaction metadata, claims, and service lines
- Handle 837P (Professional), 837I (Institutional), 837D (Dental) variants
- Format dates, amounts, codes with descriptive text
- Extract entities (providers, subscribers, patients)
- Rebuild X12 from JSON structure for round-trip validation

---

### X12.Verifier (365 lines)
**Responsibility:** Fast validation without conversion

- Detect delimiters & transaction type
- Validate envelope (ISA/GS/ST/SE/GE/IEA)
- Validate required segments (BHT, NM1, CLM)
- Validate segment syntax
- Count CLM segments for billing

---

### JobStatus (Centralized Module)
**Responsibility:** Single source of truth for job status definitions

- Defines all valid job statuses as atoms (`:uploaded`, `:verifying`, `:verified`, `:translating`, `:translated`, `:failed_verification`, `:failed_translation`)
- Provides validation functions for type safety
- Helper predicates: `success?/1`, `failed?/1`, `complete?/1`
- Replaces hardcoded status strings scattered throughout codebase

---

### X12.RoundtripValidator (263 lines)
**Responsibility:** Ensure JSON→X12 fidelity

- Reconstruct X12 from JSON
- Compare byte-by-byte with original
- Report any differences
- **Blocks translation if data loss detected**

---

### Conversions Context
**Responsibility:** Manage batches and jobs

- `verify_batch_sync/2` - Stage 1: Verification (FREE)
- `translate_batch_sync/2` - Stage 2: Translation (BILLED)
- `process_batch_sync/2` - Legacy: both stages
- Job/Batch CRUD and tracking
- Real-time updates via PubSub

---

## Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| **Language** | Elixir | 1.15+ |
| **Web Framework** | Phoenix | 1.8.1+ |
| **Real-time UI** | Phoenix LiveView | 1.1.0+ |
| **Database** | PostgreSQL | 14+ |
| **ORM** | Ecto | 3.13+ |
| **HTTP Server** | Bandit | 1.5+ |
| **JSON** | Jason | 1.2+ |
| **CSS** | Tailwind | 4.1.7+ |

---

## Configuration

```elixir
# config/config.exs

# Batch retention (auto-cleanup old batches)
config :x12_translator, :batch_retention,
  max_batches: 50

# Converter timeouts & limits
config :x12_translator, :converter,
  max_file_size_mb: 50,
  processing_timeout_ms: 30_000

# Batch processor
config :x12_translator, :batch_processor,
  max_concurrency: 10,
  timeout_per_file_ms: 30_000

# Remote fetcher
config :x12_translator, :remote_fetcher,
  timeout_ms: 60_000,
  max_file_size_bytes: 100 * 1024 * 1024
```

---

## Error Handling

### File Size Protection
- **Limit:** 50 MB (configurable)
- **Action:** Reject before reading to memory

### Processing Timeout
- **Limit:** 30 seconds (configurable)
- **Action:** Kill hung task, return error

### Input Validation
- ISA segment must be ≥106 characters
- Must start with "ISA"
- Delimiters must be single character

### Graceful Degradation
- One file failure doesn't block batch
- Detailed error messages per job
- Verification failures don't charge
- Translation failures don't charge failed files

---

## Related Documentation

- **[API.md](API.md)** - Database schema, error codes, configuration, module reference
- **[X12BRIDGE_db.pdf](X12BRIDGE_db.pdf)** - Entity Relationship Diagram (ERD) showing all database tables and relationships
- **[SETUP_TROUBLESHOOTING.md](SETUP_TROUBLESHOOTING.md)** - Common setup issues and solutions for macOS and Ubuntu
