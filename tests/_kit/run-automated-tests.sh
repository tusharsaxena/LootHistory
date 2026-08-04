#!/usr/bin/env bash
#
# run-automated-tests.sh — the Ka0s collection's consolidated automated-test runner.
#
# Runs the four out-of-game suites and records every result as one frozen bundle under
# docs/automated-tests/<YYYYMMDD-HHMMSS>/, then rolls the run into docs/automated-tests/RESULTS.md.
#
#   lint        luacheck .                     GATING
#   tests       lua tests/run.lua              GATING
#   perf        lua tests/perf.lua             recorded, never gating
#   complexity  lizard -l lua -x ... .         recorded, never gating
#
# WHY perf AND complexity DO NOT GATE. `performance-§10` is explicit that a complexity threshold
# which fails a run teaches everyone to reach for --no-verify, after which the gate protects nothing
# and the habit remains; `performance-§9` says the same of wall-clock perf. Folding either into a
# red/green battery would quietly reverse both rules. They are measured, recorded and diffed — never
# used to fail the run. A regression in them yields `amber`, which is a signal, not a stop.
#
# A MISSING TOOL IS A SKIP, NOT A FAILURE. An absent luacheck/lizard/interpreter means the suite did
# not run; it does not mean the addon is broken. Skips are recorded as skips so a green run that
# actually measured nothing cannot read as a green run that measured everything.
#
# Usage, from the addon repo root:
#
#   tests/_kit/run-automated-tests.sh                          all four suites, writes a bundle
#   tests/_kit/run-automated-tests.sh --suite lint --suite tests   a subset
#   tests/_kit/run-automated-tests.sh --label pre-release       label the bundle
#   tests/_kit/run-automated-tests.sh --no-bundle               print only, write nothing
#   tests/_kit/run-automated-tests.sh --release 1.4.2           mark the bundle a release record
#
# Exit code: 0 unless the verdict is `red` (a gating suite failed). --no-bundle keeps the same code,
# so a pre-commit hook can call it without writing anything.
#
# VENDORED — do not edit this copy. It lives in the LibKa0s repo at testkit/ and is vendored
# whole-folder to <Addon>/tests/_kit/. A local patch is overwritten by the next re-vendor, silently.

set -uo pipefail

# ── argument parsing ────────────────────────────────────────────────────────────────────────────
SUITES=()
LABEL=""
RELEASE=""
WRITE_BUNDLE=1

while [ $# -gt 0 ]; do
    case "$1" in
        --suite)      SUITES+=("$2"); shift 2 ;;
        --label)      LABEL="$2"; shift 2 ;;
        --release)    RELEASE="$2"; shift 2 ;;
        --no-bundle)  WRITE_BUNDLE=0; shift ;;
        -h|--help)    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
