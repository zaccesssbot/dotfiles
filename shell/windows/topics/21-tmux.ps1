# =============================================================================
# tmux / Windows Terminal shortcuts
# tmux on Windows is psmux, a native tmux that runs PowerShell panes and reads ~/.tmux.conf
# (linked to terminal\tmux\windows\tmux.conf). WSL keeps its own tmux and the Linux config:
# inside Ubuntu, ide and these names are the Linux versions. Windows Terminal itself handles
# tabs and panes natively too, so a few shortcuts cover that as well.
# Project layouts, each a psmux session named after the folder:
#   ide [folder]      nvim, a shell, a scene and a lazygit window
#   idev [folder]     nvim over a shell, the dev server's logs and a scene, plus lazygit
#   imon [folder]     btop4win beside docker ps and a scene
#   ilab [folder]     nvim over a build shell, a serial monitor shell and a scene
#   ilog [folder]     two log shells side by side and a scene
#   iplay [folder]    Zacess Games beside a scene
#   ireview [folder]  nvim over gh pr status, lazygit and a scene
#   itest [folder]    nvim over a test watcher, a shell and a scene, plus lazygit
#   ide-pick          a fuzzy list of the project folders, the picked one opens in ide (Ctrl+B then f)
# =============================================================================

# wt: open a new Windows Terminal tab in the current directory
function wt-here { wt -d (Get-Location).Path }

# wt-split: open a split pane in Windows Terminal
function wt-split { wt sp -d (Get-Location).Path }

# tmux through psmux
# inside psmux, attaching would nest one session in another ("sessions should be nested with
# care"), so ta and tn make the session detached and switch the client to it, the same as ide
function _in_psmux { [bool]($env:TMUX -or $env:PSMUX_SESSION) }

