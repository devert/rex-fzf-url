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
# a size ends the wait, or a size of 80x24 that stays the same for all the
# checks. When stty finds no terminal, there is no size to wait for, so
# return at once.
# The terminal does not echo keys during the wait. An echoed key moves the
# cursor, and fzf then draws one row lower. The keys stay in the input for
# the script that runs after the wait.
# measure.lua prints the size on its last line of output. `rex do` can
# print other lines too, so use the last line that is a size.
# Return 0 when the terminal has its new size, and 1 when the wait timed out.
wait_resize_limit=1
wait_resize_tries=25
wait_resize_stable=10
wait_resize() {
    local saved status
    saved=$(stty -g 2>/dev/null)
    [[ -n "$saved" ]] && stty -echo 2>/dev/null
    wait_resize_size "$@"
    status=$?
    [[ -n "$saved" ]] && stty "$saved" 2>/dev/null
    return "$status"
}

# wait_resize_size [CACHE SPEC]: the wait of wait_resize, with the same
# return status.
# perl's alarm stops `rex do` after the limit, as macOS has no timeout
# command, and the --timeout option of rex does not stop a script. The
# alarm stays on when perl replaces itself with `rex do`, so no other
# process has to stop it.
wait_resize_size() {
    local want= out line size last= same=0 tries=$wait_resize_tries args
    if [[ -n "${REX_BLOCK:-}" ]]; then
        args=("block=$REX_BLOCK")
        [[ -n "${1:-}" && -n "${2:-}" ]] && args+=("cache=$1" "spec=$2")
        out=$(perl -e 'alarm shift; exec @ARGV or exit 127' "$wait_resize_limit" "${REX_BIN_DIR:+$REX_BIN_DIR/}rex" do "$wait_resize_dir/measure.lua" "${args[@]}" 2>/dev/null)
        while IFS= read -r line; do [[ "$line" =~ ^[0-9]+\ [0-9]+$ ]] && want=$line; done <<<"$out"
    fi
    while :; do
        size=$(stty size 2>/dev/null)
        [[ -n "$size" ]] || return 0
        [[ "$size" == "$want" ]] && return 0
        if [[ "$size" == "$last" ]]; then
            same=$((same + 1))
        else
            same=1
        fi
        [[ "$size" != "24 80" && "$same" -ge "$wait_resize_stable" ]] && return 0
        last=$size
        # Check once more after the last sleep, so that it is not wasted.
        # With no wanted size, a size that did not change in all the checks
        # is the real size, even when it is 80x24.
        if [[ "$tries" -le 0 ]]; then
            [[ -z "$want" && "$same" -gt "$wait_resize_tries" ]] && return 0
            return 1
        fi
        sleep 0.02
        tries=$((tries - 1))
    done
}
