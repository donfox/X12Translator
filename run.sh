#!/bin/bash

# X12Translator - Run Script
# This script starts the Phoenix application

set -e  # Exit on error

echo "🚀 Starting X12Translator Application..."
echo ""

# Load environment variables if .env exists
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
    echo "🔑 Loaded environment from .env"
fi

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    echo "❌ Error: mix.exs not found. Please run this script from the X12Translator project root."
    exit 1
fi

# Check if Elixir is installed
if ! command -v elixir &> /dev/null; then
    echo "❌ Error: Elixir is not installed. Please install Elixir first."
    exit 1
fi

# Check if dependencies are installed
if [ ! -d "deps" ]; then
    echo "📦 Installing dependencies..."
    mix deps.get
    echo ""
fi

# Check if assets are compiled
if [ ! -d "priv/static/assets" ]; then
    echo "🎨 Compiling assets..."
    mix assets.deploy
    echo ""
fi

# Start the Phoenix server
echo "✅ Dependencies ready"
echo "🌐 Starting Phoenix server at http://localhost:4000"
echo ""
echo "Press Ctrl+C to stop the server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

mix phx.server
