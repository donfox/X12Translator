# CLAUDE.md - X12Bridge Project Guide

## Project Overview

**X12Bridge** is a focused X12 → JSON translation service (SaaS) that allows users to upload X12 EDI files and receive clean, semantic JSON output. This is a single-purpose application deliberately scoped to avoid feature creep.

**Core Value Proposition:** Convert complex X12 EDI healthcare transactions into developer-friendly JSON format.

### What This Project IS
- ✅ X12 file upload and parsing service
- ✅ Conversion to semantic, hierarchical JSON
- ✅ Job tracking and usage limits
- ✅ Subscription-based access with tiered pricing
- ✅ Support for multiple X12 transaction types (837P, 837I, 837D, etc.)

### What This Project IS NOT
- ❌ NOT a complete claims processing system
- ❌ NO provider lookup or validation
- ❌ NO fraud detection
- ❌ NO payment processing for actual claims
- ❌ JUST translation - keep it simple

## Architecture

### Structure: Simple Phoenix Application

This project uses a **simple Phoenix app with contexts** (NOT an umbrella structure) following the YAGNI principle. The umbrella approach was explicitly rejected to save development time and reduce complexity.

```
x12_bridge/
├── lib/
│   ├── x12_bridge/
│   │   ├── x12/                    # X12 parsing context
│   │   │   ├── parser.ex           # Core X12 segment parser
│   │   │   ├── converter.ex        # X12 → JSON conversion
│   │   │   └── validator.ex        # X12 structural validation
│   │   ├── accounts/               # Users & authentication
│   │   │   ├── user.ex
│   │   │   ├── subscription.ex
│   │   │   └── guardian.ex
│   │   ├── conversions/            # Job tracking & processing
│   │   │   ├── job.ex
│   │   │   └── processor.ex
│   │   └── repo.ex
│   ├── x12_bridge_web/
│   │   ├── controllers/
│   │   ├── live/                   # LiveView components
│   │   │   ├── upload_live.ex
│   │   │   └── dashboard_live.ex
│   │   └── templates/
├── config/
├── priv/
│   └── repo/migrations/
└── test/
```

### Key Contexts

1. **X12 Context** (`lib/x12_bridge/x12/`)
   - Handles all X12 parsing logic
   - Converts X12 segments to structured JSON
   - Based on proven Python implementation patterns

2. **Accounts Context** (`lib/x12_bridge/accounts/`)
   - User registration and authentication
   - Subscription tier management
   - Usage limit tracking

3. **Conversions Context** (`lib/x12_bridge/conversions/`)
   - File upload handling
   - Conversion job tracking
   - Background processing
   - Result storage and retrieval

## Technology Stack

### Core Technologies
- **Language:** Elixir 1.15+
- **Framework:** Phoenix 1.7+
- **Database:** PostgreSQL
- **Real-time:** Phoenix LiveView
- **Auth:** Guardian (JWT-based authentication)
- **JSON:** Jason

### Key Dependencies
```elixir
{:phoenix, "~> 1.7"},
{:phoenix_live_view, "~> 0.20"},
{:ecto_sql, "~> 3.11"},
{:postgrex, "~> 0.17"},
{:guardian, "~> 2.3"},
{:bcrypt_elixir, "~> 3.0"},
{:jason, "~> 1.4"},
{:swoosh, "~> 1.14"},        # Email notifications
{:oban, "~> 2.17"},          # Background job processing (optional)
```

### Why Elixir for This Project
- Pattern matching is perfect for X12 segment parsing
- Immutable data structures make parsing safer
- Supervisor trees provide resilient file processing
- Phoenix LiveView enables real-time progress updates
- Built-in concurrency for handling multiple simultaneous uploads
- OTP fault tolerance for production reliability

## Database Schema

### Core Tables

**users**
- `id` (UUID, PK)
- `email` (unique)
- `password_hash`
- `name`
- timestamps

