#!/usr/bin/env bash
# Tests for extract-urls. Must run under macOS /bin/bash 3.2.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
pass=0
fail=0

check() {
  # check <name> <input> <expected>
  local name=$1 input=$2 expected=$3 got
  got=$(printf '%s\n' "$input" | perl "$DIR/bin/extract-urls")
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected: %s\n  got:      %s\n' "$name" "$expected" "$got"
  fi
}

check "plain https" \
  "see https://example.com/a/b?q=1 for details" \
  "https://example.com/a/b?q=1"

check "trailing period excluded" \
  "read https://example.com/doc." \
  "https://example.com/doc"

check "ftp and file schemes" \
  $'ftp://ftp.gnu.org/gnu/bash/\nfile:///etc/hosts' \
  $'ftp://ftp.gnu.org/gnu/bash/\nfile:///etc/hosts'

check "git ssh remote rewritten" \
  "origin  git@github.com:wfxr/xre.git (fetch)" \
  "https://github.com/wfxr/xre.git"

check "git remote in parentheses drops the closing paren" \
  "clone (git@github.com:devert/rex-fzf-url.git) now" \
  "https://github.com/devert/rex-fzf-url.git"

check "www path in parentheses drops the closing paren" \
  "(see www.example.com/docs)" \
  "http://www.example.com/docs"

check "bare www prefixed" \
  "docs at www.rust-lang.org today" \
  "http://www.rust-lang.org"

check "https www counts once, kept verbatim" \
  "https://www.example.com/x" \
  "https://www.example.com/x"

check "ipv4 with port and path" \
  "listening on 127.0.0.1:8080/health now" \
  "http://127.0.0.1:8080/health"

check "quoted user/repo shorthand" \
  "plugin 'junegunn/fzf' is installed" \
  "https://github.com/junegunn/fzf"

check "dedup keeps first occurrence" \
  $'https://example.com\nhttps://example.com' \
  "https://example.com"

check "ansi colors stripped" \
  $'\e[31mhttps://red.example.com\e[0m' \
  "https://red.example.com"

check "osc8 hyperlink wrapper stripped" \
  $'\e]8;;https://osc.example.com\e\\link text\e]8;;\e\\ and https://plain.example.com' \
  $'https://osc.example.com\nhttps://plain.example.com'

check "multiple urls one line, in order" \
  "a https://one.example.com b https://two.example.com c" \
  $'https://one.example.com\nhttps://two.example.com'

check "no urls yields empty output" \
  "nothing to see here" \
  ""

# Extra-pattern passthrough
got=$(printf 'ticket JIRA-1234 done\n' | FZF_URL_EXTRA_PATTERN='JIRA-\d+' FZF_URL_EXTRA_SUB='https://jira.example.com/browse/$0' perl "$DIR/bin/extract-urls")
if [[ "$got" == "https://jira.example.com/browse/JIRA-1234" ]]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL extra pattern\n  got: %s\n' "$got"
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
