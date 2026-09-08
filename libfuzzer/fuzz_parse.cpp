// fuzz_parse.cpp
//
// libFuzzer harness for tinyxml2. Feeds arbitrary byte sequences directly
// into XMLDocument::Parse(), which is the library's main entry point for
// untrusted/adversarial input (parsing arbitrary user-supplied XML text).
//
// Build: see run_libfuzzer.sh in this directory.

#include "tinyxml2.h"
#include <cstdint>
#include <cstddef>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    // XMLDocument::Parse expects a null-terminated (or explicitly sized)
    // buffer; libFuzzer gives us a raw, non-null-terminated byte range, so
    // we copy it into a buffer we control and size it explicitly rather
    // than relying on a trailing NUL that may not exist in the fuzzer's
    // input buffer.
    tinyxml2::XMLDocument doc;
    doc.Parse(reinterpret_cast<const char*>(data), size);

    // We don't assert anything about the result here -- a successful parse,
    // a graceful XMLError, and a caught exception are all "fine". What
    // libFuzzer/ASan actually catch are crashes, hangs, and memory-safety
    // violations, not the parse's logical outcome.
    return 0;
}
