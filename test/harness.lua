-- harness.lua: the pass and fail counts and the checks that the Lua tests
-- share. Load it with dofile, and call done at the end of the test file.

local H = { passed = 0, failed = 0 }

-- Rex runs plugins with plain Lua 5.1, not LuaJIT. Remove what LuaJIT adds,
-- so that code that uses it fails here too. The goto statement can't be
-- removed, as it is syntax.
bit, jit = nil, nil
for _, name in ipairs({ "bit", "jit", "jit.opt", "jit.util", "jit.profile",
  "ffi", "string.buffer", "table.new", "table.clear" }) do
  package.loaded[name] = nil
  package.preload[name] = nil
end

-- Count a check that passes when ok is true. detail is printed on failure.
function H.ok(name, ok, detail)
  if ok then
    H.passed = H.passed + 1
  else
    H.failed = H.failed + 1
    print("FAIL " .. name .. (detail and ("\n  " .. detail) or ""))
  end
end

-- Count a check that passes when got equals expected.
function H.eq(name, got, expected)
  H.ok(name, got == expected,
    string.format("expected: %q\n  got:      %q", tostring(expected), tostring(got)))
end

-- Count a check that passes when fn(...) raises exactly the error expected.
function H.raises(name, expected, fn, ...)
  local ok, err = pcall(fn, ...)
  H.ok(name, not ok and err == expected,
    string.format("expected error: %s\n  got:            %s", expected, ok and "no error" or tostring(err)))
end

-- Print the counts and exit with 1 when a check failed.
function H.done()
  print(string.format("%d passed, %d failed", H.passed, H.failed))
  os.exit(H.failed == 0 and 0 or 1)
end

return H
