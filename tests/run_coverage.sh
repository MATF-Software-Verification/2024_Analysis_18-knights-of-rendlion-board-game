#!/bin/bash
# Builds tinyxml2 with gcov instrumentation, runs BOTH the project's existing
# test suite (xmltest.cpp) AND our own self-authored unit tests
# (unit_tests.cpp), and generates a combined lcov coverage report.
#
# Prerequisites: g++, lcov
#   Debian/Ubuntu: sudo apt install -y build-essential lcov
#   macOS:         brew install lcov  (g++/clang already present via Xcode CLT)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TINYXML2_DIR="$REPO_ROOT/tinyxml2"
BUILD_DIR="$TINYXML2_DIR/build_coverage"

echo "=== 1. Compiling with coverage instrumentation ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
g++ -std=c++11 --coverage -O0 -I.. -c ../xmltest.cpp -o xmltest.o
g++ -std=c++11 --coverage -O0 -I.. -c ../tinyxml2.cpp -o tinyxml2.o
g++ -std=c++11 --coverage -O0 -I.. -c "$SCRIPT_DIR/unit_tests.cpp" -o unit_tests.o
g++ --coverage xmltest.o tinyxml2.o -o xmltest_combined
g++ --coverage unit_tests.o tinyxml2.o -o unit_tests_combined

echo "=== 2. Running existing xmltest.cpp suite (from tinyxml2/ so it finds test data files) ==="
( cd "$TINYXML2_DIR" && ./build_coverage/xmltest_combined )

echo "=== 3. Running our self-authored unit tests ==="
( cd "$TINYXML2_DIR" && ./build_coverage/unit_tests_combined )

echo "=== 4. Capturing combined coverage data ==="
lcov --capture --directory "$BUILD_DIR" \
  --output-file "$BUILD_DIR/coverage.info" \
  --ignore-errors mismatch,negative,inconsistent,unsupported

echo "=== 5. Filtering to library source only (excluding the test files themselves) ==="
lcov --extract "$BUILD_DIR/coverage.info" "*/tinyxml2.cpp" \
  --output-file "$SCRIPT_DIR/coverage.info"

echo "=== 6. Writing text summary ==="
lcov --summary "$SCRIPT_DIR/coverage.info" > "$SCRIPT_DIR/coverage_summary.txt" 2>&1
cat "$SCRIPT_DIR/coverage_summary.txt"

echo "=== 7. Generating HTML report (gitignored, local viewing only) ==="
genhtml "$SCRIPT_DIR/coverage.info" --output-directory "$SCRIPT_DIR/html" > /dev/null

echo ""
echo "Done. Summary saved to tests/coverage_summary.txt"
echo "Full HTML report available locally at tests/html/index.html (regenerate via this script)"