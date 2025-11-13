#!/bin/bash
# Test runner script for backend tests

set -e  # Exit on error

echo "🧪 Running Maccy Sync Backend Tests..."
echo "======================================="
echo ""

# Check if bun is installed
if ! command -v bun &> /dev/null; then
    echo "❌ Bun is not installed. Please install it first:"
    echo "   curl -fsSL https://bun.sh/install | bash"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    bun install
    echo ""
fi

# Run TypeScript type checking
echo "🔍 Running TypeScript type check..."
bunx tsc --noEmit
if [ $? -eq 0 ]; then
    echo "✅ Type check passed"
else
    echo "❌ Type check failed"
    exit 1
fi
echo ""

# Run tests
echo "🧪 Running unit tests..."
bun test
TEST_EXIT_CODE=$?

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ All backend tests passed!"
else
    echo ""
    echo "❌ Some backend tests failed"
    exit $TEST_EXIT_CODE
fi

# Generate coverage report if tests passed
echo ""
echo "📊 Generating coverage report..."
bun test --coverage 2>/dev/null || echo "Coverage report generation not available"

echo ""
echo "🎉 Backend testing complete!"
