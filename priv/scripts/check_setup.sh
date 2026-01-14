#!/usr/bin/env bash
# Setup validation script for X12Bridge
# Checks for common configuration issues before running mix setup

set -e

echo "🔍 X12Bridge Setup Validator"
echo "============================"
echo ""

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

# Determine which database config will be used
echo "📋 Detecting database configuration..."
echo ""

# Check for PostgreSQL environment variables
PGHOST_VAR="${PGHOST:-localhost}"
PGPORT_VAR="${PGPORT:-5432}"
PGUSER_VAR="${PGUSER:-postgres}"
PGDATABASE_VAR="${PGDATABASE:-x12_bridge_dev}"

# Default config from config/dev.exs
CONFIG_HOST="localhost"
CONFIG_PORT="5432"
CONFIG_USER="postgres"
CONFIG_DB="x12_bridge_dev"

# Determine what will actually be used (env vars override config)
EFFECTIVE_HOST="${PGHOST:-$CONFIG_HOST}"
EFFECTIVE_PORT="${PGPORT:-$CONFIG_PORT}"
EFFECTIVE_USER="${PGUSER:-$CONFIG_USER}"
EFFECTIVE_DB="${PGDATABASE:-$CONFIG_DB}"

if [ -n "$PGHOST" ] || [ -n "$PGPORT" ] || [ -n "$PGUSER" ] || [ -n "$PGDATABASE" ]; then
  echo -e "${BLUE}ℹ️  PostgreSQL environment variables detected (these override config/dev.exs):${NC}"
  [ -n "$PGHOST" ] && echo "  PGHOST=$PGHOST"
  [ -n "$PGPORT" ] && echo "  PGPORT=$PGPORT"
  [ -n "$PGUSER" ] && echo "  PGUSER=$PGUSER"
  [ -n "$PGDATABASE" ] && echo "  PGDATABASE=$PGDATABASE"
  echo ""
fi

echo -e "${BLUE}📍 Effective database configuration:${NC}"
echo "  Host:     $EFFECTIVE_HOST"
echo "  Port:     $EFFECTIVE_PORT"
echo "  User:     $EFFECTIVE_USER"
echo "  Database: $EFFECTIVE_DB"
echo ""

# Check if PostgreSQL is reachable
echo "🗄️  Checking PostgreSQL connection..."

# Try with configured password first
if [ -n "$PGPASSWORD" ]; then
  PASSWORD_SOURCE="PGPASSWORD environment variable"
  TEST_PASSWORD="$PGPASSWORD"
else
  PASSWORD_SOURCE="default (postgres)"
  TEST_PASSWORD="postgres"
fi

if PGPASSWORD="$TEST_PASSWORD" psql -h "$EFFECTIVE_HOST" -p "$EFFECTIVE_PORT" -U "$EFFECTIVE_USER" -c "SELECT 1" &> /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} PostgreSQL connection successful!"
  echo "  Using password from: $PASSWORD_SOURCE"
else
  echo -e "${RED}✗${NC} Cannot connect to PostgreSQL with current configuration"
  echo ""
  echo "Connection details:"
  echo "  Host: $EFFECTIVE_HOST"
  echo "  Port: $EFFECTIVE_PORT"
  echo "  User: $EFFECTIVE_USER"
  echo ""
  echo "Possible fixes:"
  echo ""
  echo "1. If PostgreSQL is not running:"
  echo "   macOS:   brew services start postgresql@14"
  echo "   Ubuntu:  sudo systemctl start postgresql"
  echo "   Docker:  docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:14"
  echo ""
  echo "2. If using a custom database server:"
  echo "   Set these environment variables:"
  echo "     export PGHOST=your-db-host"
  echo "     export PGPORT=your-db-port"
  echo "     export PGUSER=your-db-user"
  echo "     export PGPASSWORD=your-db-password"
  echo ""
  echo "3. If using localhost with different credentials:"
  echo "   Edit config/dev.exs:"
  echo "     username: \"your_username\","
  echo "     password: \"your_password\","
  echo ""
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""

# Check rebar3 permissions (common Ubuntu issue)
echo "🔧 Checking rebar3 configuration..."

REBAR_CONFIG="$HOME/.config/rebar3/rebar.config"
if [ -f "$REBAR_CONFIG" ]; then
  if [ -r "$REBAR_CONFIG" ]; then
    echo -e "${GREEN}✓${NC} rebar3 config is readable"
  else
    echo -e "${RED}✗${NC} rebar3 config has permission issues"
    echo ""
    echo "To fix:"
    echo "  chmod 644 $REBAR_CONFIG"
    echo ""
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
else
  echo -e "${GREEN}✓${NC} No rebar3 config (will be created automatically)"
fi

echo ""

# Check Elixir/Erlang versions
echo "🧪 Checking Elixir/Erlang versions..."

if command -v elixir &> /dev/null; then
  ELIXIR_VERSION=$(elixir --version | grep "Elixir" | awk '{print $2}')
  echo -e "${GREEN}✓${NC} Elixir $ELIXIR_VERSION installed"
else
  echo -e "${RED}✗${NC} Elixir not found"
  echo ""
  echo "Install Elixir:"
  echo "  macOS:   brew install elixir"
  echo "  Ubuntu:  sudo apt-get install elixir"
  echo ""
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if command -v erl &> /dev/null; then
  echo -e "${GREEN}✓${NC} Erlang/OTP installed"
else
  echo -e "${RED}✗${NC} Erlang not found"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""

# Check Node.js (for assets)
echo "📦 Checking Node.js..."

if command -v node &> /dev/null; then
  NODE_VERSION=$(node --version)
  echo -e "${GREEN}✓${NC} Node.js $NODE_VERSION installed"
else
  echo -e "${YELLOW}⚠️  WARNING: Node.js not found (needed for assets)${NC}"
  echo ""
  echo "Install Node.js:"
  echo "  macOS:   brew install node"
  echo "  Ubuntu:  curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt-get install nodejs"
  echo ""
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""
echo "============================"

if [ $ISSUES_FOUND -eq 0 ]; then
  echo -e "${GREEN}✅ All checks passed! Ready to run 'mix setup'${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  Found $ISSUES_FOUND issue(s). Please fix them before running 'mix setup'.${NC}"
  echo ""
  echo "After fixing issues, run:"
  echo "  bash priv/scripts/check_setup.sh  # Verify again"
  echo "  mix setup                         # Run setup"
  exit 1
fi
