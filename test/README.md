# Tests

The tests do not need Rex. Fake programs and a fake `rex` Lua table replace Rex, fzf, and the clipboard tools.

## Requirements

- `luajit`, or `lua` 5.1 or later
- `perl`. The macOS Perl works.
- `/bin/bash`. The bash tests must work with bash 3.2, the macOS version.

## Run the tests

From the root of the repository, run all the test files:

```sh
test/run.sh
```

The script prints the pass and fail counts for each file. For each failed check, it prints the expected value and the value it got. If a check fails, the script exits with status 1.

To run one file:

```sh
luajit test/init.test.lua
/bin/bash test/picker.test.sh
```

## Test files

Each test file tests one source file:

- `init.test.lua` tests `init.lua`.
- `popup-size.test.lua` tests `lib/popup-size.lua`.
- `measure.test.lua` tests `bin/measure.lua`.
- `extract-urls.test.sh` tests `bin/extract-urls`.
- `picker.test.sh` tests `bin/picker.sh`.
- `message.test.sh` tests `bin/message.sh`.

`harness.lua` and `harness.sh` hold the checks that the test files share. Name a new test file `<source>.test.lua` or `<source>.test.sh`, so that `run.sh` finds it.

## Coverage

Coverage shows which lines of code the tests ran. luacov measures `init.lua`, `lib/popup-size.lua`, and `bin/measure.lua`. Devel::Cover measures `bin/extract-urls`. kcov measures `bin/picker.sh` and `bin/message.sh`.

### Install the coverage tools

You install the tools one time. You need Homebrew. Run this command:

```sh
test/install-coverage-tools.sh
```

If luajit, luarocks, cpanminus, or kcov is missing, the script installs it with Homebrew. It installs luacov and luacov-html into `lua_modules/`, and Devel::Cover into `local/`, in the repository. Git ignores both folders. You can run the script again.

To remove the tools, delete `lua_modules/` and `local/`, and run `brew uninstall kcov`.

### Make the reports

To run the tests and make the HTML reports, run this command:

```sh
test/run.sh --open
```

The script opens `test/coverage.html` in your browser. It has a link to each report, and each link opens in a new tab. The reports are:

- `luacov-html/index.html` for the Lua code
- `cover_db/coverage.html` for `bin/extract-urls`
- `kcov/index.html` for the bash scripts

To get only the summaries in the terminal, run this command:

```sh
test/run.sh --coverage
```

Both commands also write `luacov.report.out`, which gives the hit count for each line of Lua. A line that did not run starts with `*` characters and a `0`.

If the tools are not installed, the script stops with an error. Each coverage run deletes the reports from the previous run. Git ignores the report files.

kcov does not count the first line of the `fzf` call in `bin/picker.sh`. bash 3.2 reports a command that spans lines at its last line, so kcov never sees a hit on the first line.
