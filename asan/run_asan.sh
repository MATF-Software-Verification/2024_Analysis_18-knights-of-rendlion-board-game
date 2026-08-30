#!/bin/bash
# Builds tinyxml2, the existing xmltest.cpp suite, and our self-authored
# unit_tests.cpp with AddressSanitizer instrumentation, runs both, and
# reports whether any memory-safety errors (buffer overflows, use-after-free,
# double-free, leaks, etc.) were detected.
#
# Prerequisites: g++ (or clang++) with AddressSanitizer support (standard on
# both Linux/GCC and macOS/Clang, no extra install needed).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TINYXML2_DIR="$REPO_ROOT/tinyxml2"
BUILD_DIR="$TINYXML2_DIR/build_asan"

echo "=== 1. Compiling with AddressSanitizer instrumentation ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
g++ -std=c++11 -g -O1 -fsanitize=address -fno-omit-frame-pointer -I.. -c ../xmltest.cpp -o xmltest.o
g++ -std=c++11 -g -O1 -fsanitize=address -fno-omit-frame-pointer -I.. -c ../tinyxml2.cpp -o tinyxml2.o
g++ -std=c++11 -g -O1 -fsanitize=address -fno-omit-frame-pointer -I.. -c "$SCRIPT_DIR/../tests/unit_tests.cpp" -o unit_tests.o
g++ -fsanitize=address xmltest.o tinyxml2.o -o xmltest_asan
g++ -fsanitize=address unit_tests.o tinyxml2.o -o unit_tests_asan

echo "=== 2. Running existing xmltest.cpp suite under ASan ==="
( cd "$TINYXML2_DIR" && ./build_asan/xmltest_asan ) | tee "$SCRIPT_DIR/results_xmltest.log"

echo "=== 3. Running our self-authored unit tests under ASan ==="
( cd "$TINYXML2_DIR" && ./build_asan/unit_tests_asan ) | tee "$SCRIPT_DIR/results_unit_tests.log"

echo "=== 4. Checking for ASan error reports ==="
if grep -qE "==[0-9]+==ERROR|SUMMARY: AddressSanitizer|SUMMARY: LeakSanitizer" \
    "$SCRIPT_DIR/results_xmltest.log" "$SCRIPT_DIR/results_unit_tests.log"; then
  echo "AddressSanitizer reported issues -- see results_*.log above."
  exit 1
else
  echo "No AddressSanitizer errors detected in either test run."
fi
