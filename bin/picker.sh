#!/usr/bin/env bash
# picker.sh: runs inside the floating Rex pane that the fzf_url action opens.
# The action already read the scrollback, extracted the URLs, and wrote them
# to the file in $1. Enter opens the selection, ctrl-y copies it, and tab
# selects more than one. The pane closes when this script exits.
# Must stay compatible with macOS /bin/bash 3.2.
#
# Environment, set by init.lua from the setup() options:
#   FZF_URL_OPEN_CMD     command that opens a URL (default: open or xdg-open)
#   FZF_URL_COPY_CMD     command that copies stdin to the clipboard
#   FZF_URL_FZF_PATH     the full path of fzf (default: fzf in PATH)
#   FZF_URL_FZF_OPTIONS  extra fzf options
#   FZF_URL_SOURCE_BLOCK the pane that ran the action
#   FZF_URL_HEADER       the help text below the prompt (default: the text
#                        in the layout table of init.lua)
#   FZF_URL_HEIGHT       the rows that fzf needs, with each URL on one row
#   FZF_URL_WRAP         "URL_COLS WRAP_COLS WIDTH...": the layout values and
#                        the widths of the URLs that can wrap. A "w" after
#                        a width marks a URL with a wide character.
#   FZF_URL_CACHE        the file where bin/measure.lua saves window sizes
#   FZF_URL_MEASURE      what bin/measure.lua needs to know about this pane
set -u

# Rex doesn't give focus back to the pane that ran the action when a floating
# pane closes, so do it on every exit. Rex sets REX_BIN_DIR in its panes.
refocus() {
    [[ -n "${FZF_URL_SOURCE_BLOCK:-}" ]] &&
        "${REX_BIN_DIR:+$REX_BIN_DIR/}rex" focus "$FZF_URL_SOURCE_BLOCK" >/dev/null 2>&1
}
trap refocus EXIT

# wait_resize waits until the app gives the pane its size (see
# bin/wait-resize.sh).
. "${0%/*}/wait-resize.sh"
resized=

# No `set -e`: a pane that closes without a message is hard to debug.
# Failures print a message and pause so the user can read it. A message
# that prints before the pane gets its size can end up broken or out of
# view, so wait for the size first.
fail() {
    [[ -n "$resized" ]] || wait_resize
    resized=1
    printf 'fzf-url: %s\n' "$1" >&2
    sleep 2
    exit 1
}

