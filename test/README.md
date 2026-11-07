# Tests

The tests do not need Rex. Fake programs and a fake `rex` Lua table replace Rex, fzf, the clipboard tools, and the URL openers.

## Requirements

- `luajit`, or `lua` 5.1 or later
- `perl`. The macOS Perl works.
- `/bin/bash`. The bash tests must work with bash 3.2, the macOS version.

## Run the tests

From the root of the repository, run all the test files:

```sh
test/run.sh
```

If a check fails, the script exits with status 1.

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
- `extract-urls.test.sh` tests `bin/extract-urls.pl`.
- `picker.test.sh` tests `bin/picker.sh`.
- `message.test.sh` tests `bin/message.sh`.

`harness.lua` and `harness.sh` hold the checks that the test files share.

Give a new test file the name of its source file without the extension, then `.test.lua` or `.test.sh`. `run.sh` finds test files by these names.

## Coverage

Coverage shows which lines of code the tests ran. luacov measures `init.lua`, `lib/popup-size.lua`, and `bin/measure.lua`. Devel::Cover measures `bin/extract-urls.pl`. kcov measures `bin/picker.sh` and `bin/message.sh`.

### Install the coverage tools

Install the tools one time. This step needs Homebrew. Run this command:

```sh
test/install-coverage-tools.sh
```

If luajit, luarocks, cpanminus, or kcov is missing, the script installs it with Homebrew. The script installs luacov and luacov-html into `lua_modules/`, and Devel::Cover into `local/`, in the repository. You can run the script again.

To remove the tools, do these steps:

1. Delete `lua_modules/` and `local/`.
2. Uninstall the Homebrew formulas that the script installed and that nothing else uses. If you run the tests, keep luajit.

   ```sh
   brew uninstall kcov luarocks cpanminus
   brew autoremove
   ```

   `brew autoremove` removes the dependencies that no other formula needs, such as the `lua` that luarocks installed.

### Make the reports

To run the tests and make the reports, run this command:

```sh
test/run.sh --coverage
```

The script shows a summary of test coverage in the terminal. It also prints the `file://` URL of `test/coverage.html`, a page with a link to each HTML report.

To do the same and also open that page in your browser, run this command:

```sh
test/run.sh --open
```

If the tools are not installed, the script stops with an error. Each coverage run deletes the reports from the previous run.
