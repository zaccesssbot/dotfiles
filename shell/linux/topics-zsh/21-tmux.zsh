# =============================================================================
# tmux - terminal multiplexer
# Requires: apt install tmux
# Project layouts, each a session named after the folder (Ctrl+B then f picks a folder for ide):
#   ide [folder]      Neovim, a shell, a scene and a lazygit window
#   idev [folder]     Neovim over a shell, the dev server's logs and a scene, plus lazygit
#   imon [folder]     btop beside docker ps and a scene
#   ilab [folder]     Neovim over a build shell, a serial monitor shell and a scene
#   ilog [folder]     two log shells side by side and a scene
#   iplay [folder]    Zacess Games beside a scene
#   ireview [folder]  Neovim over gh pr status, lazygit and a scene
#   itest [folder]    Neovim over a test watcher, a shell and a scene, plus lazygit
# =============================================================================

ta() {
    local session="${1:-main}"
    # inside tmux, attaching would nest one session in another, so the session is made detached
    # when it is missing and the client switches to it, the same as ide
    if [ -n "$TMUX" ]; then
        tmux has-session -t "=$session" 2>/dev/null || tmux new-session -d -s "$session"
        tmux switch-client -t "=$session"
    else
        tmux attach-session -t "$session" 2>/dev/null || tmux new-session -s "$session"
    fi
}

tn() {
    local session="${1:?Usage: tn <session-name>}"
    if [ -n "$TMUX" ]; then
        tmux new-session -d -s "$session" && tmux switch-client -t "=$session"
    else
        tmux new-session -s "$session"
    fi
}
alias tls="tmux list-sessions"
tk() { tmux kill-session -t "${1:?Usage: tk <session-name>}"; }
alias tka="tmux kill-server"
alias tw="tmux new-window"
alias ts="tmux split-window -v"
alias tss="tmux split-window -h"
alias tconf="tmux source-file ~/.tmux.conf"
alias tlog="tmux capture-pane -p"
alias td="tmux detach-client"
tren() { tmux rename-session "${1:?Usage: tren <new-name>}"; }
tkillother() { tmux kill-session -a; }

cluster() {
    tmux new-session -d -s cluster -x 220 -y 50
    tmux rename-window -t cluster 'nodes'
    tmux send-keys -t cluster 'ssh node1' Enter
    tmux split-window -t cluster -h
    tmux send-keys -t cluster 'ssh node2' Enter
    tmux split-window -t cluster -v
    tmux send-keys -t cluster 'ssh node3' Enter
    tmux select-pane -t cluster:0.0
    tmux split-window -t cluster -v
    tmux send-keys -t cluster 'ssh node4' Enter
    tmux attach-session -t cluster
}

# The project layouts below share these helpers, so each layout only says where its panes go.
# _ide_open names the session after the folder, plus the layout's suffix so two layouts of one
# folder can be open at once. It also takes the size the layout will be seen at so the shares come
# out right. It sets dir, name, width and height for the layout calling it and returns 1 when
# there is no such folder and 2 when the session is already open.
_ide_open() {
    if ! dir="$(cd "${3:-.}" 2>/dev/null && pwd -P)"; then
        printf '%s: there is no folder %s\n' "$1" "${3:-.}" >&2
        return 1
    fi
    # tmux reads a dot or a colon in a session name as a separator, so both become dashes
    name="$(basename "$dir" | tr -c 'A-Za-z0-9_\n-' '-')$2"
    tmux has-session -t "=$name" 2>/dev/null && return 2
    if [ -n "$TMUX" ]; then
        width="$(tmux display-message -p '#{window_width}')"
        height="$(tmux display-message -p '#{window_height}')"
    else
        width="$(tput cols)"
        height="$(tput lines)"
    fi
    return 0
}

# _ide_main <window name>: the new session's first pane, printed as its pane id
_ide_main() {
    tmux new-session -d -P -F '#{pane_id}' -s "$name" -n "$1" -c "$dir" -x "$width" -y "$height"
}

# _ide_split <pane> <-v or -h> <share>: a shell split from another pane, printed as its pane id
_ide_split() {
    tmux split-window "$2" -l "$3" -P -F '#{pane_id}' -t "$1" -c "$dir"
}

# _ide_scene <pane> <-v or -h> <share>: a Zacess scene that follows the shells in this session,
# calm while commands work and stormy when one fails. Left out when Zacess Scenes is not installed
_ide_scene() {
    if command -v zacess-scenes >/dev/null 2>&1; then
        tmux split-window "$2" -l "$3" -d -t "$1" -c "$dir" 'zacess-scenes follow'
    fi
}