# _psmux_out: psmux run as if from outside a session. psmux keeps a server per session. from inside
# a pane a session named with the exact-match form ("=name") was not found, while the same command
# from outside was. the pane's psmux variables are cleared for the call and put back after,
# and a pane on a named server (-L) keeps that server
function _psmux_out {
    if (-not (_in_psmux)) { psmux @args; return }
    # TMUX names the server: /tmp/psmux-<pid>/<server>,<port>,<id>, "default" for the usual one.
    # PSMUX_SESSION is not used, since a pane can keep the name of the spare server its session took over
    $server = @()
    if ($env:TMUX -match '/([^/,]+),' -and $Matches[1] -ne 'default') { $server = '-L', $Matches[1] }
    $saved = @{}
    foreach ($name in 'TMUX', 'TMUX_PANE', 'PSMUX_SESSION', 'PSMUX_TARGET_SESSION') {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    try { psmux @server @args } finally {
        foreach ($name in $saved.Keys) { if ($null -ne $saved[$name]) { Set-Item "Env:$name" $saved[$name] } }
    }
}

function ta {
    param([string]$Session = "main")
    if (_in_psmux) {
        _psmux_out has-session -t "=$Session" 2>$null
        if ($LASTEXITCODE -ne 0) { _psmux_out new-session -d -s $Session }
        psmux switch-client -t "=$Session"
        return
    }
    psmux attach-session -t $Session 2>$null
    if ($LASTEXITCODE -ne 0) { psmux new-session -s $Session }
}

function tn {
    param([string]$Session)
    if (-not $Session) { Write-Error 'Usage: tn <session-name>'; return }
    if (_in_psmux) {
        _psmux_out new-session -d -s $Session
        if ($LASTEXITCODE -eq 0) { psmux switch-client -t "=$Session" }
        return
    }
    psmux new-session -s $Session
}
function tls   { _psmux_out list-sessions }
function tk    { param([string]$Session) _psmux_out kill-session -t $Session }
function tka   { _psmux_out kill-server }
function tw    { psmux new-window }
function ts    { psmux split-window -v }
function tss   { psmux split-window -h }
function tconf { psmux source-file '~/.tmux.conf' }
function tlog  { psmux capture-pane -p }
function td    { psmux detach-client }
function tren  { param([string]$Name) psmux rename-session $Name }
# tkillother: kill every session except the one this pane is in. psmux's kill-session -a kills the
# current session and keeps the others, the opposite of tmux, so each other session is killed by name
function tkillother {
    if (-not (_in_psmux)) { Write-Error 'tkillother: run it inside a psmux session, it keeps the one it is run from'; return }
    # the session's own name, asked with this pane's variables intact. PSMUX_SESSION is not used: a
    # session made from outside psmux takes over its spare server, so the pane keeps that server's
    # name (__warm__) after it becomes main. the session would then close itself
    $current = (psmux display-message -p '#S' 2>$null | Select-Object -First 1)
    if ($current) { $current = $current.Trim() }
    if (-not $current) { Write-Error 'tkillother: could not tell which session this is, so nothing was killed'; return }
    foreach ($name in @(_psmux_out list-sessions -F '#S')) {
        # a session that closed meanwhile is not an error worth showing
        if ($name -and $name -ne $current) { _psmux_out kill-session -t $name 2>$null }
    }
}

# the project layouts below share these helpers, so each layout only says where its panes go.
# _ide_open names the session after the folder, plus the layout's suffix so two layouts of one
# folder can be open at once. it also takes the size the layout will be seen at so the shares come
# out right. it returns nothing when there is no such folder
function _ide_open([string]$Layout, [string]$Suffix, [string]$Path) {
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.PSIsContainer) { Write-Error "${Layout}: there is no folder $Path"; return }
    # tmux reads a dot or a colon in a session name as a separator, so both become dashes
    $s = @{ Dir = $item.FullName; Name = ($item.Name -replace '[^A-Za-z0-9_-]', '-') + $Suffix }
    $s.Pane = "=$($s.Name):"
    _psmux_out has-session -t "=$($s.Name)" 2>$null
    $s.Open = $LASTEXITCODE -eq 0
    if ($env:TMUX) {
        $s.Width = psmux display-message -p '#{window_width}'
        $s.Height = psmux display-message -p '#{window_height}'
    } else {
        $s.Width = $Host.UI.RawUI.WindowSize.Width
        $s.Height = $Host.UI.RawUI.WindowSize.Height
    }
    $s
}

# psmux numbers pane ids per session rather than per server, so a bare %2 can name a pane in
# another open session. the layouts therefore only ever address the session's active pane
# ($S.Pane): each split makes the new pane the active one, a scene is split off without taking
# the focus and _ide_show moves back to the main pane by direction

# _ide_main: the new session, its first pane active
function _ide_main($S, [string]$Window) {
    _psmux_out new-session -d -s $S.Name -n $Window -c $S.Dir -x $S.Width -y $S.Height
}

# _ide_split: a shell split from the active pane (-v below, -h beside), which becomes the active one
function _ide_split($S, [string]$Direction, [string]$Share) {
    _psmux_out split-window $Direction -l $Share -t $S.Pane -c $S.Dir
}

# _ide_send: a command line typed into the active pane, so the pane stays a shell when it ends
function _ide_send($S, [string]$Line) {
    _psmux_out send-keys -t $S.Pane $Line Enter
}

# _ide_scene: a Zacess scene split off the active pane without taking the focus, following the
# shells in this session. left out when Zacess Scenes is not installed. zsf hands the scene the zt
# theme; the shells' follow hook takes its channel from the session name, so the scene gets the same
function _ide_scene($S, [string]$Direction, [string]$Share) {
    if (Get-Command zacess-scenes -ErrorAction SilentlyContinue) {
        _psmux_out split-window $Direction -l $Share -d -t $S.Pane -c $S.Dir "pwsh -NoLogo -Command zsf --channel $($S.Name)"
    }
}

