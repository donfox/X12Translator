# X12Bridge Complete Guide

**Everything you need to install, use, and understand X12Bridge**

This guide combines setup instructions, user documentation, and Elixir fundamentals in one comprehensive resource.

---

## Table of Contents

### Part 1: Quick Start
- [Prerequisites](#prerequisites)
- [Quick Setup](#quick-setup)
- [First Conversion](#first-conversion)

### Part 2: Installation & Setup
- [Detailed Installation](#detailed-installation)
- [Database Setup](#database-setup)
- [Running the Application](#running-the-application)
- [Testing](#testing)

### Part 3: Using X12Bridge
- [Converting X12 Files](#converting-x12-files)
- [Understanding Results](#understanding-results)
- [Validation](#validation)
- [Batch Processing](#batch-processing-ui)
- [Troubleshooting Common Issues](#troubleshooting-common-issues)

### Part 4: Understanding Elixir
- [What is Elixir?](#what-is-elixir)
- [Basic Syntax](#basic-elixir-syntax)
- [Pattern Matching](#pattern-matching)
- [The Pipe Operator](#the-pipe-operator)
- [Phoenix LiveView](#phoenix-liveview)
- [Code Flow in X12Bridge](#understanding-x12bridge-code-flow)

### Part 5: Development
- [Development Workflow](#development-workflow)
- [Interactive Development](#interactive-development)
- [Debugging Tips](#debugging-tips)

### Part 6: Production
- [Production Deployment](#production-deployment)
- [Deployment Platforms](#deployment-platforms)

---

# Part 1: Quick Start

## Prerequisites

### Required Software

1. **Elixir 1.15 or higher**
   ```bash
   elixir --version
   # Elixir 1.15.x or higher
   ```

2. **Erlang/OTP 25 or higher**
   ```bash
   erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
   # 25 or higher
   ```

3. **PostgreSQL 14 or higher**
   ```bash
   psql --version
   # PostgreSQL 14.x or higher
   ```

4. **Node.js 18 or higher** (for asset compilation)
   ```bash
   node --version
   # v18.x.x or higher
   ```

### Installing Prerequisites

#### macOS (using Homebrew)

```bash
# Install Elixir (includes Erlang)
brew install elixir

# Install PostgreSQL
brew install postgresql@14
brew services start postgresql@14

# Install Node.js
brew install node
```

#### Ubuntu/Debian

```bash
# Install Erlang and Elixir
sudo apt-get update
sudo apt-get install elixir

# Install PostgreSQL
sudo apt-get install postgresql postgresql-contrib
sudo systemctl start postgresql

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install nodejs
```

---

## Quick Setup

Get up and running in 3 commands:

```bash
# 1. Clone the repository
git clone <repository-url>
cd X12Bridge

# 2. Install dependencies and setup database
mix setup

# 3. Start the Phoenix server
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000) in your browser.

---

## First Conversion

### Try a Sample File

1. Navigate to [http://localhost:4000/converter](http://localhost:4000/converter)
2. Click **"Load 837P Sample"**
3. Click **"Validate & Convert to JSON"**
4. See the JSON result below!

**Congratulations!** You just converted your first X12 file to JSON.

---

# Part 2: Installation & Setup

## Detailed Installation

### Step 1: Clone the Repository

```bash
git clone <repository-url>
cd X12Bridge
```

### Step 2: Install Dependencies

```bash
# Install Elixir dependencies
mix deps.get

# Install Node.js dependencies and build assets
cd assets && npm install && cd ..
```

### Step 3: Configure Database

Edit `config/dev.exs` if needed (default uses local PostgreSQL):

```elixir
config :x12_bridge, X12Bridge.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "x12_bridge_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

### Step 4: Create and Migrate Database

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# (Optional) Seed database
mix run priv/repo/seeds.exs
```

### Step 5: Compile Assets

```bash
# Install Tailwind CSS
mix tailwind.install

# Install esbuild
mix esbuild.install

# Build assets
mix assets.build
```

### Step 6: Verify Installation

```bash
# Compile the project
mix compile

# Run tests to verify everything works
mix test
```

---

## Database Setup

### Database Configuration Files

- **Development**: `config/dev.exs`
- **Test**: `config/test.exs`
- **Production**: `config/runtime.exs` (uses `DATABASE_URL` environment variable)

### Manual Database Commands

```bash
# Create database
mix ecto.create

# Drop database
mix ecto.drop

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Check migration status
mix ecto.migrations
```

### Database Schema

The database includes two main tables:

**conversion_batches**
- Tracks batch processing jobs
- Fields: id, name, total_files, completed_files, failed_files, status

**conversion_jobs**
- Tracks individual file conversions within batches
- Fields: id, batch_id, original_filename, file_size, status, json_result, error_message, processing_time_ms, progress

For complete schema details, see [DATABASE.md](DATABASE.md).

---

## Running the Application

### Development Mode

Start the Phoenix server with live code reloading:

```bash
mix phx.server
```

Or inside an interactive Elixir shell:

```bash
iex -S mix phx.server
```

The application will be available at:
- **Web Interface**: [http://localhost:4000](http://localhost:4000)
- **Converter**: [http://localhost:4000/converter](http://localhost:4000/converter)
- **Batch Processing**: [http://localhost:4000/batch](http://localhost:4000/batch)

### Running in Background

```bash
# Start server in detached mode
mix phx.server &

# Or use screen/tmux for persistent sessions
screen -S x12bridge
mix phx.server
# Ctrl+A, D to detach
```

### Stopping the Server

- If running in foreground: `Ctrl+C` twice
- If running in background: `kill <process_id>`
- If in IEx: `Ctrl+C` twice

---

## Testing

### Run All Tests

```bash
mix test
```

### Run Specific Tests

```bash
# Test specific file
mix test test/x12_bridge/x12/parser_test.exs

# Test specific line
mix test test/x12_bridge/x12/parser_test.exs:42

# Run only tests with specific tag
mix test --only integration
```

### Test Coverage

```bash
# Run tests with coverage
mix test --cover
```

---

# Part 3: Using X12Bridge

## Converting X12 Files

You have three ways to provide X12 content:

### Method 1: Try Sample Files (Quickest)

Perfect for testing or learning how X12Bridge works.

1. Click one of the sample buttons:
   - **Load 837P Sample** - Professional claim example
   - **Load 837I Sample** - Institutional claim example
   - **Load 837D Sample** - Dental claim example

2. The X12 content will load automatically
3. Click **"Validate & Convert to JSON"**
4. See results below

### Method 2: Upload a File

Best for converting your own X12 files.

1. Find the **"Upload X12 File"** section
2. Click the upload area or drag and drop your file
3. Accepted formats: `.x12`, `.edi`, `.txt`
4. Click **"Upload File"**
5. The file content will appear in the X12 Content section
6. Click **"Validate & Convert to JSON"**

### Method 3: Paste Content Directly

Good for small snippets or testing.

1. Scroll to the **"X12 Content"** text area
2. Paste your X12 EDI content
3. Click **"Validate & Convert to JSON"**

---

## Understanding Results

### Validation Results

After clicking "Validate & Convert", you'll see validation results:

#### Valid File ✓
```
✓ VALID
156 segments processed
No validation issues found!
```

Your file is structurally correct and ready for conversion.

#### Invalid File ✗
```
✗ INVALID
156 segments processed
```

You'll see a list of issues categorized by severity:

**🔴 Errors** (Red border)
- Must be fixed for successful conversion
- Example: "Missing required Billing Provider (NM1*85)"

**🟡 Warnings** (Yellow border)
- Should be reviewed but conversion may still work
- Example: "Date year 2099 seems unusual"

**🔵 Info** (Blue border)
- Informational messages
- Example: "Segment ID 'XYZ' not recognized"

Each issue shows:
```
[SEGMENT:LINE] Message
Context (if available)
```

### JSON Output

If conversion succeeds, you'll see formatted JSON output:

```json
{
  "transaction": {
    "type": "837",
    "control_number": "0001",
    ...
  },
  "claims": [
    {
      "claim_id": "CLAIM123",
      "total_charge": 150.00,
      "service_lines": [...]
    }
  ],
  "summary": {
    "total_claims": 1,
    "total_service_lines": 2
  }
}
```

#### Working with JSON Output

You have two options:

1. **Download JSON**
   - Click the **"Download JSON"** button
   - File will be saved as `x12_converted.json`
   - Open in any text editor or JSON viewer

2. **Copy JSON**
   - Click the **"Copy JSON"** button
   - Paste into your application, API tool, or text editor

---

## Validation

### Validation Only (Without Conversion)

Sometimes you just want to check if an X12 file is valid:

1. Load your X12 content (upload, paste, or sample)
2. Click **"Validate Only"**
3. See validation results without converting to JSON
4. Faster than full conversion

### What Gets Validated

X12Bridge checks:

#### Structure
- File starts with ISA segment
- ISA segment is at least 106 characters
- Valid delimiters (*, :, ~)
- Recognized segment IDs

#### Envelopes
- ISA/IEA control numbers match
- GS/GE control numbers match
- ST/SE control numbers match
- Transaction type is "837"
- Segment counts are correct

#### Content
- Entity codes are valid (NM1 segments)
- Claim amounts are valid numbers (CLM segments)
- Dates are in CCYYMMDD format and valid (DTP segments)
- Diagnosis codes are present (HI segments)
- Service line charges are valid (SV1/SV2/SV3 segments)

#### Business Rules
- Required entities are present:
  - Billing Provider (NM1*85)
  - Subscriber/Insured (NM1*IL)
  - Claim Information (CLM segment)
- Claim total matches sum of service lines (within $0.01)

---

## Batch Processing UI

For converting multiple files at once, use the batch processing interface.

### Accessing Batch Processing

Navigate to `http://localhost:4000/batch`

### How to Use

1. **Upload Multiple Files**
   - Click upload area or drag and drop multiple files
   - All files must be X12 format (.x12, .edi, .txt)

2. **Start Processing**
   - Click **"Process Batch"**
   - See real-time progress for each file

3. **Review Results**
   - ✓ Green checkmarks = Successfully converted
   - ✗ Red X marks = Failed to convert
   - Click on individual files to see details

4. **Download Results**
   - Download successful conversions as JSON
   - Review error messages for failed files

For command-line batch processing, see [BATCH_PROCESSING.md](BATCH_PROCESSING.md).

---

## Troubleshooting Common Issues

### "File too short to contain valid ISA segment"

**Problem:** File is smaller than 106 bytes or doesn't start with ISA.

**Solution:**
- Verify file contains valid X12 EDI data
- Check that file starts with `ISA`
- Ensure file isn't corrupted

---

### "File must start with ISA segment"

**Problem:** File doesn't begin with ISA interchange header.

**Solution:**
- X12 files must start with ISA segment
- Remove any header text or blank lines before ISA
- Verify file format is X12 EDI, not CSV or other format

---

### "Missing required Billing Provider (NM1*85)"

**Problem:** Required billing provider information is missing.

**Solution:**
- Ensure your X12 file includes an NM1 segment with entity code "85"
- This is required for all 837 claim transactions
- Check your X12 source/generator

---

### "Claim amount does not match service line total"

**Problem:** The CLM02 (total claim amount) doesn't equal the sum of service line charges.

**Solution:**
- This is a warning, not an error - conversion will still work
- Review the claim amounts for accuracy
- Check if there are missing service lines
- Verify service line charges are correct

---

### Port 4000 already in use

**Problem:** Another process is using port 4000.

**Solution:**

1. Find the process:
   ```bash
   # macOS/Linux
   lsof -i :4000
   ```

2. Kill the process:
   ```bash
   kill -9 <PID>
   ```

3. Or change port in `config/dev.exs`:
   ```elixir
   config :x12_bridge, X12BridgeWeb.Endpoint,
     http: [port: 4001]  # Change from 4000 to 4001
   ```

---

### "Connection refused" error when connecting to database

**Problem:** PostgreSQL is not running.

**Solution:**

Start PostgreSQL:
```bash
# macOS
brew services start postgresql@14

# Linux
sudo systemctl start postgresql

# Check status
psql -U postgres -c "SELECT version();"
```

---

# Part 4: Understanding Elixir

## What is Elixir?

Elixir is a **functional programming language** that runs on the Erlang VM. Think of it like this:

- **JavaScript/Python**: Change variables, loop through things
- **Elixir**: Transform data through pipelines, never change variables

**Key Concept**: In Elixir, once you set a variable, it never changes. Instead, you create new variables with transformed data.

---

## Basic Elixir Syntax

### Variables and Data Types

```elixir
# Simple values
name = "John"
age = 30
price = 99.99
is_valid = true

# Lists (like arrays)
numbers = [1, 2, 3, 4, 5]
names = ["Alice", "Bob", "Carol"]

# Maps (like objects/dictionaries)
person = %{
  name: "John",
  age: 30,
  city: "NYC"
}

# Access map values
person.name        # => "John"
person[:name]      # => "John"
Map.get(person, :name)  # => "John"
```

### Atoms (Symbols)

```elixir
# Atoms start with :
:ok
:error
:pending

# They're like string constants but more efficient
# Used for status values, keys, etc.
```

### Tuples (Fixed-size containers)

```elixir
# Success/error pattern (VERY common in Elixir)
{:ok, result} = parse_file(content)
{:error, reason} = parse_file(bad_content)

# Pattern matching on tuples
case parse_file(content) do
  {:ok, data} ->
    # Use data
  {:error, reason} ->
    # Handle error
end
```

---

## Pattern Matching

Instead of if/else everywhere, Elixir uses pattern matching:

```elixir
# Traditional (other languages)
if (status == "ok") {
  doSomething(result);
} else {
  handleError(reason);
}

# Elixir pattern matching
case parse_file(content) do
  {:ok, result} -> do_something(result)
  {:error, reason} -> handle_error(reason)
end
```

**In X12Bridge example** ([parser.ex:45-50](../lib/x12_bridge/x12/parser.ex#L45-L50)):

```elixir
def parse(content) when is_binary(content) do
  with {:ok, delimiters} <- parse_delimiters(content),
       {:ok, segments} <- parse_segments(content, delimiters) do
    {:ok, %{delimiters: delimiters, segments: segments}}
  end
end
```

**What's happening:**
1. `with` tries each step
2. If `parse_delimiters` returns `{:ok, delimiters}`, continue
3. If `parse_segments` returns `{:ok, segments}`, continue
4. If everything works, return `{:ok, map}`
5. If anything fails, return the `{:error, reason}` automatically

---

## The Pipe Operator `|>`

This is like Unix pipes but for data:

```elixir
# Without pipes (hard to read)
result = process(clean(parse(content)))

# With pipes (reads top to bottom)
result = content
  |> parse()
  |> clean()
  |> process()
```

**Real example from X12Bridge** ([parser.ex:95-112](../lib/x12_bridge/x12/parser.ex#L95-L112)):

```elixir
def parse_segments(content, %Delimiters{} = delimiters) do
  segments =
    content
    |> String.split(delimiters.segment, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.length(&1) > 0))
    |> Enum.with_index(1)
    |> Enum.map(fn {raw_segment, line_num} ->
      # Build segment struct
    end)

  {:ok, segments}
end
```

**Step by step:**
1. Take content string
2. Split by segment delimiter (`~`)
3. Trim whitespace from each piece
4. Filter out empty strings
5. Add line numbers (starting at 1)
6. Build segment structs
7. Return `{:ok, segments}`

---

## Modules and Functions

```elixir
defmodule MyModule do
  # Public function (accessible from outside)
  def public_function(arg) do
    # Do something
  end

  # Private function (only usable inside this module)
  defp private_function(arg) do
    # Do something
  end
end

# Call it
MyModule.public_function("hello")
```

### Guards

```elixir
# Function only runs if content is a binary string
def parse(content) when is_binary(content) do
  # ...
end

# Function only runs if number > 0
def process(num) when num > 0 do
  # ...
end
```

---

## Structs (Custom Data Types)

```elixir
defmodule Person do
  defstruct [:name, :age, :city]
end

# Create a struct
person = %Person{name: "John", age: 30, city: "NYC"}

# Access fields
person.name  # => "John"

# Update (creates NEW struct, doesn't modify original)
older_person = %{person | age: 31}
```

---

## Enum (Working with Lists)

```elixir
numbers = [1, 2, 3, 4, 5]

# Map (transform each item)
doubled = Enum.map(numbers, fn n -> n * 2 end)
# => [2, 4, 6, 8, 10]

# Filter (keep only items that match)
evens = Enum.filter(numbers, fn n -> rem(n, 2) == 0 end)
# => [2, 4]

# Reduce (combine into single value)
sum = Enum.reduce(numbers, 0, fn n, acc -> n + acc end)
# => 15

# Count
count = Enum.count(numbers)
# => 5
```

**Shorthand syntax:**

```elixir
# Instead of: fn n -> n * 2 end
# Use: &(&1 * 2)

doubled = Enum.map(numbers, &(&1 * 2))
```

---

## Phoenix LiveView

LiveView lets you build interactive UIs without JavaScript.

### How it works

```mermaid
sequenceDiagram
    participant Browser
    participant LiveView
    participant Server

    Browser->>LiveView: Initial page load
    LiveView->>Browser: Render HTML
    Browser->>LiveView: WebSocket connection
    Browser->>LiveView: User clicks button
    LiveView->>Server: handle_event("button_click")
    Server->>LiveView: Update state
    LiveView->>Browser: Re-render changed parts
```

### Basic structure

```elixir
defmodule MyAppWeb.PageLive do
  use MyAppWeb, :live_view

  # Runs once when page loads
  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  # Handles user events (clicks, form submits, etc.)
  def handle_event("increment", _params, socket) do
    {:noreply, assign(socket, count: socket.assigns.count + 1)}
  end

  # Renders HTML
  def render(assigns) do
    ~H"""
    <div>
      <p>Count: <%= @count %></p>
      <button phx-click="increment">Increment</button>
    </div>
    """
  end
end
```

### Handling events

```elixir
# User clicks "Convert" button
def handle_event("convert", _params, socket) do
  content = socket.assigns.x12_content

  case Converter.convert_content(content) do
    {:ok, json} ->
      {:noreply, assign(socket, json_result: json)}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed: #{reason}")}
  end
end
```

**In HTML:**

```heex
<button phx-click="convert">Convert</button>
```

When user clicks, it calls `handle_event("convert", ...)`.

---

## Understanding X12Bridge Code Flow

### 1. User uploads file

```elixir
def handle_event("upload_file", _params, socket) do
  uploaded_files =
    consume_uploaded_entries(socket, :x12_file, fn %{path: path}, _entry ->
      case File.read(path) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:postpone, reason}
      end
    end)

  case uploaded_files do
    [content | _] ->
      {:noreply, assign(socket, :x12_content, content)}
    [] ->
      {:noreply, put_flash(socket, :error, "No file uploaded")}
  end
end
```

**Step by step:**
1. LiveView receives upload
2. Read file from temp path
3. If successful, store content in socket state
4. Re-render page with content

### 2. Parse X12 content

```elixir
def parse(content) when is_binary(content) do
  with {:ok, delimiters} <- parse_delimiters(content),
       {:ok, segments} <- parse_segments(content, delimiters) do
    {:ok, %{delimiters: delimiters, segments: segments}}
  end
end
```

**Step by step:**
1. Extract delimiters from ISA segment
2. Split content into segments using delimiters
3. Return both delimiters and segments
4. If any step fails, return error

### 3. Convert to JSON

```elixir
def convert_content(content) when is_binary(content) do
  with {:ok, %{delimiters: delimiters, segments: segments}} <- Parser.parse(content),
       {:ok, structured_data} <- build_structure(segments, delimiters) do
    Jason.encode(structured_data, pretty: true)
  end
end
```

**Step by step:**
1. Parse X12 (get delimiters and segments)
2. Build hierarchical structure (claims with service lines)
3. Encode to JSON string
4. Return formatted JSON

---

## Common Patterns You'll See

### 1. Error Tuple Pattern

```elixir
case do_something() do
  {:ok, result} -> use_result(result)
  {:error, reason} -> handle_error(reason)
end
```

**Why:** Explicit error handling, no exceptions

### 2. With Statement (Chain operations)

```elixir
with {:ok, step1} <- do_step1(),
     {:ok, step2} <- do_step2(step1),
     {:ok, step3} <- do_step3(step2) do
  {:ok, step3}
end
```

**Why:** Stop at first error, clean code

### 3. Pipe Transform

```elixir
data
|> step1()
|> step2()
|> step3()
```

**Why:** Reads like a recipe, clear flow

### 4. Pattern Match Functions

```elixir
def extract_entity(nil), do: nil

def extract_entity(%Segment{} = nm1) do
  # Extract entity details
end
```

**Why:** Handle different inputs cleanly

### 5. Update Immutably

```elixir
# Don't change original
original_map = %{count: 0}

# Create new map with changes
new_map = %{original_map | count: 1}

# original_map is still %{count: 0}
```

**Why:** Safe concurrency, no surprises

---

## Key Differences from Other Languages

| Other Languages | Elixir |
|----------------|--------|
| Variables change | Variables never change |
| Objects with methods | Modules with functions |
| Classes and inheritance | Modules and composition |
| for/while loops | Recursion and Enum |
| Exceptions everywhere | {:ok/:error} tuples |
| Null/undefined | nil or pattern match |
| Threads/mutexes | Processes (lightweight) |

---

# Part 5: Development

## Development Workflow

### Useful Mix Commands

```bash
# Compile with warnings as errors
mix compile --warnings-as-errors

# Format code
mix format

# Check formatting without changing files
mix format --check-formatted

# Get dependencies
mix deps.get

# Clean dependencies
mix deps.clean --all
```

### Code Reloading

Phoenix supports hot code reloading in development:

1. Edit any `.ex` file
2. Save the file
3. Reload browser page - changes apply automatically
4. No need to restart server

**Note**: Changes to `config/` files require server restart.

---

## Interactive Development

Use IEx for interactive development:

```bash
iex -S mix phx.server
```

Then interact with modules:

```elixir
# Parse X12 content
{:ok, result} = X12Bridge.X12.Parser.parse(content)

# Convert to JSON
{:ok, json} = X12Bridge.X12.Converter.convert_content(content)

# Validate
result = X12Bridge.X12.Validator.validate_content(content)

# Reload modules after changes
r X12Bridge.X12.Parser
```

---

## Debugging Tips

### 1. IO.inspect (Print debugging)

```elixir
content
|> Parser.parse()
|> IO.inspect(label: "After parse")
|> Converter.convert_content()
|> IO.inspect(label: "After convert")
```

### 2. IEx (Interactive Shell)

```bash
iex -S mix phx.server

# Try functions
iex> content = File.read!("test.x12")
iex> {:ok, result} = X12Bridge.X12.Parser.parse(content)
iex> result.segments |> length()
```

### 3. Logs

```elixir
require Logger

Logger.info("Processing file: #{filename}")
Logger.error("Failed to parse: #{inspect(reason)}")
```

### 4. Tests

```bash
# Run specific test
mix test test/x12_bridge/x12/parser_test.exs:42

# Run all tests
mix test

# Run with verbose output
mix test --trace
```

---

# Part 6: Production

## Production Deployment

### Environment Variables

Set these environment variables in production:

```bash
# Required
export SECRET_KEY_BASE="<generate with: mix phx.gen.secret>"
export DATABASE_URL="postgresql://user:pass@host/db_name"

# Optional
export PHX_HOST="yourdomain.com"
export PORT="4000"
export POOL_SIZE="10"
```

### Generate Secret Key

```bash
mix phx.gen.secret
```

Copy the output and set as `SECRET_KEY_BASE`.

### Build Release

```bash
# Set environment to production
export MIX_ENV=prod

# Install dependencies
mix deps.get --only prod

# Compile assets
mix assets.deploy

# Compile application
mix compile

# Build release
mix release
```

### Run Release

```bash
# Set environment variables first (see above)
export SECRET_KEY_BASE="..."
export DATABASE_URL="..."

# Run migrations
_build/prod/rel/x12_bridge/bin/x12_bridge eval "X12Bridge.Release.migrate"

# Start server
_build/prod/rel/x12_bridge/bin/x12_bridge start
```

---

## Deployment Platforms

### Fly.io (Recommended)

1. Install Fly CLI
   ```bash
   curl -L https://fly.io/install.sh | sh
   ```

2. Login and initialize
   ```bash
   fly auth login
   fly launch
   ```

3. Set secrets
   ```bash
   fly secrets set SECRET_KEY_BASE="<your-secret>"
   ```

4. Deploy
   ```bash
   fly deploy
   ```

### Docker

Create `Dockerfile`:

```dockerfile
FROM elixir:1.15-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base npm git

# Set working directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy application files
COPY . .

# Compile and build release
RUN mix compile
RUN mix assets.deploy
RUN mix release

# Start a new stage for smaller image size
FROM alpine:3.18
RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app
COPY --from=build /app/_build/prod/rel/x12_bridge ./

EXPOSE 4000
CMD ["bin/x12_bridge", "start"]
```

Build and run:

```bash
docker build -t x12_bridge .
docker run -p 4000:4000 \
  -e SECRET_KEY_BASE="<secret>" \
  -e DATABASE_URL="<db_url>" \
  x12_bridge
```

---

## Next Steps

1. **Read the code in order:**
   - Start with [parser.ex](../lib/x12_bridge/x12/parser.ex) - Simplest
   - Then [converter.ex](../lib/x12_bridge/x12/converter.ex) - Uses parser
   - Then [converter_live.ex](../lib/x12_bridge_web/live/converter_live.ex) - Uses both

2. **Try things in IEx:**
   ```bash
   iex -S mix
   ```

3. **Read more documentation:**
   - [API Reference](API_REFERENCE.md) - Complete API docs
   - [Architecture](ARCHITECTURE.md) - System design and diagrams
   - [Database](DATABASE.md) - Schema and ERD
   - [Batch Processing](BATCH_PROCESSING.md) - Automated file processing

---

## Resources

- **Elixir Official**: https://elixir-lang.org/
- **Elixir School**: https://elixirschool.com/en
- **Phoenix Docs**: https://hexdocs.pm/phoenix/
- **Ecto Docs**: https://hexdocs.pm/ecto/
- **Phoenix Getting Started**: https://hexdocs.pm/phoenix/overview.html

---

**Version:** 1.0
**Last Updated:** January 2026
