#!/bin/bash

# X12Bridge - Development Script
# Usage: ./dev.sh [command]
# Commands:
#   start    - Start the Phoenix server (default)
#   test     - Run tests
#   iex      - Start interactive Elixir shell with app loaded
#   setup    - Full setup (deps + compile + migrate)
#   clean    - Clean build artifacts

set -e

COMMAND=${1:-start}

echo "🔧 X12Bridge Development Tool"
echo ""

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    echo "❌ Error: mix.exs not found. Please run this script from the X12Bridge project root."
    exit 1
fi

case $COMMAND in
    start)
        echo "🚀 Starting Phoenix server..."
        echo "📍 http://localhost:4000"
        echo ""
        mix phx.server
        ;;

    test)
        echo "🧪 Running tests..."
        echo ""
        mix test
        ;;

    iex)
        echo "💻 Starting interactive Elixir shell..."
        echo ""
        iex -S mix phx.server
        ;;

    setup)
        echo "📦 Installing dependencies..."
        mix deps.get
        echo ""

        echo "🔨 Compiling application..."
        mix compile
        echo ""

        echo "🎨 Compiling assets..."
        mix assets.deploy
        echo ""

        echo "✅ Setup complete!"
        echo "Run './dev.sh start' to start the server"
        ;;

    clean)
        echo "🧹 Cleaning build artifacts..."
        mix clean
        rm -rf _build deps priv/static/assets
        echo "✅ Clean complete!"
        echo "Run './dev.sh setup' to rebuild"
        ;;

    *)
        echo "❌ Unknown command: $COMMAND"
        echo ""
        echo "Available commands:"
        echo "  start    - Start the Phoenix server (default)"
        echo "  test     - Run tests"
        echo "  iex      - Start interactive Elixir shell with app loaded"
        echo "  setup    - Full setup (deps + compile + migrate)"
        echo "  clean    - Clean build artifacts"
        exit 1
        ;;
esac