**subscriptions**
- `id` (UUID, PK)
- `user_id` (FK → users)
- `tier` (free, starter, professional, business)
- `status` (active, canceled, expired)
- `conversions_used` (integer)
- `conversions_limit` (integer)
- `current_period_start`, `current_period_end`
- timestamps

**conversion_jobs**
- `id` (UUID, PK)
- `user_id` (FK → users)
- `original_filename`
- `file_size`
- `status` (pending, processing, completed, failed)
- `json_result` (JSONB - stores converted JSON)
- `error_message` (text)
- `processing_time_ms`
- timestamps

## X12 Parser Implementation

### Source Material
The X12 parser is based on working Python implementations found in `pyx12_837p_to_json/`:
- **Structured parser** - Creates hierarchical JSON (claims with service lines)
- **Flat parser** - Sequential segment representation

### Key X12 Concepts

**Loop Hierarchy (for 837P):**
- **2300 Loop** - Claim level (CLM segment)
  - Contains claim ID, total charge, dates
  - **2400 Loop** - Service line level (SV1 segment)
    - Contains procedure codes, line charges, dates

**Critical Segments:**
- `ISA` - Interchange Control Header
- `GS` - Functional Group Header
- `ST` - Transaction Set Header
- `CLM` - Claim Information
- `SV1` - Professional Service
- `SE` - Transaction Set Trailer
- `GE` - Functional Group Trailer
- `IEA` - Interchange Control Trailer

### Translation Pattern (Python → Elixir)

**Python (PyX12):**
```python
for claim_loop in ctx.iter_segments("2300"):
    claim_id = claim_loop.get_value("CLM01")
    total_charge = claim_loop.get_value("CLM02")

    service_lines = []
    for sl_loop in claim_loop.select("2400"):
        procedure_code = sl_loop.get_value("SV101")
        service_lines.append({...})
```

**Elixir (Functional):**
```elixir
x12_content
|> parse_segments()
|> find_loops("2300")
|> Enum.map(fn claim_loop ->
  %{
    claim_id: get_value(claim_loop, "CLM01"),
    total_charge: get_value(claim_loop, "CLM02"),
    service_lines:
      claim_loop
      |> find_nested_loops("2400")
      |> Enum.map(&extract_service_line/1)
  }
end)
```

## Pricing Strategy

### Tier Structure

**FREE** (Developer/Testing)
- 10 conversions/month
- 1 MB max file size
- 5 requests/hour rate limit

**STARTER** ($29/month or $0.25/conversion)
- 200 conversions/month (~$0.145 per conversion at full usage)
- 5 MB max file size
- 20 requests/hour

**PROFESSIONAL** ($99/month or $0.15/conversion)
- 1,000 conversions/month (~$0.099 per conversion)
- 25 MB max file size
- 100 requests/hour
- API access included

**BUSINESS** ($299/month or $0.10/conversion)
- 5,000 conversions/month (~$0.06 per conversion)
- Unlimited file size
- 500 requests/hour
- API access + webhooks
- Batch processing

**ENTERPRISE** (Custom pricing)
- Unlimited conversions
- Dedicated infrastructure
- SLA guarantees

### Market Context
- Competitive with Stedi ($0.01-0.05/transaction) but more focused
- Lower than enterprise solutions ($0.10-0.50/transaction)
- Higher than basic validators ($0.001-0.01/file)
- Value-based pricing for solving X12 complexity pain point

## Development Timeline

**Estimated:** 2.5-3 weeks (15 working days at 3-4 hours/day = ~50-55 total hours)

### Week 1: Foundation (X12 Parser)
- Day 1: Phoenix app setup, dependencies
- Day 2-3: Port flat parser from Python
- Day 4-5: Port structured parser + tests

### Week 2: Features (Web Interface)
- Day 6-7: User accounts + Guardian auth
- Day 8-9: LiveView file upload + UI
- Day 10: Job tracking + download