# _ide_repo: whether lazygit is installed and the folder is a git repository
function _ide_repo($S) {
    (Get-Command lazygit -ErrorAction SilentlyContinue) -and ((git -C $S.Dir rev-parse --is-inside-work-tree 2>$null) -eq 'true')
}

# _ide_git: a second window running lazygit when _ide_repo allows it. Ctrl+B then 2 (or Ctrl+B
# then n) goes to it
function _ide_git($S) {
    if (_ide_repo $S) {
        _psmux_out new-window -d -t "=$($S.Name):" -n git -c $S.Dir
        _psmux_out send-keys -t "=$($S.Name):git" lazygit Enter
    }
}

# _ide_show: the focus moves to the layout's main pane (-U up, -L left), then the session opens,
# switched to from inside psmux and attached from outside it
function _ide_show($S, [string]$Back) {
    if ($Back) { _psmux_out select-pane -t $S.Pane $Back }
    if ($env:TMUX) { psmux switch-client -t "=$($S.Name)" } else { psmux attach-session -t "=$($S.Name)" }
}

# ide: the same layout as ide on macOS and Linux, in psmux. a session named after the folder with
# nvim on top, a shell below, a follow scene beside the shell and lazygit in a second window when
# the folder is a git repo. running it again goes back to the session rather than building another
function ide {
    param([string]$Path = '.')
    $s = _ide_open 'ide' '' $Path; if (-not $s) { return }; if ($s.Open) { return _ide_show $s }
    _ide_main $s 'editor'
    _ide_send $s 'nvim .'
    _ide_split $s '-v' '30%'
    _ide_scene $s '-h' '35%'
    _ide_git $s
    _ide_show $s '-U'
}

# idev: web development. nvim on top (65 percent) over a row of a shell, the dev server's logs and
# a scene, plus the lazygit window. the logs pane runs npm run dev when package.json has a dev
# script, php artisan serve in a Laravel project and is a plain shell otherwise
function idev {
    param([string]$Path = '.')
    $s = _ide_open 'idev' '-dev' $Path; if (-not $s) { return }; if ($s.Open) { return _ide_show $s }
    _ide_main $s 'editor'
    _ide_send $s 'nvim .'
    _ide_split $s '-v' '35%'
    # the bottom row is shell 35, logs 40 and scene 25 percent: logs takes 65 percent of the row,
    # then the scene takes 38 percent of that
    _ide_split $s '-h' '65%'
    _ide_scene $s '-h' '38%'
    $scripts = _ide_scripts $s
    if ($scripts.dev) {
        _ide_send $s 'npm run dev'
    } elseif (Test-Path -LiteralPath (Join-Path $s.Dir 'artisan')) {
        _ide_send $s 'php artisan serve'
    }
    _ide_git $s
    _ide_show $s '-U'
}

# _ide_scripts: package.json's scripts and the names of its packages, empty without one
function _ide_scripts($S) {
    $package = Join-Path $S.Dir 'package.json'
    $found = @{ dev = $null; test = $null; packages = @() }
    if (-not (Test-Path -LiteralPath $package)) { return $found }
    try { $json = Get-Content -LiteralPath $package -Raw | ConvertFrom-Json } catch { return $found }
    $found.dev = $json.scripts.dev
    $found.test = $json.scripts.test
    foreach ($group in $json.dependencies, $json.devDependencies) { if ($group) { $found.packages += $group.PSObject.Properties.Name } }
    $found
}

# imon: system monitor. btop4win (or btop) on the left 65 percent, with docker ps refreshing every
# five seconds above a scene on the right. each is a plain shell when its tool is not installed
function imon {
    param([string]$Path = '.')
    $s = _ide_open 'imon' '-mon' $Path; if (-not $s) { return }; if ($s.Open) { return _ide_show $s }
    _ide_main $s 'monitor'
    $top = Get-Command btop4win, btop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($top) { _ide_send $s $top.Name }
    _ide_split $s '-h' '35%'
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        # a stopped daemon gets one short line rather than a repeated connection error, checked again
        # every five seconds
        _ide_send $s 'while ($true) { Clear-Host; docker ps 2>$null; if ($LASTEXITCODE) { ''Docker is not running'' }; Start-Sleep 5 }'
    }
    _ide_scene $s '-v' '50%'
    _ide_show $s '-L'
}

