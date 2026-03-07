# Windows Setup Guide

Complete guide for setting up X12Translator on Windows (native) and WSL (Windows Subsystem for Linux).

---

## Choose Your Path

**Option 1: WSL (Recommended)** - Easier, follows Linux setup
**Option 2: Native Windows** - More complex, requires PowerShell/cmd knowledge

### Quick Recommendation

| Your Experience | Recommended Path |
|-----------------|------------------|
| Comfortable with Linux | **WSL** |
| Windows-only background | **Native Windows** |
| Want easiest setup | **WSL** |
| Need native Windows integration | **Native Windows** |

---

## Option 1: WSL Setup (Recommended)

WSL lets you run a Linux environment directly on Windows. Once set up, follow the standard Linux instructions.

### 1. Install WSL

```powershell
# Run in PowerShell as Administrator
wsl --install

# Restart computer when prompted
```

This installs Ubuntu by default. After restart, launch Ubuntu from Start Menu and create a username/password.

### 2. Install Prerequisites in WSL

```bash
# Update package manager
sudo apt update && sudo apt upgrade -y

# Install Elixir, Erlang, and build tools
sudo apt install -y elixir erlang postgresql postgresql-contrib git curl

# Install asdf (version manager - optional but recommended)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
source ~/.bashrc

# Install Elixir via asdf
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang 26.2.1
asdf install elixir 1.15.7-otp-26
asdf global erlang 26.2.1
asdf global elixir 1.15.7-otp-26
```

### 3. Setup PostgreSQL in WSL

```bash
# Start PostgreSQL
sudo service postgresql start

# Set postgres user password
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"

# Enable PostgreSQL to start automatically
echo "sudo service postgresql start" >> ~/.bashrc
```

### 4. Clone and Setup Project

```bash
# Navigate to your projects directory
cd ~
mkdir -p projects && cd projects

# Clone the repository
git clone https://github.com/donfox/X12Translator.git
cd X12Translator

# Install dependencies and setup
mix deps.get
mix setup

# Start the server
mix phx.server
```

### 5. Access from Windows Browser

WSL provides network access to localhost:
```
http://localhost:4000/converter
```

### WSL Tips

**File Access:**
- Access WSL files from Windows: `\\wsl$\Ubuntu\home\yourusername\projects`
- Access Windows files from WSL: `/mnt/c/Users/YourName/`

**VS Code Integration:**
```bash
# Install VS Code in Windows, then in WSL:
code .
```

**Stop PostgreSQL:**
```bash
sudo service postgresql stop
```

---

## Option 2: Native Windows Setup

### Prerequisites

#### 1. Install Erlang

Download and install from: https://www.erlang.org/downloads

**Recommended:** Erlang/OTP 26.x

```powershell
# Verify installation
erl -version
```

#### 2. Install Elixir

Download installer from: https://elixir-lang.org/install.html#windows

**Recommended:** Use the web installer or Chocolatey:

```powershell
# Using Chocolatey (if installed)
choco install elixir

# Verify installation
elixir --version
```

#### 3. Install PostgreSQL

Download from: https://www.postgresql.org/download/windows/

During installation:
- Set password for `postgres` user (recommend: `postgres` for dev)
- Port: `5432` (default)
- Remember installation path

**Verify:**
```powershell
# Should show PostgreSQL service running
Get-Service postgresql*
```

#### 4. Install Git

Download from: https://git-scm.com/download/win

During installation, select "Use Git from the Windows Command Prompt"

#### 5. Install Node.js (Optional)

Download from: https://nodejs.org/

**Note:** Mix handles asset compilation, but Node.js may be needed for some tools.

### Environment Setup

#### Configure PATH (PowerShell)

```powershell
# Check if Elixir is in PATH
$env:PATH

# If not, add it (adjust paths to match your installation):
# Settings → System → About → Advanced system settings → Environment Variables
# Add to PATH:
#   C:\Program Files\Elixir\bin
#   C:\Program Files\erl-26.2\bin
```

#### PostgreSQL Configuration

**Option A: Use Default Credentials**

The app defaults to `postgres/postgres`. If you set a different password during installation:

```powershell
# Set environment variables in PowerShell
$env:PGUSER = "postgres"
$env:PGPASSWORD = "your_password_here"
$env:PGHOST = "localhost"
$env:PGPORT = "5432"

# To make permanent, add to PowerShell profile:
notepad $PROFILE

# Add these lines:
$env:PGUSER = "postgres"
$env:PGPASSWORD = "your_password_here"
```

