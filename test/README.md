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

You install the tools one time. luacov, luacov-html, and Devel::Cover go into `lua_modules/` and `local/` in the repository. Git ignores both folders. kcov comes from Homebrew.

1. Install luarocks, cpanminus, and kcov:

   ```sh
   brew install luarocks cpanminus kcov
   ```

2. From the root of the repository, install luacov, luacov-html, and Devel::Cover:

   ```sh
   luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit)" --tree lua_modules install luacov
   luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit)" --tree lua_modules install luacov-html
   cpanm -L local --notest Devel::Cover
   ```

To remove the tools, delete `lua_modules/` and `local/`, and run `brew uninstall kcov`.

### Make the reports

To run the tests, make the HTML reports, and open them in your browser, run this command:

```sh
test/run.sh --open
```

The script writes these reports:

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
