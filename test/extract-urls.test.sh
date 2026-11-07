#!/usr/bin/env bash
# Tests for extract-urls. Must run under macOS /bin/bash 3.2.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/test/harness.sh"

# check <name> <input> <expected> [REGEX URL ...]
check() {
  local name=$1 input=$2 expected=$3
  shift 3
  check_eq "$name" "$expected" "$(printf '%s\n' "$input" | perl "$DIR/bin/extract-urls.pl" "$@" 2>&1)"
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

check "ssh:// git remote rewritten" \
  "url = ssh://git@github.com/wfxr/xre.git" \
  "https://github.com/wfxr/xre.git"

check "git remote in parentheses drops the closing paren" \
  "clone (git@github.com:devert/rex-fzf-url.git) now" \
  "https://github.com/devert/rex-fzf-url.git"

check "www path in parentheses drops the closing paren" \
  "(see www.example.com/docs)" \
  "http://www.example.com/docs"

check "www path drops a trailing period" \
  "see www.example.com/docs." \
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

check "ipv4 alone, and a trailing comma dropped" \
  "hosts 10.0.0.1:80/x, 10.0.0.2 up" \
  $'http://10.0.0.1:80/x\nhttp://10.0.0.2'

check "single-quoted user/repo shorthand" \
  "plugin 'junegunn/fzf' is installed" \
  "https://github.com/junegunn/fzf"

check "double-quoted user/repo shorthand" \
  'use "junegunn/fzf.vim" here' \
  "https://github.com/junegunn/fzf.vim"

check "dedup keeps first occurrence" \
  $'https://example.com\nhttps://example.com' \
  "https://example.com"

check "ansi colors stripped" \
  $'\e[31mhttps://red.example.com\e[0m' \
  "https://red.example.com"

check "private mode CSI stripped" \
  $'\e[?25lhttps://a.example.com\e[?25h' \
  "https://a.example.com"

check "osc8 hyperlink wrapper stripped" \
  $'\e]8;;https://osc.example.com\e\\link text\e]8;;\e\\ and https://plain.example.com' \
  $'https://osc.example.com\nhttps://plain.example.com'

check "osc title dropped with the URL in it" \
  $'\e]0;title https://title.example.com\a then https://x.example.com' \
  "https://x.example.com"

check "multiple urls one line, in order" \
  "a https://one.example.com b https://two.example.com c" \
  $'https://one.example.com\nhttps://two.example.com'

check "no urls yields empty output" \
  "nothing to see here" \
  ""

# Extra patterns, passed as REGEX URL argument pairs.

check "one extra pattern" \
  "ticket JIRA-1234 done" \
  "https://jira.example.com/browse/JIRA-1234" \
  'JIRA-\d+' 'https://jira.example.com/browse/$0'

check "two extra patterns, in list order per line" \
  $'fix ENG-7 and PR #42\nthen ENG-8' \
  $'https://linear.app/x/issue/ENG-7\nhttps://github.com/o/r/pull/42\nhttps://linear.app/x/issue/ENG-8' \
  'ENG-\d+' 'https://linear.app/x/issue/$0' \
  '#(\d+)' 'https://github.com/o/r/pull/$1'

check "empty url emits the match" \
  "id abc-123" \
  "abc-123" \
  'abc-\d+' ''

check "a missing group gives an empty string" \
  "ENG-5" \
  "u/5/" \
  'ENG-(\d+)' 'u/$1/$2'

check "an extra URL that a built-in pattern found counts once" \
  "ENG-1 https://linear.app/x/issue/ENG-1" \
  "https://linear.app/x/issue/ENG-1" \
  'ENG-\d+' 'https://linear.app/x/issue/$0'

check "odd argument count fails" \
  "x" \
  "extract-urls: extra patterns need REGEX URL pairs" \
  'only-a-regex'

printf 'x\n' | perl "$DIR/bin/extract-urls.pl" '(' 'u' >/dev/null 2>&1
check_eq "an invalid regex fails" "yes" "$([[ $? -ne 0 ]] && echo yes || echo no)"

finish