if [ ${#SUITES[@]} -eq 0 ]; then SUITES=(lint tests perf complexity); fi

wants() { for s in "${SUITES[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

# ── locate the addon ────────────────────────────────────────────────────────────────────────────
TOC="$(ls -1 ./*.toc 2>/dev/null | head -1 || true)"
if [ -z "$TOC" ]; then
    echo "no .toc at the repo root — run this from the addon root" >&2
    exit 2
fi
ADDON="$(basename "$TOC" .toc)"
ADDON_VERSION="$(grep -i '^## Version:' "$TOC" 2>/dev/null | head -1 | sed 's/^## *[Vv]ersion: *//' | tr -d '\r' || true)"
[ -z "$ADDON_VERSION" ] && ADDON_VERSION="unknown"

# LOCAL time, not UTC: a record is read by the person who ran it, and a folder name that
# disagrees with their clock costs a mental conversion on every glance. startedAt keeps an
# explicit UTC offset so the instant stays unambiguous once the record outlives the machine.
STAMP="$(date +%Y%m%d-%H%M%S)"
STARTED_AT="$(date +%Y-%m-%dT%H:%M:%S%:z)"
OUT="docs/automated-tests/$STAMP"
RUN_START=$(date +%s)

# ── interpreter + tool discovery ────────────────────────────────────────────────────────────────
LUA=""
for c in lua5.1 lua luajit; do command -v "$c" >/dev/null 2>&1 && { LUA="$c"; break; }; done
LUA_VERSION=""
[ -n "$LUA" ] && LUA_VERSION="$($LUA -v 2>&1 | head -1 | tr -d '\r')"
LUACHECK_VERSION=""
command -v luacheck >/dev/null 2>&1 && LUACHECK_VERSION="$(luacheck --version 2>/dev/null | head -1 | tr -d '\r')"
NOCOLOR=""
[ -n "$LUACHECK_VERSION" ] && luacheck --help 2>&1 | grep -q -- "--no-color" && NOCOLOR="--no-color"
LIZARD_VERSION=""
command -v lizard >/dev/null 2>&1 && LIZARD_VERSION="$(lizard --version 2>/dev/null | head -1 | tr -d '\r')"

GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo "")"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
GIT_DIRTY=false
[ -n "$(git status --porcelain 2>/dev/null)" ] && GIT_DIRTY=true

[ "$WRITE_BUNDLE" -eq 1 ] && mkdir -p "$OUT"

# Per-suite state. status is pass|fail|skip; skip_reason explains a skip in the summary.
declare -A ST DUR NOTE
for s in lint tests perf complexity; do ST[$s]="notrun"; DUR[$s]=0; NOTE[$s]=""; done

LINT_WARN=0; LINT_ERR=0; LINT_FILES=0
TESTS_PASS=0; TESTS_FAIL=0; TESTS_TOTAL=0
PERF_SCENARIOS=0; PERF_FAILED=0
CCN_WARN=0; CCN_NLOC=0; CCN_FUNCS=0; CCN_AVG=0; CCN_MAX=0; CCN_BAND=0; CCN_OVER=0
CCN_AVG_NLOC=0; CCN_AVG_TOKEN=0; CCN_FUN_RT=0; CCN_NLOC_RT=0

# Strip ANSI colour before writing. luacheck and the harness colour their output when they
# think a terminal is attached, and the raw escapes ('\033[32m\033[1mOK') land verbatim in the
# artifact — unreadable in an editor and noise in any diff between two runs. The parsers below
# already strip for their own use; the stored evidence gets the same treatment.
strip_ansi() { sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\r$//'; }
emit() { if [ "$WRITE_BUNDLE" -eq 1 ]; then strip_ansi > "$OUT/$1"; else cat > /dev/null; fi; }

# ── lint ────────────────────────────────────────────────────────────────────────────────────────
if wants lint; then
    t0=$(date +%s)
    if [ ! -f .luacheckrc ]; then
        ST[lint]="skip"; NOTE[lint]="no .luacheckrc — lint is not part of this addon's battery"
    elif [ -z "$LUACHECK_VERSION" ]; then
        ST[lint]="skip"; NOTE[lint]="luacheck not on PATH — install: pipx install luacheck"
    else
        # $NOCOLOR is belt and braces with strip_ansi: where the flag exists nothing colours the
        # output in the first place, and where it does not, strip_ansi still cleans it.
        raw="$(luacheck . $NOCOLOR 2>&1)"; rc=$?
        printf '%s\n' "$raw" | emit lint.txt
        line="$(printf '%s\n' "$raw" | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^Total: ' | tail -1)"
        LINT_WARN=$(printf '%s' "$line" | grep -oE '[0-9]+ warning' | grep -oE '[0-9]+' || echo 0)
        LINT_ERR=$(printf '%s'  "$line" | grep -oE '[0-9]+ error'   | grep -oE '[0-9]+' || echo 0)
        LINT_FILES=$(printf '%s' "$line" | grep -oE 'in [0-9]+ files' | grep -oE '[0-9]+' || echo 0)
        [ -z "$LINT_WARN" ] && LINT_WARN=0; [ -z "$LINT_ERR" ] && LINT_ERR=0; [ -z "$LINT_FILES" ] && LINT_FILES=0
        if [ "$rc" -eq 0 ]; then ST[lint]="pass"; else ST[lint]="fail"; fi
    fi
    DUR[lint]=$(( $(date +%s) - t0 ))
fi

# ── tests ───────────────────────────────────────────────────────────────────────────────────────
if wants tests; then
    t0=$(date +%s)
    if [ ! -f tests/run.lua ]; then
        ST[tests]="skip"; NOTE[tests]="no tests/run.lua"
    elif [ -z "$LUA" ]; then
        ST[tests]="skip"; NOTE[tests]="no Lua 5.1 interpreter on PATH — the kit uses setfenv, which is 5.1-only"
    else
        raw="$($LUA tests/run.lua 2>&1)"; rc=$?
        printf '%s\n' "$raw" | emit tests.txt
        # Both summary shapes in the collection: "N passed, N failed, N total" and the older
        # "N passed, N failed". Matching only the first silently recorded 0/0/0 for every addon
        # using the second — a green run reporting zero tests, which is the exact failure this
        # runner exists to make impossible.
        clean="$(printf '%s\n' "$raw" | sed 's/\x1b\[[0-9;]*m//g')"
        line="$(printf '%s\n' "$clean" | grep -oE '[0-9]+ passed, [0-9]+ failed(, [0-9]+ total)?' | tail -1)"
        if [ -n "$line" ]; then
            TESTS_PASS=$(printf '%s' "$line" | awk '{print $1}')
            TESTS_FAIL=$(printf '%s' "$line" | awk '{print $3}')
            TESTS_TOTAL=$(printf '%s' "$line" | awk '{print $5}')
            [ -z "$TESTS_TOTAL" ] && TESTS_TOTAL=$(( TESTS_PASS + TESTS_FAIL ))
        fi
        if [ "$rc" -eq 0 ]; then ST[tests]="pass"; else ST[tests]="fail"; fi
        # A zero-exit run whose count could not be read is NOT a pass. Reporting green off an
        # unparsed summary is worse than reporting a failure, because it is believed.
        if [ "${ST[tests]}" = "pass" ] && [ "$TESTS_TOTAL" -eq 0 ]; then
            ST[tests]="skip"
            NOTE[tests]="the harness exited 0 but its summary could not be parsed — count not recorded"
        fi
        # The generated inventory travels with the run it describes, so a bundle answers
        # "which cases existed at this point" without a second checkout.
        if [ "$WRITE_BUNDLE" -eq 1 ]; then
            $LUA tests/run.lua --list 2>/dev/null | strip_ansi > "$OUT/test-cases.md" \
                || rm -f "$OUT/test-cases.md"
        fi
    fi
    DUR[tests]=$(( $(date +%s) - t0 ))
fi

# ── perf (recorded, never gating) ───────────────────────────────────────────────────────────────
if wants perf; then
    t0=$(date +%s)
    if [ ! -f tests/perf.lua ]; then
        ST[perf]="skip"; NOTE[perf]="no tests/perf.lua — this addon ships no offline scenarios"
    elif [ -z "$LUA" ]; then
        ST[perf]="skip"; NOTE[perf]="no Lua interpreter on PATH"
    else
        if [ "$WRITE_BUNDLE" -eq 1 ]; then
            raw="$($LUA tests/perf.lua --out "$OUT/perf.json" ${LABEL:+--label "$LABEL"} 2>&1)"; rc=$?
        else
            raw="$($LUA tests/perf.lua ${LABEL:+--label "$LABEL"} 2>&1)"; rc=$?
        fi
        printf '%s\n' "$raw" | emit perf.txt
        # The scenario table opens with a `scenario  iters  ms/iter ...` header and runs until the
        # first blank line. Counting the header itself (or any `##`) is how this silently reported
        # "1 scenario" for a six-row table, so the rows are counted structurally: five fields, with
        # the iteration count numeric.
        PERF_SCENARIOS=$(printf '%s\n' "$raw" | awk '
            /^[[:space:]]*scenario[[:space:]]+iters/ { intable=1; next }
            intable && NF==0 { intable=0 }
            intable && NF==5 && $2 ~ /^[0-9]+$/ { n++ }
            END { print n+0 }')
        [ -z "$PERF_SCENARIOS" ] && PERF_SCENARIOS=0
        if [ "$rc" -eq 0 ]; then ST[perf]="pass"; else ST[perf]="fail"; PERF_FAILED=1; fi
    fi
    DUR[perf]=$(( $(date +%s) - t0 ))
fi

# ── complexity (recorded, never gating) ─────────────────────────────────────────────────────────
if wants complexity; then
    t0=$(date +%s)
    if [ -z "$LIZARD_VERSION" ]; then
        ST[complexity]="skip"; NOTE[complexity]="lizard not on PATH — install: pipx install lizard"
    else
        # The standard fixes this invocation (performance-§10). Do not add flags, re-tune
        # thresholds or narrow the path: a locally "improved" command produces a report that
        # cannot be diffed against any other, which is the one property the fixed command protects.
        raw="$(lizard -l lua -x "./libs/*" -x "./tests/_kit/*" . 2>&1)"
        printf '%s\n' "$raw" | emit complexity.txt
        # lizard's footer, whole:
        #   Total nloc  Avg.NLOC  AvgCCN  Avg.token  Fun Cnt  Warning cnt  Fun Rt  nloc Rt
        # All eight are recorded. The averages and the two ratios are what make one run comparable
        # to another across a change in size -- a total that rose because the addon grew is a
        # different fact from an average that rose because it got denser, and only the second is a
        # complexity signal. Dropping them meant the analysis could only ever report totals.
        footer="$(printf '%s\n' "$raw" | tail -1)"
        fld() { printf '%s' "$footer" | awk -v n="$1" '{print $n}'; }
        CCN_NLOC=$(fld 1);      [ -z "$CCN_NLOC" ]      && CCN_NLOC=0
        CCN_AVG_NLOC=$(fld 2);  [ -z "$CCN_AVG_NLOC" ]  && CCN_AVG_NLOC=0
        CCN_AVG=$(fld 3);       [ -z "$CCN_AVG" ]       && CCN_AVG=0
        CCN_AVG_TOKEN=$(fld 4); [ -z "$CCN_AVG_TOKEN" ] && CCN_AVG_TOKEN=0
        CCN_FUNCS=$(fld 5);     [ -z "$CCN_FUNCS" ]     && CCN_FUNCS=0
        CCN_WARN=$(fld 6);      [ -z "$CCN_WARN" ]      && CCN_WARN=0
        CCN_FUN_RT=$(fld 7);    [ -z "$CCN_FUN_RT" ]    && CCN_FUN_RT=0
        CCN_NLOC_RT=$(fld 8);   [ -z "$CCN_NLOC_RT" ]   && CCN_NLOC_RT=0
        CCN_MAX=$(printf '%s\n' "$raw" | awk '/!!!! Warnings/{f=1} f && /@/ {if ($2+0>m) m=$2+0} END{print m+0}')
        # layout-§1: 1000–1500 is the on-notice band, >1500 is a bug. Counted here so the
        # manifest answers the layout question without a second pass over the tree.
        while IFS= read -r n; do
            [ "$n" -ge 1000 ] 2>/dev/null && { [ "$n" -gt 1500 ] && CCN_OVER=$((CCN_OVER+1)) || CCN_BAND=$((CCN_BAND+1)); }
        done < <(find . -name '*.lua' -not -path './libs/*' -not -path './tests/_kit/*' -exec wc -l {} + 2>/dev/null | awk '$2!="total"{print $1}')
        ST[complexity]="pass"
    fi
    DUR[complexity]=$(( $(date +%s) - t0 ))
fi

# ── verdict ─────────────────────────────────────────────────────────────────────────────────────
# red   — a GATING suite failed (lint, tests)
# amber — a gating suite was skipped, or a recorded suite failed its own deterministic assertions
# green — gating suites passed and nothing was silently not-measured
VERDICT="green"
for s in lint tests; do
    [ "${ST[$s]}" = "fail" ] && VERDICT="red"
done
if [ "$VERDICT" != "red" ]; then
    for s in lint tests; do [ "${ST[$s]}" = "skip" ] && VERDICT="amber"; done
    [ "${ST[perf]}" = "fail" ] && VERDICT="amber"
fi

RUN_DURATION=$(( $(date +%s) - RUN_START ))

# ── console summary ─────────────────────────────────────────────────────────────────────────────
fmt() {
    case "$1" in
        lint)       printf '%s warnings / %s errors in %s files' "$LINT_WARN" "$LINT_ERR" "$LINT_FILES" ;;
        tests)      printf '%s passed, %s failed, %s total' "$TESTS_PASS" "$TESTS_FAIL" "$TESTS_TOTAL" ;;
        perf)       printf '%s scenarios' "$PERF_SCENARIOS" ;;
        complexity) printf '%s warnings (fun rate %s), %s NLOC / %s funcs, avg NLOC %s, avg CCN %s (max %s), avg tokens %s' \
                        "$CCN_WARN" "$CCN_FUN_RT" "$CCN_NLOC" "$CCN_FUNCS" "$CCN_AVG_NLOC" "$CCN_AVG" "$CCN_MAX" "$CCN_AVG_TOKEN" ;;
    esac
}
echo "$ADDON $ADDON_VERSION — automated tests — $STAMP"
for s in lint tests perf complexity; do
    [ "${ST[$s]}" = "notrun" ] && continue
    gate=""; { [ "$s" = "perf" ] || [ "$s" = "complexity" ]; } && gate=" (recorded, non-gating)"
    if [ "${ST[$s]}" = "skip" ]; then
        printf '  %-11s skip  — %s\n' "$s" "${NOTE[$s]}"
    else
        printf '  %-11s %-5s — %s%s\n' "$s" "${ST[$s]}" "$(fmt "$s")" "$gate"
    fi
done
echo "  verdict: $VERDICT"

# ── bundle ──────────────────────────────────────────────────────────────────────────────────────
if [ "$WRITE_BUNDLE" -eq 1 ]; then
    sj() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    suite_json() {
        local s="$1" extra="$2"
        printf '    "%s": { "status": "%s", "durationMs": %s%s%s }' \
            "$s" "${ST[$s]}" "$(( ${DUR[$s]} * 1000 ))" \
            "$( [ -n "${NOTE[$s]}" ] && printf ', "skipReason": "%s"' "$(sj "${NOTE[$s]}")" )" \
            "$extra"
    }
    {
        printf '{\n'
        printf '  "schema": 1,\n'
        printf '  "addon": "%s",\n'          "$(sj "$ADDON")"
        printf '  "addonVersion": "%s",\n'   "$(sj "$ADDON_VERSION")"
        printf '  "run": "%s",\n'            "$STAMP"
        printf '  "startedAt": "%s",\n'      "$STARTED_AT"
        printf '  "durationMs": %s,\n'       "$(( RUN_DURATION * 1000 ))"
        printf '  "label": %s,\n'            "$( [ -n "$LABEL" ] && printf '"%s"' "$(sj "$LABEL")" || printf 'null' )"
        printf '  "release": %s,\n'          "$( [ -n "$RELEASE" ] && printf '"%s"' "$(sj "$RELEASE")" || printf 'null' )"
        printf '  "git": { "sha": "%s", "branch": "%s", "dirty": %s },\n' "$GIT_SHA" "$(sj "$GIT_BRANCH")" "$GIT_DIRTY"
        printf '  "host": { "lua": "%s", "luacheck": "%s", "lizard": "%s" },\n' \
            "$(sj "$LUA_VERSION")" "$(sj "$LUACHECK_VERSION")" "$(sj "$LIZARD_VERSION")"
        printf '  "suites": {\n'
        suite_json lint       ", \"warnings\": $LINT_WARN, \"errors\": $LINT_ERR, \"files\": $LINT_FILES, \"gating\": true"; printf ',\n'
        suite_json tests      ", \"passed\": $TESTS_PASS, \"failed\": $TESTS_FAIL, \"total\": $TESTS_TOTAL, \"gating\": true"; printf ',\n'
        suite_json perf       ", \"scenarios\": $PERF_SCENARIOS, \"gating\": false"; printf ',\n'
        suite_json complexity ", \"warnings\": $CCN_WARN, \"maxCcn\": $CCN_MAX, \"nloc\": $CCN_NLOC, \"functions\": $CCN_FUNCS, \"avgCcn\": $CCN_AVG, \"avgNloc\": $CCN_AVG_NLOC, \"avgToken\": $CCN_AVG_TOKEN, \"warnFunRatio\": $CCN_FUN_RT, \"warnNlocRatio\": $CCN_NLOC_RT, \"bandFiles\": $CCN_BAND, \"overCapFiles\": $CCN_OVER, \"gating\": false"; printf '\n'
        printf '  },\n'
        printf '  "verdict": "%s"\n' "$VERDICT"
        printf '}\n'
    } > "$OUT/manifest.json"

    cell() { [ "${ST[$1]}" = "skip" ] && printf 'skip' || printf '%s' "$2"; }
    ROW="| [\`$STAMP\`]($STAMP/) | $ADDON_VERSION | $(cell lint "$LINT_WARN/$LINT_ERR") | $(cell tests "$TESTS_PASS/$TESTS_TOTAL") | $(cell perf "${ST[perf]}") | $(cell complexity "$CCN_WARN") | $(cell complexity "$CCN_MAX") | **$VERDICT** |"

    RESULTS="docs/automated-tests/RESULTS.md"
    HEADER='| Run | Version | Lint w/e | Tests | Perf | CCN warn | Max CCN | Verdict |'
    if [ -f "$RESULTS" ] && grep -qF "$HEADER" "$RESULTS"; then
        awk -v row="$ROW" -v hdr="$HEADER" '
            {print}
            $0 == hdr {getline sep; print sep; print row}
        ' "$RESULTS" > "$RESULTS.tmp" && mv "$RESULTS.tmp" "$RESULTS"
    else
        {
            printf '# Automated test results\n\n'
            printf '<!-- The newest run is prepended by tests/_kit/run-automated-tests.sh. -->\n'
            printf '<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->\n\n'
            printf 'One row per run. The frozen evidence for each is in the dated folder beside this file;\n'
            printf 'the analysis of a given run is its `ANALYSIS.md`.\n\n'
            printf '%s\n' "$HEADER"
            printf '|---|---|---|---|---|---|---|---|\n'
            printf '%s\n' "$ROW"
        } > "$RESULTS"
    fi

    echo "  bundle:  $OUT/"
    echo "  results: $RESULTS"
fi

[ "$VERDICT" = "red" ] && exit 1
exit 0
