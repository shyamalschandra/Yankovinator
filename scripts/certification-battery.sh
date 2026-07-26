#!/usr/bin/env bash
# Full certification battery for Yankovinator releases
set -uo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; if [[ -n "${2:-}" ]]; then echo "$2"; fi; FAIL=$((FAIL+1)); }

BIN=".build/release"
Y="$BIN/yankovinator"
KG="$BIN/keyword-generator"
BM="$BIN/benchmark"

echo "======== 1) Builds ========"
swift build && ok "swift build debug" || bad "swift build debug" ""
swift build -c release && ok "swift build release" || bad "swift build release" ""

echo "======== 2) XCTest ========"
if swift test 2>&1 | tee /tmp/yank-cert-swift.log | tail -8; then
  if rg -q "0 failures" /tmp/yank-cert-swift.log; then ok "swift test"; else bad "swift test" "failures in log"; fi
else bad "swift test" "$(tail -15 /tmp/yank-cert-swift.log)"
fi

echo "======== 3) CLI help (release) ========"
for spec in "yankovinator --help" "keyword-generator --help" "benchmark --help"; do
  if $BIN/${spec%% *} ${spec#* } >/dev/null 2>&1; then ok "$spec"; else bad "$spec" ""; fi
done

echo "======== 4) Help content (new flags) ========"
H=$($Y --help 2>&1)
echo "$H" | rg -q "no-progress" && ok "help: no-progress" || bad "help: no-progress" ""
echo "$H" | rg -q "midi-progress" && ok "help: midi-progress" || bad "help: midi-progress" ""
echo "$H" | rg -q "no-cloud-prescription" && ok "help: no-cloud-prescription" || bad "help: no-cloud-prescription" ""
echo "$H" | rg -q "consumer" && ok "help: consumer pool note" || bad "help: consumer pool note" ""
echo "$H" | rg -q "ollama-num-parallel|OLLAMA_NUM_PARALLEL" && ok "help: ollama-num-parallel" || bad "help: ollama-num-parallel" ""
echo "$H" | rg -q "ollama-num-workers" && ok "help: ollama-num-workers alias" || bad "help: ollama-num-workers alias" ""
echo "$H" | rg -q "ollama-timeout" && ok "help: ollama-timeout" || bad "help: ollama-timeout" ""
echo "$H" | rg -q "candidates" && ok "help: candidates" || bad "help: candidates" ""

echo "======== 5) Validation errors ========"
VAL_DIR=$(mktemp -d)
mkdir -p "$VAL_DIR/s" "$VAL_DIR/t" "$VAL_DIR/o"
WOUT=$($Y --input-dir "$VAL_DIR/s" --themes-dir "$VAL_DIR/t" --output-dir "$VAL_DIR/o" --workers 0 2>&1 || true)
if echo "$WOUT" | rg -qi "Workers must"; then ok "workers=0 rejected"; else bad "workers=0 rejected" "$WOUT"; fi
COUT=$($Y --input-dir "$VAL_DIR/s" --themes-dir "$VAL_DIR/t" --output-dir "$VAL_DIR/o" --candidates 0 2>&1 || true)
if echo "$COUT" | rg -qi "Candidates must"; then ok "candidates=0 rejected"; else bad "candidates=0 rejected" "$COUT"; fi
rm -rf "$VAL_DIR"
IOUT=$($Y --input-dir "/tmp/nonexistent-yank-empty-$$" --themes-dir "/tmp/themes-yank-$$" --output-dir "/tmp/out-$$" 2>&1 || true)
if echo "$IOUT" | rg -qi "No \\.txt lyrics files found in input directory"; then ok "bad input-dir"; else bad "bad input-dir" "$IOUT"; fi
ALIAS_DIR=$(mktemp -d)
mkdir -p "$ALIAS_DIR/s" "$ALIAS_DIR/t" "$ALIAS_DIR/o"
ALIAS=$($Y --input-dir "$ALIAS_DIR/s" --themes-dir "$ALIAS_DIR/t" --output-dir "$ALIAS_DIR/o" --ollama-num-workers 10 --force 2>&1 || true)
if echo "$ALIAS" | rg -qi "No \\.txt lyrics files found in input directory"; then ok "ollama-num-workers alias batch"; else bad "ollama-num-workers alias batch" "$ALIAS"; fi
rm -rf "$ALIAS_DIR"

echo "======== 6) npm / TS site ========"
npm run build && ok "npm run build" || bad "npm run build" ""

echo "======== 7) Ollama probe ========"
OLLAMA_UP=0
if curl -s -o /dev/null -w "%{http_code}" http://localhost:11434/api/tags | rg -q "200"; then
  OLLAMA_UP=1
  ok "ollama http"
else
  bad "ollama http" "E2E skipped"
fi

if [[ "$OLLAMA_UP" == "1" ]]; then
  echo "======== 8) E2E batch one song × one theme ========"
  TMP=$(mktemp -d)
  mkdir -p "$TMP/songs" "$TMP/themes" "$TMP/out"
  cp data/example_lyrics.txt "$TMP/songs/s.txt"
  cp data/example_keywords.txt "$TMP/themes/t1.txt"
  if $Y --input-dir "$TMP/songs" --themes-dir "$TMP/themes" --output-dir "$TMP/out" --no-progress 2>&1 | tail -3; then
    [[ -s "$TMP/out/t1/s.parody.txt" ]] && ok "batch parody E2E" || bad "batch parody E2E" "empty output"
  else
    bad "batch parody E2E" ""
  fi

  echo "======== 9) E2E candidates=3 ========"
  rm -rf "$TMP/out"
  if $Y --input-dir "$TMP/songs" --themes-dir "$TMP/themes" --output-dir "$TMP/out" --candidates 3 --no-progress 2>&1 | tail -5; then
    [[ -s "$TMP/out/t1/s.parody.txt" ]] && ok "candidates E2E" || bad "candidates E2E" ""
  else
    bad "candidates E2E" ""
  fi

  echo "======== 10) E2E batch 2 songs × one theme ========"
  cp data/example_lyrics.txt "$TMP/songs/a.txt"
  cp data/example_lyrics.txt "$TMP/songs/b.txt"
  rm -rf "$TMP/out2"
  mkdir -p "$TMP/out2"
  if $Y --input-dir "$TMP/songs" --themes-dir "$TMP/themes" --output-dir "$TMP/out2" --workers 4 --candidates 2 --no-progress 2>&1 | tail -5; then
    [[ -f "$TMP/out2/t1/a.parody.txt" && -f "$TMP/out2/t1/b.parody.txt" ]] && ok "batch songs×theme×candidates" || bad "batch outputs missing" ""
  else
    bad "batch songs×theme" ""
  fi

  echo "======== 11) E2E cross-product (mini, force) ========"
  mkdir -p "$TMP/cout"
  cp data/example_keywords.txt "$TMP/themes/t2.txt"
  if $Y --input-dir "$TMP/songs" --themes-dir "$TMP/themes" --output-dir "$TMP/cout" --workers 10 --candidates 2 --no-progress --force 2>&1 | tail -5; then
    [[ -f "$TMP/cout/t1/a.parody.txt" && -f "$TMP/cout/t2/a.parody.txt" ]] && ok "cross-product×candidates" || bad "cross-product outputs" ""
  else
    bad "cross-product" ""
  fi

  echo "======== 12) keyword-generator E2E ========"
  if $KG "space" --count 2 --output "$TMP/kg.txt" 2>&1 | tail -3; then
    [[ -s "$TMP/kg.txt" ]] && ok "keyword-generator E2E" || bad "keyword-generator empty" ""
  else
    bad "keyword-generator E2E" ""
  fi

  echo "======== 13) benchmark E2E ========"
  if $BM --lyrics data/example_lyrics.txt --keywords data/example_keywords.txt --iterations 1 --workers 2 >/tmp/yank-bm.log 2>&1; then
    ok "benchmark E2E"
  else
    bad "benchmark E2E" "$(tail -5 /tmp/yank-bm.log)"
  fi

  rm -rf "$TMP"
fi

echo ""
echo "======== CERTIFICATION SUMMARY: $PASS passed, $FAIL failed ========"
if [[ "$FAIL" -ne 0 ]]; then exit 1; fi