**Option B: Update config/dev.exs**

Edit the file to match your PostgreSQL installation:

```elixir
config :x12_translator, X12Translator.Repo,
  username: "postgres",
  password: "your_password_here",
  hostname: "localhost",
  port: 5432,
  database: "x12_translator_dev"
```

### Clone and Setup Project

```powershell
# Navigate to your projects directory
cd C:\Users\YourName\projects

# Clone the repository
git clone https://github.com/donfox/X12Translator.git
cd X12Translator

# Install dependencies
mix deps.get

# Setup database and assets
mix setup

# Start the server
mix phx.server
```

### Access Application

Open browser to:
```
http://localhost:4000/converter
```

---

## Windows PowerShell Equivalents

The repository includes bash scripts that don't work on Windows. Here are equivalents:

### run.sh → run.ps1

Create `run.ps1`:
```powershell
# Start Phoenix server
mix phx.server
```

Run with:
```powershell
.\run.ps1
```

### dev.sh → dev.ps1

Create `dev.ps1`:
```powershell
# Development server with console
iex -S mix phx.server
```

### run_batch_demo.sh → run_batch_demo.ps1

Create `run_batch_demo.ps1`:
```powershell
# Run batch processing demo
mix run demo_batch_processing.exs
```

### Using Command Prompt (cmd)

If you prefer cmd over PowerShell, create `.bat` files:

**run.bat:**
```batch
@echo off
mix phx.server
```

**dev.bat:**
```batch
@echo off
iex -S mix phx.server
```

---

## Common Windows Issues

### 1. PostgreSQL Connection Refused

**Symptoms:**
```
** (DBConnection.ConnectionError) tcp connect (localhost:5432): connection refused
```

**Solutions:**

**Check service is running:**
```powershell
Get-Service postgresql*

# If not running:
Start-Service postgresql-x64-14  # (version may vary)
```

**Check environment variables:**
```powershell
# View all PG variables
Get-ChildItem Env: | Where-Object {$_.Name -like "PG*"}

# If conflicting variables exist, remove them:
Remove-Item Env:\PGHOST
Remove-Item Env:\PGPORT
```

**Verify PostgreSQL is listening:**
```powershell
netstat -an | findstr "5432"
# Should show: TCP    127.0.0.1:5432    0.0.0.0:0    LISTENING
```

### 2. Mix Not Found

**Symptoms:**
```
'mix' is not recognized as an internal or external command
```

**Solution:**

Add Elixir to PATH:
1. Search Windows for "Environment Variables"
2. Click "Environment Variables" button
3. Under "System variables", find "Path"
4. Click "Edit"
5. Click "New"
6. Add: `C:\Program Files\Elixir\bin`
7. Click OK, restart PowerShell

### 3. Compilation Errors with Dependencies

**Symptoms:**
```
Failed to compile dependency :telemetry
```

**Solution:**

Install Visual C++ Build Tools:
```powershell
# Using Chocolatey
choco install visualstudio2022buildtools

# Or download from:
# https://visualstudio.microsoft.com/downloads/
# Select "Build Tools for Visual Studio"
```

### 4. Permission Denied Errors

**Symptoms:**
```
Permission denied @ dir_s_mkdir - _build
```

**Solution:**

Run PowerShell as Administrator or check folder permissions:
```powershell
# Grant full control to current user
icacls "C:\path\to\X12Translator" /grant ${env:USERNAME}:F /T
```

### 5. Long Path Issues

**Symptoms:**
```
File name too long
```

**Solution:**

Enable long paths in Windows:
```powershell
# Run as Administrator
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force

# Restart computer
```

Or enable in Git:
```powershell
git config --system core.longpaths true
```

### 6. Line Ending Issues

**Symptoms:**
Files have `^M` characters or scripts fail to run.

**Solution:**

Configure Git to handle line endings:
```powershell
# In X12Translator directory
git config core.autocrlf true

# Reset files
git rm --cached -r .
git reset --hard
```

---

## Database Management (Windows)

### Start/Stop PostgreSQL

**Using Services:**
```powershell
# Start
Start-Service postgresql-x64-14

# Stop
Stop-Service postgresql-x64-14

# Status
Get-Service postgresql-x64-14
```

**Using pg_ctl (Advanced):**
```powershell
# Find data directory (usually):
# C:\Program Files\PostgreSQL\14\data

# Start
pg_ctl start -D "C:\Program Files\PostgreSQL\14\data"

# Stop
pg_ctl stop -D "C:\Program Files\PostgreSQL\14\data"
```

