# The shell configuration for the demo pane that demo/record.sh opens.
# The git and npm functions print fixed sample output, so every recording
# shows the same URLs and needs no network or real project.

PROMPT='%F{cyan}~/code/acme-app%f %F{magenta}❯%f '
unsetopt BEEP

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

npm() {
    cat <<'EOF'

> acme-app@0.4.0 dev
> vite

  VITE v7.1.3  ready in 312 ms

  ➜  Local:   http://localhost:5173/
  ➜  Network: http://192.168.1.24:5173/
  ➜  Docs:    https://vite.dev/guide/
EOF
}
