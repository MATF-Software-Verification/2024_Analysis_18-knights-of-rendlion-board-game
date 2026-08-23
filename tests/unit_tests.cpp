// unit_tests.cpp
//
// Self-authored unit tests for tinyxml2, written specifically to cover
// functionality left untested by the project's own bundled test suite
// (xmltest.cpp). Targets were identified by running lcov coverage against
// xmltest.cpp and inspecting the uncovered lines (see ../coverage_summary.txt
// and ../coverage.info for that baseline).
//
// Uses a minimal hand-rolled assertion style (matching the project's own
// existing test style) rather than an external framework, to keep the
// dependency footprint small. Any framework is permitted per the course
// guidelines; this project's own tests already use no framework, so we
// follow the same convention here for consistency.
//
// Build: see run_unit_tests.sh in this directory.

#include "tinyxml2.h"
#include <cstdio>
#include <cstring>

using namespace tinyxml2;

static int gPass = 0;
static int gFail = 0;

static void Check(const char* name, bool condition) {
    if (condition) {
        printf("[PASS] %s\n", name);
        ++gPass;
    } else {
        printf("[FAIL] %s\n", name);
        ++gFail;
    }
}

// --- XMLUtil::ToBool -------------------------------------------------------
// Existing xmltest.cpp only ever exercises the numeric path of ToBool
// (e.g. "0"/"1" via SetAttribute/QueryBoolAttribute in numeric form).
// The word-based branches ("true"/"True"/"TRUE"/"false"/"False"/"FALSE")
// and the invalid-input path were entirely uncovered.

static void TestToBoolWordForms() {
    bool v;

    Check("ToBool(\"true\") succeeds and is true",
          XMLUtil::ToBool("true", &v) && v == true);
    Check("ToBool(\"True\") succeeds and is true",
          XMLUtil::ToBool("True", &v) && v == true);
    Check("ToBool(\"TRUE\") succeeds and is true",
          XMLUtil::ToBool("TRUE", &v) && v == true);

    Check("ToBool(\"false\") succeeds and is false",
          XMLUtil::ToBool("false", &v) && v == false);
    Check("ToBool(\"False\") succeeds and is false",
          XMLUtil::ToBool("False", &v) && v == false);
    Check("ToBool(\"FALSE\") succeeds and is false",
          XMLUtil::ToBool("FALSE", &v) && v == false);

    Check("ToBool(\"nonsense\") fails",
          XMLUtil::ToBool("nonsense", &v) == false);
}

// --- XMLNode::ChildElementCount --------------------------------------------
// Neither overload (with or without a name filter) was exercised at all by
// the existing suite.

static void TestChildElementCount() {
    XMLDocument doc;
    doc.Parse("<root><a/><b/><a/></root>");
    XMLElement* root = doc.RootElement();

    Check("ChildElementCount() counts all children",
          root != nullptr && root->ChildElementCount() == 3);
    Check("ChildElementCount(\"a\") counts only matching children",
          root != nullptr && root->ChildElementCount("a") == 2);
    Check("ChildElementCount(\"z\") is 0 for a non-matching name",
          root != nullptr && root->ChildElementCount("z") == 0);
}

// --- Malformed numeric character references ---------------------------------
// The existing suite tests overflow/out-of-range numeric refs (e.g.
// &#10FFFF; / &#110000;) but not structurally malformed ones: an invalid
// digit, or a reference with no terminating semicolon anywhere in the
// remaining document. Both are realistic malformed-input cases given this
// function parses arbitrary/adversarial user-supplied XML.

static void TestMalformedNumericEntities() {
    {
        // Invalid decimal digit ('z' is not 0-9) -> parse of the entity
        // itself must fail safely and be left as literal text, without
        // corrupting the rest of the document or crashing.
        XMLDocument doc;
        doc.Parse("<root>&#zz;</root>");
        Check("Invalid decimal digit in numeric ref: no parse error",
              doc.Error() == false);
        Check("Invalid decimal digit in numeric ref: left as literal text",
              doc.RootElement() && doc.RootElement()->GetText()
              && strcmp(doc.RootElement()->GetText(), "&#zz;") == 0);
    }
    {
        // Invalid hex digit ('z' is not 0-9/a-f/A-F).
        XMLDocument doc;
        doc.Parse("<root>&#xzz;</root>");
        Check("Invalid hex digit in numeric ref: no parse error",
              doc.Error() == false);
        Check("Invalid hex digit in numeric ref: left as literal text",
              doc.RootElement() && doc.RootElement()->GetText()
              && strcmp(doc.RootElement()->GetText(), "&#xzz;") == 0);
    }
    {
        // No semicolon anywhere in the remaining document -> must fail
        // safely rather than scanning past the intended entity boundary.
        XMLDocument doc;
        doc.Parse("<root>&#65</root>");
        Check("Numeric ref with no terminating semicolon: no parse error",
              doc.Error() == false);
        Check("Numeric ref with no terminating semicolon: left as literal text",
              doc.RootElement() && doc.RootElement()->GetText()
              && strcmp(doc.RootElement()->GetText(), "&#65") == 0);
    }
}

int main() {
    TestToBoolWordForms();
    TestChildElementCount();
    TestMalformedNumericEntities();

    printf("\n%d passed, %d failed\n", gPass, gFail);
    return gFail == 0 ? 0 : 1;
}
