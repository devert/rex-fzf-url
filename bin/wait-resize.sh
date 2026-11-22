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
# app asks for. bin/measure.lua waits up to half a second for that size and
# prints it. Rex sets REX_BLOCK in its panes. Then wait up to half a second
# for the terminal to get that size. With CACHE and SPEC, measure.lua also
# saves the size, so that later popups in this window fit their content more
# closely. If measure.lua prints no size, wait for any size other than
# 80x24.
# The terminal can settle on a size other than the one that measure.lua
# printed, for example when the window changes size during the wait. So a
# size other than 80x24 that stays the same for wait_resize_stable checks
# also ends the wait.
# Return 0 when the terminal has its new size, and 1 when the wait timed out.
wait_resize_stable=5
wait_resize() {
    local want= size last= same=0 tries=25 args
    if [[ -n "${REX_BLOCK:-}" ]]; then
        args=("block=$REX_BLOCK")
        [[ -n "${1:-}" && -n "${2:-}" ]] && args+=("cache=$1" "spec=$2")
        want=$("${REX_BIN_DIR:+$REX_BIN_DIR/}rex" do "$wait_resize_dir/measure.lua" "${args[@]}" 2>/dev/null)
        [[ "$want" =~ ^[0-9]+\ [0-9]+$ ]] || want=
    fi
    while [[ "$tries" -gt 0 ]]; do
        size=$(stty size 2>/dev/null)
        if [[ -n "$want" ]]; then
            [[ "$size" == "$want" ]] && return 0
            if [[ "$size" != "24 80" && "$size" == "$last" ]]; then
                same=$((same + 1))
                [[ "$same" -ge "$wait_resize_stable" ]] && return 0
            else
                same=1
            fi
            last=$size
        else
            [[ "$size" != "24 80" ]] && return 0
        fi
        sleep 0.02
        tries=$((tries - 1))
    done
    return 1
}
