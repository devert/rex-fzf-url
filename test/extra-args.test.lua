-- Tests for extra_args in init.lua, which turns the extra_patterns option
-- into REGEX URL argument pairs for bin/extract-urls. Run with luajit or
-- lua 5.1 or later:
--
--   luajit test/extra-args.test.lua

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."

rex = {}
local extra_args = dofile(dir .. "/../init.lua")._extra_args

local pass, fail = 0, 0

local function check(name, list, expected)
  local got = table.concat(extra_args(list), "|")
  expected = table.concat(expected, "|")
  if got == expected then
    pass = pass + 1
  else
    fail = fail + 1
    print(string.format("FAIL %s\n  expected: %s\n  got:      %s", name, expected, got))
  end
end

local function check_error(name, list, expected)
  local ok, err = pcall(extra_args, list)
  if not ok and err == expected then
    pass = pass + 1
  else
    fail = fail + 1
    print(string.format("FAIL %s\n  expected error: %s\n  got:            %s",
      name, expected, ok and "no error" or tostring(err)))
  end
end

check("no extra_patterns gives no arguments", nil, {})

check("an empty list gives no arguments", {}, {})

check("two entries give four arguments in list order", {
  { regex = [[ENG-\d+]], url = "https://linear.app/x/issue/$0" },
  { regex = [[PR #(\d+)]], url = "https://github.com/o/r/pull/$1" },
}, {
  [[ENG-\d+]], "https://linear.app/x/issue/$0",
  [[PR #(\d+)]], "https://github.com/o/r/pull/$1",
})

check("an entry with no url gives an empty url", {
  { regex = "abc-\\d+" },
}, { "abc-\\d+", "" })

check_error("extra_patterns that is not a list", "ENG-\\d+",
  "fzf-url: extra_patterns must be a list")

check_error("an entry with no regex", {
  { regex = "a", url = "u" },
  { url = "u" },
}, "fzf-url: extra_patterns[2] needs a regex string")

check_error("an entry with an empty regex", {
  { regex = "", url = "u" },
}, "fzf-url: extra_patterns[1] needs a regex string")

check_error("a url that is not a string", {
  { regex = "a", url = 3 },
}, "fzf-url: extra_patterns[1].url must be a string")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
