#!/usr/bin/env bash
# Full certification battery for Yankovinator releases
# Covers: build, unit, regression, UX, A/B, blackbox, E2E (Ollama), site
set -uo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
EXPECTED_VERSION="${YANKOVINATOR_EXPECT_VERSION:-1.06.13}"
REPORT_PATH="${YANKOVINATOR_CERT_REPORT:-docs/certification-latest.txt}"
REPORT_LINES=()

ok() {
  echo "PASS: $1"
  PASS=$((PASS+1))
  REPORT_LINES+=("PASS  $1")
}
bad() {
  echo "FAIL: $1"
  if [[ -n "${2:-}" ]]; then echo "$2"; fi
  FAIL=$((FAIL+1))
  REPORT_LINES+=("FAIL  $1")
}

BIN=".build/release"
Y="$BIN/yankovinator"
KG="$BIN/keyword-generator"
BM="$BIN/benchmark"
TUI_BIN="tui/target/release/yankovinator-tui"

section() { echo ""; echo "======== $* ========"; }

section "1) Builds"
swift build && ok "swift build debug" || bad "swift build debug" ""
swift build -c release && ok "swift build release" || bad "swift build release" ""

section "2) Unit / XCTest (full suite)"
if swift test 2>&1 | tee /tmp/yank-cert-swift.log | tail -12; then
  if rg -q "0 failures" /tmp/yank-cert-swift.log; then ok "swift test"; else bad "swift test" "failures in log"; fi
else
  bad "swift test" "$(tail -15 /tmp/yank-cert-swift.log)"
fi