# _ide_git: a second window running lazygit, when lazygit is installed and the folder is a git
# repository. Ctrl+B then 2 (or Ctrl+B then n) goes to it
_ide_git() {
    if command -v lazygit >/dev/null 2>&1 && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        tmux new-window -d -t "=$name:" -n git -c "$dir"
        tmux send-keys -t "=$name:git" lazygit Enter
    fi
}

# _ide_show [pane]: the focus goes to the layout's main pane, then the session opens (switched to
# from inside tmux, attached from outside it)
_ide_show() {
    if [ -n "$1" ]; then tmux select-pane -t "$1"; fi
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "=$name"
    else
        tmux attach-session -t "=$name"
    fi
}

# ide: a project's workspace in tmux. Neovim takes the top 70 percent, a shell sits bottom left
# and a Zacess scene bottom right follows that shell, calm while commands work and stormy when
# one fails. A folder that is a git repository also gets a git window running lazygit. Running
# it again for the same folder goes back to the open session rather than making another.
#   ide            the current folder
#   ide <folder>   another folder
ide() {
    local dir name width height editor shell
    _ide_open ide '' "$1" || { [ $? -eq 2 ] && _ide_show; return; }
    editor="$(_ide_main editor)"
    tmux send-keys -t "$editor" 'nvim .' Enter
    shell="$(_ide_split "$editor" -v 30%)"
    _ide_scene "$shell" -h 35%
    _ide_git
    _ide_show "$editor"
}

# idev: web development. Neovim on top (65 percent) over a row of a shell, the dev server's logs
# and a scene, plus the lazygit window. The logs pane runs npm run dev when package.json has a
# dev script, php artisan serve in a Laravel project and is a plain shell otherwise
idev() {
    local dir name width height editor shell logs
    _ide_open idev -dev "$1" || { [ $? -eq 2 ] && _ide_show; return; }
    editor="$(_ide_main editor)"
    tmux send-keys -t "$editor" 'nvim .' Enter
    shell="$(_ide_split "$editor" -v 35%)"
    # the bottom row is shell 35, logs 40 and scene 25 percent: logs takes 65 percent of the row,
    # then the scene takes 38 percent of that
    logs="$(_ide_split "$shell" -h 65%)"
    _ide_scene "$logs" -h 38%
    if [ -f "$dir/package.json" ] && grep -q '"dev"[[:space:]]*:' "$dir/package.json"; then
        tmux send-keys -t "$logs" 'npm run dev' Enter
    elif [ -f "$dir/artisan" ]; then
        tmux send-keys -t "$logs" 'php artisan serve' Enter
    fi
    _ide_git
    _ide_show "$editor"
}

# imon: system monitor. btop (or else htop or top) on the left 65 percent, with docker ps refreshing
# every five seconds above a scene on the right. Without Docker that pane is a plain shell
imon() {
    local dir name width height monitor side
    _ide_open imon -mon "$1" || { [ $? -eq 2 ] && _ide_show; return; }
    monitor="$(_ide_main monitor)"
    if command -v btop >/dev/null 2>&1; then
        tmux send-keys -t "$monitor" btop Enter
    elif command -v htop >/dev/null 2>&1; then
        tmux send-keys -t "$monitor" htop Enter
    else
        tmux send-keys -t "$monitor" top Enter
    fi
    side="$(_ide_split "$monitor" -h 35%)"
    if command -v docker >/dev/null 2>&1; then
        # a loop rather than watch, which macOS does not ship. A stopped daemon gets one short line
        # rather than a repeated connection error. It is checked again every five seconds
        tmux send-keys -t "$side" 'while :; do clear; docker ps 2>/dev/null || echo "Docker is not running"; sleep 5; done' Enter
    fi
    _ide_scene "$side" -v 50%
    _ide_show "$monitor"
}

# ilab: embedded and lab work. Neovim on top (65 percent) over a row of a build shell ready for
# make or avr-gcc, a serial monitor shell and a scene. Nothing runs by itself in the bottom row,
# since the build and the serial port differ per board
ilab() {
    local dir name width height editor build serial
    _ide_open ilab -lab "$1" || { [ $? -eq 2 ] && _ide_show; return; }
    editor="$(_ide_main editor)"
    tmux send-keys -t "$editor" 'nvim .' Enter
    build="$(_ide_split "$editor" -v 35%)"
    # build 40, serial 35 and scene 25 percent of the row
    serial="$(_ide_split "$build" -h 60%)"
    _ide_scene "$serial" -h 42%
    _ide_show "$editor"
}