# ilab: embedded and lab work. nvim on top (65 percent) over a row of a build shell ready for make
# or avr-gcc, a serial monitor shell and a scene. nothing runs by itself in the bottom row, since
# the build and the serial port differ per board
function ilab {
    param([string]$Path = '.')
    $s = _ide_open 'ilab' '-lab' $Path; if (-not $s) { return }; if ($s.Open) { return _ide_show $s }
    _ide_main $s 'editor'
    _ide_send $s 'nvim .'
    _ide_split $s '-v' '35%'
    # build 40, serial 35 and scene 25 percent of the row
    _ide_split $s '-h' '60%'
    _ide_scene $s '-h' '42%'
    _ide_show $s '-U'
}

# ilog: two shells side by side for following logs, with a small scene bottom right. nothing tails
# by itself, since the log files differ per project
function ilog {
    param([string]$Path = '.')
    $s = _ide_open 'ilog' '-log' $Path; if (-not $s) { return }; if ($s.Open) { return _ide_show $s }
    _ide_main $s 'logs'
    _ide_split $s '-h' '50%'
    _ide_scene $s '-v' '30%'
    _ide_show $s '-L'
}

# iplay: Zacess Games large on the left (a shell when it is not installed), a scene beside it
function iplay {
    param([string]$Path = '.')
    $s = _ide_open 'iplay' '-play' $Path; if (-not $s) { return }; if ($s.Open) { return _ide_show $s }
    _ide_main $s 'play'
    if (Get-Command zacess-games -ErrorAction SilentlyContinue) { _ide_send $s 'zg' }
    _ide_scene $s '-h' '35%'
    _ide_show $s
}

# ireview: reviewing pull requests. nvim on top (65 percent) over a row of gh pr status refreshing
# every minute, lazygit and a scene. without gh that pane is a plain shell; lazygit is left out
# when it is not installed or the folder is not a git repository
function ireview {
    param([string]$Path = '.')
    $s = _ide_open 'ireview' '-review' $Path; if (-not $s) { return }; if ($s.Open) { return _ide_show $s }
    _ide_main $s 'editor'
    _ide_send $s 'nvim .'
    _ide_split $s '-v' '35%'
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        _ide_send $s 'while ($true) { Clear-Host; gh pr status; Start-Sleep 60 }'
    }
    if (_ide_repo $s) {
        # gh 40, lazygit 35 and scene 25 percent of the row
        _ide_split $s '-h' '60%'
        _ide_send $s 'lazygit'
        _ide_scene $s '-h' '42%'
    } else {
        _ide_scene $s '-h' '25%'
    }
    _ide_show $s '-U'
}

# itest: testing. nvim on top (65 percent) over a row of a test watcher, a shell and a scene, plus
# the lazygit window. the watcher runs the first that fits: the package.json test script (vitest
# when the project uses it), php artisan test, pytest (pytest -f with pytest-xdist), cargo watch
# when cargo-watch is installed. Otherwise it is a plain shell
function itest {
    param([string]$Path = '.')
    $s = _ide_open 'itest' '-test' $Path; if (-not $s) { return }; if ($s.Open) { return _ide_show $s }
    _ide_main $s 'editor'
    _ide_send $s 'nvim .'
    _ide_split $s '-v' '35%'
    $watch = _ide_watcher $s
    if ($watch) { _ide_send $s $watch }
    # watcher 45, shell 30 and scene 25 percent of the row: the shell and scene take 55 percent,
    # then the scene takes 45 percent of that
    _ide_split $s '-h' '55%'
    _ide_scene $s '-h' '45%'
    _ide_git $s
    _ide_show $s '-U'
}