section "3) CLI help (release binaries)"
for spec in "yankovinator --help" "keyword-generator --help" "benchmark --help"; do
  if $BIN/${spec%% *} ${spec#* } >/dev/null 2>&1; then ok "$spec"; else bad "$spec" ""; fi
done

section "4) UX: help content + version"
H=$($Y --help 2>&1)
VER=$($Y --version 2>&1 | tr -d '[:space:]')
[[ "$VER" == "$EXPECTED_VERSION" ]] && ok "version == $EXPECTED_VERSION" || bad "version == $EXPECTED_VERSION" "got: $VER"
for flag in no-progress midi-progress no-cloud-prescription candidates fresh-batch fit-optimize keep-candidates force workers; do
  echo "$H" | rg -q -- "$flag" && ok "help: $flag" || bad "help: $flag" ""
done
echo "$H" | rg -q "consumer" && ok "help: consumer pool note" || bad "help: consumer pool note" ""
echo "$H" | rg -q "ollama-num-parallel|OLLAMA_NUM_PARALLEL" && ok "help: ollama-num-parallel" || bad "help: ollama-num-parallel" ""
echo "$H" | rg -q "ollama-num-workers" && ok "help: ollama-num-workers alias" || bad "help: ollama-num-workers alias" ""
echo "$H" | rg -q "ollama-timeout" && ok "help: ollama-timeout" || bad "help: ollama-timeout" ""

section "4b) Rust TUI build"
if command -v cargo >/dev/null 2>&1; then
  if (cd tui && cargo build --release) 2>&1 | tail -3; then
    [[ -x "$TUI_BIN" ]] && ok "cargo build yankovinator-tui" || bad "cargo build yankovinator-tui" "missing binary"
  else
    bad "cargo build yankovinator-tui" ""
  fi
else
  bad "cargo missing" "install Rust for TUI cert"
fi

section "4c) Blackbox: Rust TUI stdin protocol"
if [[ -x "$TUI_BIN" ]]; then
  SNAP='{"t":"init","total":2,"workers":2,"label":"Cert"}'
  SNAP2='{"t":"snapshot","completed":1,"tick":3,"batch_spent_secs":1.5,"batch_eta_secs":2.0,"status":"cert","messages":["hello"],"workers":[{"idle":false,"job_number":1,"line":2,"line_total":10,"spent_secs":1.0,"eta_secs":1.0,"slot_tick":1},{"idle":true,"job_number":0,"line":null,"line_total":null,"spent_secs":0.5,"eta_secs":null,"slot_tick":0}]}'
  TUI_RUN=( "$TUI_BIN" )
  if [[ ! -t 0 ]]; then
    if command -v script >/dev/null 2>&1; then
      TUI_RUN=( script -q /dev/null "$TUI_BIN" )
    fi
  fi
  if printf '%s\n' "$SNAP" "$SNAP2" '{"t":"quit"}' | "${TUI_RUN[@]}" >/dev/null 2>&1; then
    ok "rust tui blackbox"
  else
    bad "rust tui blackbox" ""
  fi
else
  bad "rust tui blackbox" "binary missing"
fi

section "4d) Regression: focused XCTest filters"
for filter in \
  BatchResumeStoreTests \
  YankovinatorRustTUITests \
  ParallelJobRunnerTests \
  ParodyFitScorerTests \
  CloudBatchPrescriptionTests \
  CandidateParodyGeneratorTests
do
  if swift test --filter "$filter" 2>&1 | tee "/tmp/yank-cert-$filter.log" | tail -4; then
    rg -q "0 failures" "/tmp/yank-cert-$filter.log" && ok "filter:$filter" || bad "filter:$filter" ""
  else
    bad "filter:$filter" ""
  fi
done

# NL / fit-optimize regression (segfault class)
if swift test --filter testConcurrentNaturalLanguageAccess 2>&1 | tee /tmp/yank-cert-nl.log | tail -4; then
  rg -q "0 failures" /tmp/yank-cert-nl.log && ok "regression: concurrent NL" || bad "regression: concurrent NL" ""
else
  bad "regression: concurrent NL" ""
fi
if swift test --filter testRhymeLabelsDoNotOverflowPastZ 2>&1 | tee /tmp/yank-cert-rhyme.log | tail -4; then
  rg -q "0 failures" /tmp/yank-cert-rhyme.log && ok "regression: rhyme labels" || bad "regression: rhyme labels" ""
else
  bad "regression: rhyme labels" ""
fi

section "4e) A/B: Rust TUI env vs Swift fallback"
[[ "${YANKOVINATOR_RUST_TUI:-1}" != "0" ]] && ok "A/B: rust tui default enabled" || bad "A/B: rust tui default enabled" ""
if YANKOVINATOR_RUST_TUI=0 bash -c '[[ "$YANKOVINATOR_RUST_TUI" == "0" ]]'; then
  ok "A/B: rust tui opt-out env"
else
  bad "A/B: rust tui opt-out env" ""
fi
if [[ -x "$TUI_BIN" ]]; then
  export PATH="$(pwd)/tui/target/release:$PATH"
  command -v yankovinator-tui >/dev/null && ok "A/B: yankovinator-tui on PATH" || bad "A/B: yankovinator-tui on PATH" ""
  # Override path still preferred when set
  if YANKOVINATOR_TUI_PATH="$TUI_BIN" bash -c '[[ -x "$YANKOVINATOR_TUI_PATH" ]]'; then
    ok "A/B: YANKOVINATOR_TUI_PATH override"
  else
    bad "A/B: YANKOVINATOR_TUI_PATH override" ""
  fi
else
  bad "A/B: yankovinator-tui on PATH" "build missing"
fi

section "5) Validation / blackbox error contracts"
VAL_DIR=$(mktemp -d)
mkdir -p "$VAL_DIR/s" "$VAL_DIR/t" "$VAL_DIR/o"
WOUT=$($Y --input-dir "$VAL_DIR/s" --themes-dir "$VAL_DIR/t" --output-dir "$VAL_DIR/o" --workers 0 2>&1 || true)
echo "$WOUT" | rg -qi "Workers must" && ok "blackbox: workers=0 rejected" || bad "blackbox: workers=0 rejected" "$WOUT"
COUT=$($Y --input-dir "$VAL_DIR/s" --themes-dir "$VAL_DIR/t" --output-dir "$VAL_DIR/o" --candidates 0 2>&1 || true)
echo "$COUT" | rg -qi "Candidates must" && ok "blackbox: candidates=0 rejected" || bad "blackbox: candidates=0 rejected" "$COUT"
rm -rf "$VAL_DIR"
IOUT=$($Y --input-dir "/tmp/nonexistent-yank-empty-$$" --themes-dir "/tmp/themes-yank-$$" --output-dir "/tmp/out-$$" 2>&1 || true)
echo "$IOUT" | rg -qi "No \\.txt lyrics files found in input directory" && ok "blackbox: bad input-dir" || bad "blackbox: bad input-dir" "$IOUT"
ALIAS_DIR=$(mktemp -d)
mkdir -p "$ALIAS_DIR/s" "$ALIAS_DIR/t" "$ALIAS_DIR/o"
ALIAS=$($Y --input-dir "$ALIAS_DIR/s" --themes-dir "$ALIAS_DIR/t" --output-dir "$ALIAS_DIR/o" --ollama-num-workers 10 --force 2>&1 || true)
echo "$ALIAS" | rg -qi "No \\.txt lyrics files found in input directory" && ok "blackbox: ollama-num-workers alias" || bad "blackbox: ollama-num-workers alias" "$ALIAS"
rm -rf "$ALIAS_DIR"

# Fingerprint mismatch (user-facing contract for --fresh-batch)
FP_DIR=$(mktemp -d)
mkdir -p "$FP_DIR/songs" "$FP_DIR/themes" "$FP_DIR/out/.yankovinator"
cp data/example_lyrics.txt "$FP_DIR/songs/s.txt"
cp data/example_keywords.txt "$FP_DIR/themes/t.txt"
cat > "$FP_DIR/out/.yankovinator/manifest.json" <<'JSON'
{"version":1,"model":"stale-model","candidates":99,"jobsFingerprint":"deadbeefdeadbeefdeadbeefdeadbeef","startedAt":"2020-01-01T00:00:00Z","updatedAt":"2020-01-01T00:00:00Z"}
JSON
FPOUT=$($Y --input-dir "$FP_DIR/songs" --themes-dir "$FP_DIR/themes" --output-dir "$FP_DIR/out" --candidates 1 --no-progress 2>&1 || true)
if echo "$FPOUT" | rg -qi "does not match this run|fresh-batch"; then
  ok "blackbox: fingerprint mismatch asks --fresh-batch"
else
  bad "blackbox: fingerprint mismatch asks --fresh-batch" "$FPOUT"
fi
rm -rf "$FP_DIR"

section "6) Site / GitHub Pages TypeScript"
npm run build && ok "npm run build" || bad "npm run build" ""

section "7) Ollama probe"
OLLAMA_UP=0
if curl -s -o /dev/null -w "%{http_code}" http://localhost:11434/api/tags | rg -q "200"; then
  OLLAMA_UP=1
  ok "ollama http"
else
  bad "ollama http" "E2E sections skipped (start ollama for full cert)"
fi

if [[ "$OLLAMA_UP" == "1" ]]; then
  section "8) E2E batch one song × one theme"
  TMP=$(mktemp -d)
  mkdir -p "$TMP/songs" "$TMP/themes" "$TMP/out"
  cp data/example_lyrics.txt "$TMP/songs/s.txt"
  cp data/example_keywords.txt "$TMP/themes/t1.txt"
  if $Y --input-dir "$TMP/songs" --themes-dir "$TMP/themes" --output-dir "$TMP/out" --no-progress 2>&1 | tail -3; then
    [[ -s "$TMP/out/t1/s.parody.txt" ]] && ok "E2E: batch parody" || bad "E2E: batch parody" "empty output"
  else
    bad "E2E: batch parody" ""
  fi

  section "9) E2E candidates=3"
  rm -rf "$TMP/out"
  if $Y --input-dir "$TMP/songs" --themes-dir "$TMP/themes" --output-dir "$TMP/out" --candidates 3 --no-progress 2>&1 | tail -5; then
    [[ -s "$TMP/out/t1/s.parody.txt" ]] && ok "E2E: candidates" || bad "E2E: candidates" ""
  else
    bad "E2E: candidates" ""
  fi

  section "10) E2E batch 2 songs × one theme"
  cp data/example_lyrics.txt "$TMP/songs/a.txt"
  cp data/example_lyrics.txt "$TMP/songs/b.txt"
  rm -rf "$TMP/out2"
  mkdir -p "$TMP/out2"
  if $Y --input-dir "$TMP/songs" --themes-dir "$TMP/themes" --output-dir "$TMP/out2" --workers 4 --candidates 2 --no-progress 2>&1 | tail -5; then
    [[ -f "$TMP/out2/t1/a.parody.txt" && -f "$TMP/out2/t1/b.parody.txt" ]] && ok "E2E: songs×theme×candidates" || bad "E2E: batch outputs missing" ""
  else
    bad "E2E: songs×theme" ""
  fi

  section "11) E2E cross-product (mini, force)"
  mkdir -p "$TMP/cout"
  cp data/example_keywords.txt "$TMP/themes/t2.txt"
  if $Y --input-dir "$TMP/songs" --themes-dir "$TMP/themes" --output-dir "$TMP/cout" --workers 10 --candidates 2 --no-progress --force 2>&1 | tail -5; then
    [[ -f "$TMP/cout/t1/a.parody.txt" && -f "$TMP/cout/t2/a.parody.txt" ]] && ok "E2E: cross-product×candidates" || bad "E2E: cross-product outputs" ""
  else
    bad "E2E: cross-product" ""
  fi

  section "12) keyword-generator E2E"
  if $KG "space" --count 2 --output "$TMP/kg.txt" 2>&1 | tail -3; then
    [[ -s "$TMP/kg.txt" ]] && ok "E2E: keyword-generator" || bad "E2E: keyword-generator empty" ""
  else
    bad "E2E: keyword-generator" ""
  fi

  section "13) benchmark E2E"
  if $BM --lyrics data/example_lyrics.txt --keywords data/example_keywords.txt --iterations 1 --workers 2 >/tmp/yank-bm.log 2>&1; then
    ok "E2E: benchmark"
  else
    bad "E2E: benchmark" "$(tail -5 /tmp/yank-bm.log)"
  fi

  section "14) E2E resume checkpoint + --fresh-batch"
  RES=$(mktemp -d)
  mkdir -p "$RES/songs" "$RES/themes" "$RES/out"
  cp data/example_lyrics.txt "$RES/songs/r.txt"
  cp data/example_keywords.txt "$RES/themes/t.txt"
  if $Y --input-dir "$RES/songs" --themes-dir "$RES/themes" --output-dir "$RES/out" --candidates 2 --no-progress 2>&1 | tail -3; then
    [[ -d "$RES/out/.yankovinator" ]] && ok "E2E: resume checkpoint dir" || bad "E2E: resume checkpoint dir" ""
    [[ -f "$RES/out/.yankovinator/manifest.json" ]] && ok "E2E: resume manifest" || bad "E2E: resume manifest" ""
    echo stale > "$RES/out/.yankovinator/stale.marker"
  else
    bad "E2E: resume run" ""
  fi
  if $Y --input-dir "$RES/songs" --themes-dir "$RES/themes" --output-dir "$RES/out" --candidates 2 --fresh-batch --no-progress 2>&1 | tail -3; then
    [[ ! -f "$RES/out/.yankovinator/stale.marker" ]] && ok "E2E: fresh-batch clears checkpoint" || bad "E2E: fresh-batch" ""
  else
    bad "E2E: fresh-batch" ""
  fi
  rm -rf "$RES"

  section "15) Regression E2E: --fit-optimize concurrent (NL segfault class)"
  FIT=$(mktemp -d)
  mkdir -p "$FIT/songs" "$FIT/themes" "$FIT/out"
  cp data/example_lyrics.txt "$FIT/songs/f.txt"
  cp data/example_keywords.txt "$FIT/themes/t.txt"
  # Progress off still stresses parallel fit scoring / NL embeddings.
  if YANKOVINATOR_RUST_TUI=0 $Y \
      --input-dir "$FIT/songs" --themes-dir "$FIT/themes" --output-dir "$FIT/out" \
      --workers 4 --candidates 2 --fit-optimize --force --no-progress --fresh-batch \
      2>&1 | tee /tmp/yank-cert-fit.log | tail -8; then
    [[ -s "$FIT/out/t/f.parody.txt" ]] && ok "E2E: fit-optimize workers=4" || bad "E2E: fit-optimize workers=4" "empty output"
  else
    bad "E2E: fit-optimize workers=4" "$(tail -20 /tmp/yank-cert-fit.log)"
  fi
  rm -rf "$FIT"

  section "16) UX A/B E2E: progress on vs --no-progress (short)"
  AB=$(mktemp -d)
  mkdir -p "$AB/songs" "$AB/themes" "$AB/out-a" "$AB/out-b"
  cp data/example_lyrics.txt "$AB/songs/s.txt"
  cp data/example_keywords.txt "$AB/themes/t.txt"
  if YANKOVINATOR_RUST_TUI=0 $Y \
      --input-dir "$AB/songs" --themes-dir "$AB/themes" --output-dir "$AB/out-a" \
      --workers 2 --candidates 1 --no-progress --fresh-batch \
      2>&1 | tee /tmp/yank-cert-ab-a.log | tail -3; then
    [[ -s "$AB/out-a/t/s.parody.txt" ]] && ok "A/B: --no-progress path" || bad "A/B: --no-progress path" ""
  else
    bad "A/B: --no-progress path" "$(tail -10 /tmp/yank-cert-ab-a.log)"
  fi
  # Interactive progress (single-line Swift when Rust TUI disabled) must not crash.
  if YANKOVINATOR_RUST_TUI=0 $Y \
      --input-dir "$AB/songs" --themes-dir "$AB/themes" --output-dir "$AB/out-b" \
      --workers 2 --candidates 1 --fresh-batch \
      2>&1 | tee /tmp/yank-cert-ab-b.log | tail -5; then
    [[ -s "$AB/out-b/t/s.parody.txt" ]] && ok "A/B: progress-enabled path" || bad "A/B: progress-enabled path" ""
  else
    bad "A/B: progress-enabled path" "$(tail -20 /tmp/yank-cert-ab-b.log)"
  fi
  rm -rf "$AB"

  rm -rf "$TMP"
fi

section "CERTIFICATION SUMMARY"
{
  echo "Yankovinator certification report"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Expected version: $EXPECTED_VERSION"
  echo "Host: $(uname -srm)"
  echo "Pass: $PASS  Fail: $FAIL"
  echo ""
  printf '%s\n' "${REPORT_LINES[@]}"
} | tee "$REPORT_PATH"
echo "Wrote $REPORT_PATH"
echo "======== CERTIFICATION SUMMARY: $PASS passed, $FAIL failed ========"
if [[ "$FAIL" -ne 0 ]]; then exit 1; fi
