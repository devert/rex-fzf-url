# harness.sh: the pass and fail counts and the checks that the bash tests
# share. Source it, and call finish at the end of the test file.
# Must stay compatible with macOS /bin/bash 3.2.

pass=0
fail=0

# check_eq <name> <expected> <got>
check_eq() {
  if [[ "$3" == "$2" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected: %s\n  got:      %s\n' "$1" "$2" "$3"
  fi
}

# Print the counts and return 1 when a check failed.
finish() {
  printf '%d passed, %d failed\n' "$pass" "$fail"
  [[ $fail -eq 0 ]]
}
