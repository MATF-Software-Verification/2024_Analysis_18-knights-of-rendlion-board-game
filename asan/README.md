# Tool 2: AddressSanitizer

Compiler-based instrumentation (`-fsanitize=address`) that detects memory
errors at runtime: buffer overflows (stack/heap/global), use-after-free,
double-free, and memory leaks. Not covered in course labs — chosen as one
of this project's novel tools.

## Why this matters for tinyxml2

The library does manual, pointer-heavy memory management (a custom
`MemPool` allocator, hand-rolled string/entity parsing) over arbitrary,
potentially adversarial user-supplied XML text — exactly the class of code
where memory-safety bugs are most likely to hide.

## Reproduce

```bash
./run_asan.sh
```

Requires only `g++` (or `clang++`) — ASan is built into modern GCC and
Clang, no extra install needed. Runs natively on both Linux and macOS
(including Apple Silicon).

## Results

- Existing `xmltest.cpp` suite (528 cases): **528 passed, 0 failed, 0 ASan errors**
- Our self-authored `unit_tests.cpp` (16 cases): **16 passed, 0 failed, 0 ASan errors**

Full run logs: [`results_xmltest.log`](./results_xmltest.log),
[`results_unit_tests.log`](./results_unit_tests.log).

**Conclusion:** no memory-safety issues detected across all 544 test cases,
including the malformed/adversarial-input cases already present in the
existing suite and the additional malformed-entity cases we added ourselves.

## Notes

- Built with `-g -O1 -fsanitize=address -fno-omit-frame-pointer`, the
  standard recommended ASan build configuration (low optimization keeps
  stack traces meaningful if something is found).
- LeakSanitizer runs automatically as part of ASan on Linux; on macOS,
  LeakSanitizer support is more limited by the OS, so a clean ASan run on
  macOS should be read primarily as "no memory-corruption errors detected,"
  with leak coverage being strongest on the Linux run.
- See [`../ubsan/`](../ubsan) for UndefinedBehaviorSanitizer results,
  tracked as a separate tool since it detects a different class of bugs.