### Week 3: Polish & Launch
- Day 11-12: Testing + error handling
- Day 13: Pricing tiers implementation
- Day 14: Documentation
- Day 15: Production deployment

## Critical Success Factors

### 1. Reuse Existing Code
- Reference Python parsers for X12 logic
- Leverage Provider_Vault patterns for auth and LiveView
- Don't reinvent solved problems

### 2. Keep It Simple
- Start with email/password auth (OAuth v2.0+)
- Three subscription tiers initially
- Basic but functional UI (polish in v1.1)

### 3. Test Incrementally
- Write tests daily, not at the end
- Use real X12 sample files throughout
- Test each parser pattern as it's implemented

### 4. Avoid Over-Engineering
- Don't add features beyond the scope
- No provider lookup, fraud detection, or claims processing
- Keep focused on translation only

## Code Organization Best Practices

### Context Boundaries
Each context (X12, Accounts, Conversions) should:
- Have a clear, single responsibility
- Expose a clean public API
- Keep implementation details private
- Use schemas for data structures

### Testing Strategy
```
test/
├── x12_bridge/
│   ├── x12/
│   │   ├── parser_test.exs
│   │   └── converter_test.exs
│   ├── accounts/
│   │   └── user_test.exs
│   └── conversions/
│       └── job_test.exs
└── x12_bridge_web/
    └── live/
        └── upload_live_test.exs
```

### File Upload Flow
1. User uploads X12 file via LiveView
2. Create `conversion_job` record (status: pending)
3. Validate file format and size limits
4. Check user's subscription limits
5. Process file (sync for small files, async for large)
6. Update job status and store JSON result
7. Increment user's conversions_used counter
8. Provide download link for JSON

## Deployment

### Recommended Platforms
- **Fly.io** (best for Elixir/Phoenix)
- Railway
- Render
- Heroku (legacy option)

### Environment Variables
```bash
SECRET_KEY_BASE=...
DATABASE_URL=...
GUARDIAN_SECRET_KEY=...
SMTP_HOST=...              # For email notifications
SMTP_USERNAME=...
SMTP_PASSWORD=...
```

## Resources

### External Documentation
- [X12 Standards](https://x12.org/)
- [HIPAA 837P Implementation Guide](https://www.cms.gov/regulations-and-guidance/administrative-simplification/hipaa-aba/downloads/claims837p.pdf)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Guardian Authentication](https://github.com/ueberauth/guardian)
- [Ecto](https://hexdocs.pm/ecto/)

### Project-Specific References
- Python reference implementation: `/Desktop/pyx12_837p_to_json/` (if available)
- Provider_Vault patterns for auth and LiveView (if available in codebase)

## Important Notes for Claude

### When Working on This Project

1. **Always prioritize simplicity** - This is intentionally a focused, single-purpose app
2. **Reference the Python parsers** - They contain proven X12 parsing logic
3. **Use Phoenix contexts** - Keep clean boundaries between X12, Accounts, and Conversions
4. **Test with real X12 files** - Don't assume parsing works without real-world data
5. **Remember the exclusions** - NO provider lookup, fraud detection, or full claims processing
6. **Focus on the user flow** - Upload → Convert → Download (with auth and limits)

### Common X12 Gotchas
- Segments are delimited by `~` (tilde)
- Elements within segments are delimited by `*` (asterisk)
- Sub-elements use `:` (colon)
- Empty elements must be handled (multiple consecutive delimiters)
- Loop hierarchy is logical, not explicit in the file structure

### Performance Considerations
- Large X12 files (10MB+) should use background job processing
- Consider streaming for very large files
- Cache parsed results in JSONB for quick re-download
- Implement rate limiting per subscription tier

---

**Project Status:** Ready for implementation
**Target Launch:** Mid-to-late January 2025
**Risk Level:** Low-Medium (proven patterns, clear scope, existing reference code)
