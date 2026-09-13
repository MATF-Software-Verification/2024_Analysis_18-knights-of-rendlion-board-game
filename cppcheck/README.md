# Tool 6: Cppcheck

Static analysis, independent from clang-tidy (tool 5) — a different
analysis engine with different heuristics, not covered in course labs.
One of this project's novel tools.

## Why a second static analyzer, given clang-tidy already ran?

Cppcheck uses a different internal analysis approach than clang-tidy (its
own dataflow/value-flow analysis rather than Clang's AST + Clang Static
Analyzer symbolic execution), so it can surface genuinely different
findings from the same source, not just duplicate clang-tidy's output.

## Reproduce

```bash
./run_cppcheck.sh
```

Requires only `cppcheck` itself (`brew install cppcheck` on macOS,
`sudo apt install cppcheck` on Linux) — no build system integration
needed, since cppcheck parses source directly rather than requiring
`compile_commands.json` the way clang-tidy does.

## Results differ by Cppcheck version — both are legitimate

| Platform | Cppcheck version | Total findings |
|---|---|---|
| Linux | 2.13.0 | 13 |
| macOS (Apple Silicon) | 2.21.0 | 28 |

Same pattern as clang-tidy's version difference (tool 5): the newer
Cppcheck release added checks that didn't exist yet in the older version —
`missingOverride` (11 instances) and `functionStatic` (2) are entirely new
categories on macOS. The original 4 categories (`invalidPrintfArgType_sint`,
`uninitMemberVar`, `noExplicitConstructor`, `nullPointerRedundantCheck`)
appear on both platforms with identical counts.

### macOS/2.21.0 breakdown (28 findings)

| Finding type | Count | Verdict |
|---|---|---|
| `missingOverride` | 11 | Real, minor (version-specific) |
| `invalidPrintfArgType_sint` | 5 | Real, low-impact |
| `uninitMemberVar` | 3 | Likely false positive |
| `noExplicitConstructor` | 3 | Real, minor |
| `nullPointerRedundantCheck` | 2 | Likely false positive |
| `functionStatic` | 2 | Real, minor (version-specific) |
| `syntaxError` | 1 | **Tool artifact — see below** |
| `knownConditionTrueFalse` | 1 | Real, minor |

(Linux/2.13.0's 13-finding breakdown is unchanged from the original run —
the same 4 categories, minus the version-specific ones below.)

### `missingOverride` (11 instances, macOS only) — real, minor

Several destructors (`~XMLText`, `~XMLComment`, `~XMLDeclaration`,
`~XMLUnknown`, `~XMLElement`, `~XMLDocument`, `~XMLPrinter`, and template
instantiations of `~MemPoolT`) override a virtual base-class destructor but
aren't marked with C++11's `override` specifier. Harmless as-is (the
`virtual` keyword alone is sufficient for correct dispatch), but adding
`override` would let the compiler catch a signature mismatch automatically
if the base class destructor's signature ever changed. Straightforward,
low-risk fix if desired — a modernization suggestion, not a bug.

### `functionStatic` (2 instances, macOS only) — real, minor

`XMLNode::InsertChildPreamble` and `XMLDocument::DeleteNode` don't use
`this` and could be declared `static`. **Notable: this is conceptually the
same finding as clang-tidy's `readability-convert-member-functions-to-static`
category** — a genuine point of agreement between the two independent
static analyzers, worth mentioning alongside the "zero category overlap"
observation elsewhere in this report as a nuance: the tools don't overlap
in naming or exact category, but did independently converge on the same
two specific functions being flagged for the same underlying reason.

### `syntaxError` (1 instance) — tool artifact, not a real defect

```
Checking tinyxml2.cpp: ANDROID_NDK=ANDROID_NDK;TIXMLASSERT...
tinyxml2.h:150:9: error: syntax error [syntaxError]
        TIXMLASSERT( start );
```

`TIXMLASSERT` is a macro **conditionally defined by the header itself**
(`tinyxml2.h`), branching on whether `TINYXML2_DEBUG`, `_MSC_VER`, or
`ANDROID_NDK` are set (see `tinyxml2.h` around line 68-80). Cppcheck
automatically explores many plausible preprocessor macro combinations to
catch config-specific bugs (§ see study guide for the general mechanism) —
but in this specific combination, it invented a synthetic configuration
that also predefines a bare, empty `TIXMLASSERT` macro *as if* it were an
external command-line define, which is not something any real build of
this project does. Under that synthetic state, the header's own
`#if !defined(TIXMLASSERT)` guard evaluates false, none of the header's
real macro definitions apply, and the later
call-style usage `TIXMLASSERT( start );` breaks against the now-empty,
externally-"predefined" macro. This never occurs in any actual build
configuration of tinyxml2 — it's an artifact of Cppcheck's automatic
configuration-guessing treating an internally-defined macro as if it were
an external one. Documented here rather than silently omitted, since
being able to explain *why* a finding is a tool artifact (not just assert
that it is one) is the more defensible position at defense.

### `uninitMemberVar` (3 instances) — likely false positive

Flags `DynArray`'s `_pool` member (for three different template
instantiations) as uninitialized in the constructor. In context, `_pool`
is a fixed-size inline array member (not a pointer), and the constructor
deliberately leaves its contents uninitialized for performance — only the
*used* portion (tracked separately via a size/count member) is ever read,
and that portion is always written before being read. A structural check
can't distinguish this legitimate performance pattern from an actual bug.

### `noExplicitConstructor` (3 instances) — real, minor

Three single-argument constructors (`XMLElement`, `XMLDocument`,
`XMLPrinter`) aren't marked `explicit`, meaning the compiler would
silently allow implicit conversions. Minor defensive-coding improvement;
no evidence of an actual implicit-conversion bug currently in the
codebase.

### `nullPointerRedundantCheck` (2 instances) — likely false positive, explained

Both point at `XMLElement::ParseAttributes`: cppcheck's flow analysis
noticed that `p` is null-checked later in the function (`if (!p || ...)`,
after being *reassigned* by `attrib->ParseDeep(...)`) and applied that
null-check expectation backward onto an *earlier*, logically distinct use
of `p` — the original value from `XMLUtil::SkipWhiteSpace`, before
reassignment, guarded by the enclosing `while(p)` loop condition. This
looks like an imprecision in cppcheck's value-flow tracking (conflating
two different value-flow states of the same variable name across a
reassignment) rather than a genuine null-dereference risk.

### `knownConditionTrueFalse` (1 instance) — real, minor

```cpp
if (FirstChild()) {
    wellLocated =
        FirstChild() &&              // <- redundant: already known true
        FirstChild()->ToDeclaration() &&
        LastChild() &&
        LastChild()->ToDeclaration();
}
```
`FirstChild()` is checked at the enclosing `if`, then redundantly
re-evaluated as part of the compound condition immediately inside that
same block. Harmless (no behavior difference — `FirstChild()` returns the
same pointer both times, short-circuit evaluation still works correctly),
but genuinely redundant code that could be simplified. Correctly
identified, not a false positive.

## Cross-tool comparison with clang-tidy (tool 5)

Mostly non-overlapping finding *categories* between the two static
analyzers — cppcheck's dataflow-based checks caught different things than
clang-tidy's AST-pattern + symbolic-execution checks did overall. The one
exception is `functionStatic`/`readability-convert-member-functions-to-static`,
where both tools independently flagged the same two functions — worth
citing as a genuine point of cross-tool agreement, alongside the broader
"different tools, different blind spots" observation from the largely
non-overlapping remainder.