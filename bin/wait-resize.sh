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
# app asks for. bin/measure.lua waits up to one second for that size and
# prints it. Rex sets REX_BLOCK in its panes. Then wait up to half a second
# for the terminal to get that size. With CACHE and SPEC, measure.lua also
# saves the size, so that later popups in this window fit their content more
# closely. If measure.lua prints no size, wait up to one second for any size
# other than 80x24.
wait_resize() {
    local want= size tries args
    if [[ -n "${REX_BLOCK:-}" ]]; then
        args=("block=$REX_BLOCK")
        [[ -n "${1:-}" && -n "${2:-}" ]] && args+=("cache=$1" "spec=$2")
        want=$("${REX_BIN_DIR:+$REX_BIN_DIR/}rex" do "$wait_resize_dir/measure.lua" "${args[@]}" 2>/dev/null)
        [[ "$want" =~ ^[0-9]+\ [0-9]+$ ]] || want=
    fi
    tries=50
    [[ -n "$want" ]] && tries=25
    while [[ "$tries" -gt 0 ]]; do
        size=$(stty size 2>/dev/null)
        if [[ -n "$want" ]]; then
            [[ "$size" == "$want" ]] && return 0
        else
            [[ "$size" != "24 80" ]] && return 0
        fi
        sleep 0.02
        tries=$((tries - 1))
    done
    return 0
}
