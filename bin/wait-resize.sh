# wait-resize.sh: bin/picker.sh and bin/message.sh source this file.
# Must stay compatible with macOS /bin/bash 3.2.
#
# The terminal of a floating pane starts at the default size of 80x24, and
# the app sets the size of the pane shortly after it opens. Text that a
# script prints before the resize can end up broken or out of view.
# wait_resize waits for that resize.

# The folder of this file, which also holds measure.lua.
wait_resize_dir=${BASH_SOURCE[0]%/*}

# wait_resize [CACHE SPEC]: wait until the terminal has the size that the
# app asks for. bin/measure.lua waits for that size and prints it. Rex sets
# REX_BLOCK in its panes. `rex do` can hang when the app is busy, so stop it
# after wait_resize_limit seconds. Then check the terminal size
# wait_resize_tries more times, 20 ms apart, until it has that size. The
# whole wait can take longer than these numbers say, because each check also
# starts stty and sleep.
# With CACHE and SPEC, measure.lua also saves the size, so that later popups
# in this window fit their content more closely.
# The terminal can settle on a size other than the one that measure.lua
# printed, for example when the window changes size during the wait. So a
# size other than 80x24 that stays the same for wait_resize_stable checks
# also ends the wait. That is about 0.2 seconds, which is longer than the
# steps of a resize usually take. If measure.lua prints no size, only such
# a size ends the wait. When stty finds no terminal, there is no size to
# wait for, so return at once.
# Return 0 when the terminal has its new size, and 1 when the wait timed out.
wait_resize_limit=1
wait_resize_tries=25
wait_resize_stable=10
wait_resize() {
    local want= size last= same=0 tries=$wait_resize_tries args
    if [[ -n "${REX_BLOCK:-}" ]]; then
        args=("block=$REX_BLOCK")
        [[ -n "${1:-}" && -n "${2:-}" ]] && args+=("cache=$1" "spec=$2")
        want=$(wait_resize_run "${REX_BIN_DIR:+$REX_BIN_DIR/}rex" do "$wait_resize_dir/measure.lua" "${args[@]}")
        [[ "$want" =~ ^[0-9]+\ [0-9]+$ ]] || want=
    fi
    while :; do
        size=$(stty size 2>/dev/null)
        [[ -n "$size" ]] || return 0
        [[ "$size" == "$want" ]] && return 0
        if [[ "$size" != "24 80" && "$size" == "$last" ]]; then
            same=$((same + 1))
            [[ "$same" -ge "$wait_resize_stable" ]] && return 0
        else
            same=1
        fi
        last=$size
        # Check once more after the last sleep, so that it is not wasted.
        [[ "$tries" -le 0 ]] && return 1
        sleep 0.02
        tries=$((tries - 1))
    done
}

# wait_resize_run COMMAND...: run the command and print its output. Stop it
# after wait_resize_limit seconds. macOS has no timeout command, so a
# watchdog in the background sleeps, then stops the command. The watchdog
# sends its output to /dev/null, so that the command substitution of the
# caller does not wait for it. It uses /bin/sleep, as the tests replace
# sleep in PATH. When the command ends first, stop the watchdog. Its sleep
# then ends on its own.
# Send stderr to /dev/null for each command, not for the whole function:
# test coverage reads the trace of bash 3.2 from stderr.
wait_resize_run() {
    local pid dog
    "$@" 2>/dev/null &
    pid=$!
    { /bin/sleep "$wait_resize_limit"; kill "$pid" 2>/dev/null; } >/dev/null &
    dog=$!
    wait "$pid" 2>/dev/null
    kill "$dog" 2>/dev/null
}