# _ide_watcher: the test command itest runs for the folder, nothing when no runner fits
function _ide_watcher($S) {
    $scripts = _ide_scripts $S
    if ($scripts.test) {
        if ($scripts.packages -contains 'vitest') { return 'npx vitest' }
        return 'npm test -- --watch'
    }
    if (Test-Path -LiteralPath (Join-Path $S.Dir 'artisan')) { return 'php artisan test' }
    $python = 'pytest.ini', 'conftest.py', 'tests' | Where-Object { Test-Path -LiteralPath (Join-Path $S.Dir $_) }
    $pyproject = Join-Path $S.Dir 'pyproject.toml'
    if (-not $python -and (Test-Path -LiteralPath $pyproject)) { $python = Select-String -LiteralPath $pyproject -Pattern '\[tool\.pytest' -Quiet }
    if ($python -and (Get-Command pytest -ErrorAction SilentlyContinue)) {
        # a real module of pytest-xdist, since an uninstall can leave an empty xdist folder that imports
        python -c 'import xdist.plugin' 2>$null
        if ($LASTEXITCODE -eq 0) { return 'pytest -f' }
        return 'pytest'
    }
    if ((Test-Path -LiteralPath (Join-Path $S.Dir 'Cargo.toml')) -and (Get-Command cargo-watch -ErrorAction SilentlyContinue)) { return 'cargo watch -x test' }
}

# ide-pick: the folders in each IDE_ROOTS folder (separated by ';', the repos folder by default),
# the one picked opens in ide. outside psmux the list is fzf, filtered as you type. inside psmux on
# Windows a real keyboard reached fzf as plain letters (Enter as m, Ctrl+C as c, mouse reports as
# text), so there the list is numbered and read with Read-Host, which needs only typing and Enter
function ide-pick {
    $roots = if ($env:IDE_ROOTS) { $env:IDE_ROOTS -split [IO.Path]::PathSeparator } else { @(Join-Path $HOME 'dev\github\repos') }
    $folders = @($roots | Where-Object { Test-Path -LiteralPath $_ } |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Directory | Where-Object Name -notlike '.*' | ForEach-Object FullName } |
        Sort-Object)
    if (-not $folders) { Write-Error 'ide-pick: no project folders found'; return }
    Clear-Host
    $pick = if (_in_psmux) { _ide_choose $folders } else { $folders | fzf --prompt 'project> ' --reverse }
    if ($pick) { ide $pick }
}

# _ide_choose: a numbered list of folders. a number opens that one, part of a name narrows the list
# (or opens the only match) and an empty answer cancels
function _ide_choose([string[]]$Folders) {
    $shown = $Folders
    while ($true) {
        Clear-Host
        # written to the screen, not returned, so only the folder picked comes back
        for ($i = 0; $i -lt $shown.Count; $i++) { Write-Host ('{0,3}  {1}' -f ($i + 1), (Split-Path $shown[$i] -Leaf)) }
        Write-Host ''
        $answer = (Read-Host 'Project number or part of a name (Enter on its own cancels)').Trim()
        if (-not $answer) { return }
        if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $shown.Count) { return $shown[[int]$answer - 1] }
        $found = @($Folders | Where-Object { (Split-Path $_ -Leaf) -like "*$answer*" })
        if ($found.Count -eq 1) { return $found[0] }
        $shown = if ($found.Count) { $found } else { $Folders }
    }
}

# cluster: open 4 Windows Terminal panes connected to cluster nodes
function cluster {
    wt `
        --window 0 new-tab --title "node1" -- ssh node1 `; `
        split-pane --title "node2" -- ssh node2 `; `
        split-pane --title "node3" -- ssh node3 `; `
        split-pane --title "node4" -- ssh node4
}
