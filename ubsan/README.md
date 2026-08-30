# Tool 3: UndefinedBehaviorSanitizer

Compiler-based instrumentation (`-fsanitize=undefined`) that detects
undefined-behavior issues at runtime: signed integer overflow, misaligned
pointer access, invalid enum values, null-pointer arithmetic, and similar.
Not covered in course labs — chosen as one of this project's novel tools.

Tracked as a separate tool from AddressSanitizer ([`../asan/`](../asan))
since the two are independent instrumentations catching different bug
classes, built and run independently here (not combined into a single
`-fsanitize=address,undefined` build).

## Why this matters for tinyxml2

The library does its own manual numeric parsing (integer/float attribute
values, hex/decimal character references) and pointer arithmetic while
scanning through raw text — code that is easy to get subtly wrong in ways
that are technically undefined behavior even when it "happens to work" on a
given compiler/platform.

## Reproduce

```bash
./run_ubsan.sh
```

Requires only `g++` (or `clang++`) — UBSan is built into modern GCC and
Clang, no extra install needed. Runs natively on both Linux and macOS.

## Results

- Existing `xmltest.cpp` suite (528 cases): **528 passed, 0 failed, 0 UBSan runtime errors**
- Our self-authored `unit_tests.cpp` (16 cases): **16 passed, 0 failed, 0 UBSan runtime errors**

Full run logs: [`results_xmltest.log`](./results_xmltest.log),
[`results_unit_tests.log`](./results_unit_tests.log).

**Conclusion:** no undefined-behavior issues detected across all 544 test
cases.

## Notes

- Built with `-g -O1 -fsanitize=undefined -fno-omit-frame-pointer`.
- A clean UBSan run doesn't prove the absence of UB in general — it only
  proves no instrumented UB was *triggered* by the specific inputs
  exercised in these two test suites. Fuzz testing (see the `libfuzzer/`
  tool once added) extends this by exploring inputs beyond the fixed test
  corpus.
