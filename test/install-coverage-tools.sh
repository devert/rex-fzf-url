#!/usr/bin/env bash
# install-coverage-tools.sh: install the tools that test/run.sh --coverage
# needs. Must stay compatible with macOS /bin/bash 3.2.
#
# Homebrew installs luajit, luarocks, cpanminus, and kcov, if they are
# missing. luacov and luacov-html go into lua_modules/, and Devel::Cover
# goes into local/, in this repository. You can run this script again.
set -eu

cd "$(dirname "$0")/.."

command -v brew >/dev/null || { echo "install-coverage-tools.sh: Homebrew not found" >&2; exit 1; }

missing=()
for formula in luajit luarocks cpanminus kcov; do
  brew list --versions "$formula" >/dev/null || missing+=("$formula")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  brew install "${missing[@]}"
fi

# The tests run on luajit, which is Lua 5.1.
for rock in luacov luacov-html; do
  luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit)" --tree lua_modules install "$rock"
done

cpanm -L local --notest Devel::Cover

echo "Coverage tools installed. Run: test/run.sh --open"
