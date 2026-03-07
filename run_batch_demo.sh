#!/bin/bash

# X12Translator Batch Processing Demo Runner
# This script demonstrates the batch processing system

echo "========================================="
echo "X12Translator Batch Processing Demo"
echo "========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    echo "Error: Not in X12Translator directory"
    echo "Please run from: /Users/donfox1/Work/X12Translator"
    exit 1
fi

echo "Running batch processing demo..."
echo ""

# Run the Elixir demo script
elixir demo_batch_processing.exs

echo ""
echo "========================================="
echo "Demo complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Check output: ls -la priv/batch_processing/output/"
echo "  2. Run tests: mix test test/x12_translator/batch_processor_test.exs"
echo "  3. Start IEx: iex -S mix"
echo ""