# ilog: two shells side by side for following logs, with a small scene bottom right. Nothing
# tails by itself, since the log files differ per project
ilog() {
    local dir name width height left right
    _ide_open ilog -log "$1" || { [ $? -eq 2 ] && _ide_show; return; }
    left="$(_ide_main logs)"
    right="$(_ide_split "$left" -h 50%)"
    _ide_scene "$right" -v 30%
    _ide_show "$left"
}

# iplay: Zacess Games large on the left (a shell when it is not installed), a scene beside it
iplay() {
    local dir name width height game
    _ide_open iplay -play "$1" || { [ $? -eq 2 ] && _ide_show; return; }
    game="$(_ide_main play)"
    if command -v zacess-games >/dev/null 2>&1; then
        tmux send-keys -t "$game" zacess-games Enter
    fi
    _ide_scene "$game" -h 35%
    _ide_show "$game"
}

# ireview: reviewing pull requests. Neovim on top (65 percent) over a row of gh pr status
# refreshing every minute, lazygit and a scene. Without gh that pane is a plain shell; lazygit
# is left out when it is not installed or the folder is not a git repository
ireview() {
    local dir name width height editor prs lazy
    _ide_open ireview -review "$1" || { [ $? -eq 2 ] && _ide_show; return; }
    editor="$(_ide_main editor)"
    tmux send-keys -t "$editor" 'nvim .' Enter
    prs="$(_ide_split "$editor" -v 35%)"
    if command -v gh >/dev/null 2>&1; then
        tmux send-keys -t "$prs" 'while :; do clear; gh pr status; sleep 60; done' Enter
    fi
    if command -v lazygit >/dev/null 2>&1 && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # gh 40, lazygit 35 and scene 25 percent of the row
        lazy="$(_ide_split "$prs" -h 60%)"
        tmux send-keys -t "$lazy" lazygit Enter
        _ide_scene "$lazy" -h 42%
    else
        _ide_scene "$prs" -h 25%
    fi
    _ide_show "$editor"
}

# itest: testing. Neovim on top (65 percent) over a row of a test watcher, a shell and a scene,
# plus the lazygit window. The watcher runs the first that fits: the package.json test script
# (vitest when the project uses it), php artisan test, pytest (pytest -f with pytest-xdist),
# cargo watch when cargo-watch is installed. Otherwise it is a plain shell
itest() {
    local dir name width height editor watcher shell watch
    _ide_open itest -test "$1" || { [ $? -eq 2 ] && _ide_show; return; }
    editor="$(_ide_main editor)"
    tmux send-keys -t "$editor" 'nvim .' Enter
    watcher="$(_ide_split "$editor" -v 35%)"
    # watcher 45, shell 30 and scene 25 percent of the row: the shell and scene take 55 percent,
    # then the scene takes 45 percent of that
    shell="$(_ide_split "$watcher" -h 55%)"
    _ide_scene "$shell" -h 45%
    watch="$(_ide_watcher)"
    if [ -n "$watch" ]; then tmux send-keys -t "$watcher" "$watch" Enter; fi
    _ide_git
    _ide_show "$editor"
}

# _ide_watcher: the test command itest runs for the folder, nothing when no runner fits
_ide_watcher() {
    if [ -f "$dir/package.json" ] && grep -q '"test"[[:space:]]*:' "$dir/package.json"; then
        if grep -q '"vitest"[[:space:]]*:' "$dir/package.json"; then echo 'npx vitest'; else echo 'npm test -- --watch'; fi
    elif [ -f "$dir/artisan" ]; then
        echo 'php artisan test'
    elif command -v pytest >/dev/null 2>&1 && { [ -f "$dir/pytest.ini" ] || [ -f "$dir/conftest.py" ] || [ -d "$dir/tests" ] ||
        grep -qs '\[tool\.pytest' "$dir/pyproject.toml"; }; then
        # a real module of pytest-xdist, since an uninstall can leave an empty xdist folder that imports
        if python3 -c 'import xdist.plugin' >/dev/null 2>&1; then echo 'pytest -f'; else echo 'pytest'; fi
    elif [ -f "$dir/Cargo.toml" ] && command -v cargo-watch >/dev/null 2>&1; then
        echo 'cargo watch -x test'
    fi
}

# ide-pick: the list Ctrl+B then f shows in tmux. Every folder in IDE_ROOTS (folders separated by
# colons, the repos folder by default), filtered as you type. The one picked opens in ide
ide-pick() {
    local pick
    pick="$(printf '%s\n' "${IDE_ROOTS:-$HOME/dev/github/repos}" | tr ':' '\n' | while IFS= read -r root; do
        [ -d "$root" ] && find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '.*'
    done | sort | fzf --prompt 'project> ' --height 100% --reverse)"
    [ -n "$pick" ] && ide "$pick"
}
