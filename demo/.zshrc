# The shell configuration for the demo pane that demo/record.sh opens.
# The git and npm functions print fixed sample output, so every recording
# shows the same URLs and needs no network or real project.

# The prompt uses the Monokai Pro colors as 24-bit escapes, so it looks the
# same with every Rex theme: the folder in orange and the branch in green on
# one line, and a green arrow on the line below.
orange=$'%{\e[38;2;252;152;103m%}'
green=$'%{\e[38;2;169;220;118m%}'
reset=$'%{\e[0m%}'
PROMPT="${orange}~/code/acme-app${reset} ${green}fix-login-redirect${reset}"$'\n'"${green}❯${reset} "
unset orange green reset
unsetopt BEEP
# The copied URLs end with no newline. Do not show the % mark that zsh puts
# after such output.
PROMPT_EOL_MARK=''
# Do not save the history of the demo shell into this folder.
HISTFILE=/dev/null

git() {
    cat <<'EOF'
Enumerating objects: 9, done.
Counting objects: 100% (9/9), done.
Delta compression using up to 10 threads
Compressing objects: 100% (5/5), done.
Writing objects: 100% (5/5), 1.21 KiB | 1.21 MiB/s, done.
Total 5 (delta 3), reused 0 (delta 0), pack-reused 0
remote:
remote: Create a pull request for 'fix-login-redirect' on GitHub by visiting:
remote:      https://github.com/acme/acme-app/pull/new/fix-login-redirect
remote:
To github.com:acme/acme-app.git
 * [new branch]      fix-login-redirect -> fix-login-redirect
EOF
}

# The Vite banner uses the same colors as Vite: the normal terminal colors,
# so they follow the Rex theme.
npm() {
    local g=$'\e[32m' c=$'\e[36m' b=$'\e[1m' d=$'\e[2m' r=$'\e[0m'
    cat <<EOF

> acme-app@0.4.0 dev
> vite

  ${g}${b}VITE${r} ${g}v8.3.6${r}  ${d}ready in ${r}${b}312${r}${d} ms${r}

  ${g}➜${r}  ${b}Local${r}:   ${c}http://localhost:${b}5173${r}${c}/${r}
  ${g}➜${r}  ${b}Network${r}: ${c}http://192.168.1.24:${b}5173${r}${c}/${r}
  ${g}➜${r}  ${b}Docs${r}:    ${c}https://vite.dev/guide/${r}
EOF
}
