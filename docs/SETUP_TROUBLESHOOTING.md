# Setup Troubleshooting

Quick fixes for common setup issues on Ubuntu and macOS.

---

## TL;DR - Ubuntu Quick Fix

If you're getting **both** connection refused and rebar3 errors:

```bash
# Fix both issues at once
unset PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE
chmod 644 ~/.config/rebar3/rebar.config 2>/dev/null || mkdir -p ~/.config/rebar3
sudo systemctl start postgresql
mix setup
```

**Why:** Old PostgreSQL environment variables (possibly from a previous project) are pointing to a non-existent server, and rebar3 config has permission issues.

---

## Environment Variable Conflicts (Most Common)

### Symptoms
```bash
$ mix setup
** (DBConnection.ConnectionError) tcp connect (hostname:port): connection refused
```

### Cause
PostgreSQL environment variables override `config/dev.exs` settings.

**Priority:** `PGHOST` env var > `hostname:` in config > localhost default

### Fix
```bash
# 1. Check what's set
env | grep PG

# 2. Unset conflicting variables
unset PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE

# 3. Run setup
mix setup
```

### Make Permanent
Check shell config files:
```bash
grep -r "PGHOST\|PGPORT" ~/.bashrc ~/.bash_profile ~/.zshrc
```

Comment out or remove those lines, then `source ~/.bashrc`

---

## rebar3 Permission Error (Ubuntu)

### Symptoms
```bash
Error reading file ~/.config/rebar3/rebar.config: permission denied
** (Mix) Could not compile dependency :telemetry
```

### Fix
```bash
chmod 644 ~/.config/rebar3/rebar.config

# Or remove and recreate
rm -rf ~/.config/rebar3
mkdir -p ~/.config/rebar3
```

---

## Custom Database Server

If you want to use a different database server (not localhost):

### Set Environment Variables
```bash
export PGHOST=your-db-host
export PGPORT=your-db-port
export PGUSER=your-db-user
export PGPASSWORD=your-db-password

# Test connection
psql -c "SELECT 1"

# Run setup
mix setup
```

When prompted about environment variables, type `y` to continue.

---

## PostgreSQL Not Running

### Check Status
```bash
# macOS
brew services list | grep postgresql

# Ubuntu
sudo systemctl status postgresql
```

### Start Service
```bash
# macOS
brew services start postgresql@14

# Ubuntu
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### First-Time Setup (Ubuntu)
```bash
sudo apt-get install postgresql
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"
```

---

## Validation Tools

### Before Setup
Run validation to see effective configuration:
```bash
bash priv/scripts/check_setup.sh
```

### During Setup
`mix setup` automatically warns about environment variable conflicts.

---

## Quick Reference

| Issue | Fix |
|-------|-----|
| Wrong host/port | `unset PGHOST PGPORT` |
| rebar3 permissions | `chmod 644 ~/.config/rebar3/rebar.config` |
| PostgreSQL not running | `brew services start postgresql@14` (macOS)<br>`sudo systemctl start postgresql` (Ubuntu) |
| Custom database | Set `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` |

---

## Still Having Issues?

1. Run validation: `bash priv/scripts/check_setup.sh`
2. Check environment: `env | grep PG`
3. Test PostgreSQL: `psql -h localhost -U postgres -c "SELECT 1"`
4. See [README.md](../README.md) and [WINDOWS_SETUP.md](WINDOWS_SETUP.md) for detailed setup instructions