# Rex starts this pane without a shell, so PATH is the one of the Rex app.
# An app that starts from Finder gets only the system folders, without the
# folders that shell startup files add. So add the folders where fzf and
# other tools are usually installed. They go last, so PATH still wins.
# FZF_URL_EXTRA_PATH replaces the list, for the tests.
# An empty part, `.`, or another relative part in PATH finds programs in the
# current folder. Bash's default PATH, when it starts with no PATH, ends in
# `.`. So keep only the parts that start with `/`.
# Export PATH, because bash does not export the default PATH that it sets.
# nohup and other programs need the folders too.
# With `set -u`, an unset HOME would stop the script, so get HOME from the
# user database then. Export it for fzf and the opener.
export HOME=${HOME:-$(cd ~ 2>/dev/null && pwd)}
default_extra="/opt/homebrew/bin:/usr/local/bin" # Homebrew
default_extra+=":/opt/local/bin"                 # MacPorts
default_extra+=":$HOME/.fzf/bin"                 # the fzf install script
default_extra+=":$HOME/.local/bin"
default_extra+=":$HOME/.nix-profile/bin"         # Nix
default_extra+=":/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin" # nix-darwin
default_extra+=":$HOME/.local/share/mise/shims"  # mise
extra=${FZF_URL_EXTRA_PATH-$default_extra}
new_path=
old_ifs=$IFS
IFS=:
set -f
for dir in $PATH:$extra; do
    case $dir in /*) new_path=${new_path:+$new_path:}$dir ;; esac
done
set +f
IFS=$old_ifs
export PATH=$new_path

# Read and remove the URL file first, so that no failure leaves it behind.
url_file="${1:-}"
[[ -n "$url_file" && -f "$url_file" ]] || fail "no URL list file"
urls=$(<"$url_file")
rm -f "$url_file"

if [[ -n "${FZF_URL_FZF_PATH:-}" ]]; then
    fzf=$FZF_URL_FZF_PATH
    # Expand only `~` and `~/...`. `~name` is left as it is.
    case $fzf in '~' | '~/'*) fzf=$HOME${fzf#\~} ;; esac
    # A name without a slash is a command in PATH. A relative path with a
    # slash would depend on the folder of this pane, which the user does not
    # know, so reject it.
    case $fzf in
        */*) [[ "$fzf" == /* ]] || fail "fzf_path must start with / or ~/: $FZF_URL_FZF_PATH" ;;
        *) fzf=$(type -P "$fzf") || fail "fzf_path not found in PATH: $FZF_URL_FZF_PATH" ;;
    esac
    [[ -f "$fzf" && -x "$fzf" ]] || fail "fzf_path is not an executable file: $FZF_URL_FZF_PATH"
else
    fzf=fzf
    command -v fzf >/dev/null 2>&1 ||
        fail "fzf not found. Set fzf_path in setup() to the full path of fzf."
fi

[[ -z "$urls" ]] && exit 0

# Draw fzf from the top of the pane, as tall as its content. init.lua works
# out that height from the layout that the fzf options below set. There is
# no bottom padding row, as Rex pads the bottom of a floating pane. The pane
# can be one or two rows taller than that, and the extra rows are then at
# the bottom. Two extra rows can happen in the first popup in a window,
# before bin/measure.lua saves the size of the window.
# Wait for the app to resize the pane, as fzf draws in place with --height,
# so lines that it draws before the resize stay on the screen. This also
# saves the size of the pane (see bin/wait-resize.sh).
# With more URLs than fit, fzf limits --height to the pane height, so it
# fills the pane and scrolls the list.
# When the wait times out, the pane can still change size after fzf starts.
# Then, and without a height, leave out --height. fzf then uses the whole
# screen and draws it again after a resize, with no stale lines.

# fzf_height: print the rows that fzf needs in this pane. That is
# FZF_URL_HEIGHT, plus the extra rows of each URL in FZF_URL_WRAP that wraps
# at the columns of the pane. This is the count of wrapped_rows in init.lua.
# Change them together. Return 1 when the height is not known.
# A "w" after a width marks a URL with a wide character. fzf moves a wide
# character that does not fit at the end of a row to the next row, so such
# a URL can lose one column on each row.
fzf_height() {
    local height=${FZF_URL_HEIGHT:-} size url_cols wrap_cols text w n loss per
    [[ "$height" =~ ^[0-9]+$ ]] || return 1
    set -f
    # shellcheck disable=SC2086
    set -- ${FZF_URL_WRAP:-}
    set +f
    if [[ $# -gt 0 ]]; then
        size=$(stty size 2>/dev/null)
        [[ "$size" =~ ^[0-9]+\ [0-9]+$ && $# -ge 3 ]] || return 1
        url_cols=$1 wrap_cols=$2
        [[ "$url_cols" =~ ^[0-9]+$ && "$wrap_cols" =~ ^[0-9]+$ ]] || return 1
        shift 2
        for w in "$@"; do [[ "$w" =~ ^[0-9]+w?$ ]] || return 1; done
        text=$((${size#* } - url_cols))
        [[ "$text" -gt "$wrap_cols" ]] || text=$((wrap_cols + 1))
        # A URL of n columns takes
        # ceil((n - text + loss) / (text - wrap_cols - loss)) extra rows.
        for w in "$@"; do
            n=${w%w} loss=0
            [[ "$w" == *w ]] && loss=1
            if [[ "$n" -gt "$text" ]]; then
                per=$((text - wrap_cols - loss))
                [[ "$per" -ge 1 ]] || per=1
                height=$((height + (n - text + loss + per - 1) / per))
            fi
        done
    fi
    echo "$height"
}

height_args=()
resized=1
if wait_resize "${FZF_URL_CACHE:-}" "${FZF_URL_MEASURE:-}" && height=$(fzf_height); then
    height_args=(--height "$height")
fi

# --no-border, --no-margin, and --no-padding stop FZF_DEFAULT_OPTS from adding
# rows that the popup size does not count. Those rows hide part of the URL list.
# --multi lets Tab select more than one URL. --wrap wraps a long URL onto more
# rows instead of cutting it off. fzf_height counts those extra rows.
# The padding, the header, and its border set the layout that init.lua sizes
# the pane for. Change them together with the layout table in init.lua.
# Rest of fzf options ported from junegunn/tmux-fzf-url's fzf-url.rb.
# --expect reports the pressed key (ctrl-y, or empty for Enter) on the first output
# line. The selections follow.
# $FZF_URL_FZF_OPTIONS is intentionally unquoted: word-splitting is the point.
# shellcheck disable=SC2086
selection=$(printf '%s\n' "$urls" | "$fzf" \
    --multi --no-margin --no-padding --no-border --wrap \
    --expect ctrl-y --style default \
    --header "${FZF_URL_HEADER-Enter: Open URL / CTRL-Y: Copy to clipboard}" \
    --header-border top --header-first \
    --highlight-line --info inline-right \
    --padding 0,0,0,1 \
    ${height_args[@]+"${height_args[@]}"} \
    ${FZF_URL_FZF_OPTIONS:-})
# fzf exits 1 when nothing matches and 130 on Esc. Any other failure, such as
# an fzf that is too old for these options, gets a message. fzf prints its
# own error above it.
fzf_status=$?
if [[ "$fzf_status" -ne 0 ]]; then
    [[ "$fzf_status" -eq 1 || "$fzf_status" -eq 130 ]] && exit 0
    fail "fzf failed with exit status $fzf_status"
fi

key=${selection%%$'\n'*}
chosen=
[[ "$selection" == *$'\n'* ]] && chosen=${selection#*$'\n'}
[[ -z "$chosen" ]] && exit 0

get_copy_cmd() {
    if [[ -n "${FZF_URL_COPY_CMD:-}" ]]; then echo "$FZF_URL_COPY_CMD"
    elif command -v pbcopy >/dev/null 2>&1; then echo "pbcopy"
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then echo "wl-copy"
    elif [[ -n "${DISPLAY:-}" ]] && command -v xclip >/dev/null 2>&1; then echo "xclip -selection clipboard"
    elif [[ -n "${DISPLAY:-}" ]] && command -v xsel >/dev/null 2>&1; then echo "xsel --clipboard --input"
    fi
}

# The pane closes when this script exits, so openers other than macOS
# `open` are detached with nohup to outlive it.
open_url() {
    if [[ -n "${FZF_URL_OPEN_CMD:-}" ]]; then nohup $FZF_URL_OPEN_CMD "$1" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then open "$1"
    elif command -v xdg-open >/dev/null 2>&1; then nohup xdg-open "$1" >/dev/null 2>&1 &
    elif [[ -n "${BROWSER:-}" ]]; then nohup "$BROWSER" "$1" >/dev/null 2>&1 &
    else fail "no opener found (open/xdg-open/\$BROWSER)"
    fi
}

if [[ "$key" == "ctrl-y" ]]; then
    cmd=$(get_copy_cmd)
    [[ -z "$cmd" ]] && fail "no clipboard tool found (pbcopy/wl-copy/xclip/xsel)"
    printf '%s' "$chosen" | $cmd
else
    while IFS= read -r url; do
        [[ -n "$url" ]] && open_url "$url"
    done <<< "$chosen"
    wait
fi