### Accessing PostgreSQL Command Line

```powershell
# psql (ensure PostgreSQL bin is in PATH)
psql -U postgres

# Or use full path:
& "C:\Program Files\PostgreSQL\14\bin\psql.exe" -U postgres
```

### Reset Database

```powershell
# Drop and recreate database
mix ecto.reset
```

---

## Development Workflow (Windows)

### Starting Development

```powershell
# 1. Ensure PostgreSQL is running
Get-Service postgresql*

# 2. Start Phoenix server
mix phx.server

# 3. Open browser
start http://localhost:4000/converter
```

### Running Tests

```powershell
# All tests
mix test

# Specific file
mix test test\x12_translator\x12\parser_test.exs

# With coverage
mix test --cover
```

### Code Quality

```powershell
# Format code
mix format

# Compile with warnings
mix compile --warnings-as-errors
```

### Interactive Console

```powershell
# Start IEx with Phoenix
iex -S mix phx.server

# Or without Phoenix
iex -S mix
```

---

## File Paths in Windows

Elixir uses forward slashes `/` even on Windows, but some tools need backslashes `\`.

**In Elixir code (use forward slashes):**
```elixir
File.read!("priv/test_data/sample.x12")
```

**In PowerShell (use backslashes or quotes):**
```powershell
Get-Content .\priv\test_data\sample.x12
# Or
Get-Content "priv/test_data/sample.x12"
```

**Mix handles both:**
```powershell
mix test test\support\helpers.exs  # Works
mix test test/support/helpers.exs  # Also works
```

---

## Performance Considerations

Windows may be slightly slower than Linux/macOS for Elixir development due to:
- File system performance (especially in `deps/` and `_build/`)
- Windows Defender scanning

**Optimizations:**

1. **Exclude project folder from Windows Defender:**
   - Settings → Update & Security → Windows Security → Virus & threat protection
   - Manage settings → Exclusions → Add folder
   - Add: `C:\Users\YourName\projects\X12Translator`

2. **Use SSD** for project files (not HDD)

3. **Consider WSL** for better performance on very large projects

---

## IDE Setup (Windows)

### Visual Studio Code

1. Install VS Code: https://code.microsoft.com/
2. Install Extensions:
   - ElixirLS (Elixir language server)
   - Phoenix Framework
   - Elixir Formatter

**Settings (`.vscode/settings.json`):**
```json
{
  "elixirLS.projectDir": "",
  "elixirLS.mixEnv": "dev",
  "elixir.formatOnSave": true,
  "[elixir]": {
    "editor.formatOnSave": true
  }
}
```

### IntelliJ IDEA / RubyMine

1. Install Elixir plugin
2. Configure Elixir SDK to point to your Elixir installation
3. Enable Mix projects auto-import

---

## Quick Reference

### Common Commands

```powershell
# Setup (first time)
mix deps.get
mix setup

# Development
mix phx.server                 # Start server
iex -S mix phx.server          # Start with console

# Database
mix ecto.create                # Create database
mix ecto.migrate               # Run migrations
mix ecto.reset                 # Reset database

# Testing
mix test                       # Run tests
mix format                     # Format code

# PostgreSQL
Start-Service postgresql*      # Start database
Stop-Service postgresql*       # Stop database
Get-Service postgresql*        # Check status
```

### Environment Variables

```powershell
# Set temporarily (current session)
$env:PGPASSWORD = "your_password"

# Set permanently (add to profile)
notepad $PROFILE
# Add: $env:PGPASSWORD = "your_password"
```

### Troubleshooting Commands

```powershell
# Check Elixir installation
elixir --version

# Check PostgreSQL status
Get-Service postgresql*

# Check port 4000 (Phoenix)
netstat -an | findstr "4000"

# Check port 5432 (PostgreSQL)
netstat -an | findstr "5432"

# View environment variables
Get-ChildItem Env: | Where-Object {$_.Name -like "PG*"}
```

---

## Next Steps

After successful setup:

1. Visit http://localhost:4000/converter
2. Try uploading a sample X12 file from `priv/test_data/`
3. Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand the system
4. Read [API.md](API.md) for module reference

---

## Getting Help

- **PostgreSQL issues:** See "Common Windows Issues" above
- **Environment variables:** [SETUP_TROUBLESHOOTING.md](SETUP_TROUBLESHOOTING.md)
- **General setup:** Follow WSL path if native Windows is problematic

---

**Last Updated:** January 2026
