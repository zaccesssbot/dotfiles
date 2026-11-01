# zt: switch every installed editor and terminal to one Zacess theme at once (Windows).
#
#   zt <theme>                 fix that theme everywhere and stop following the system
#   zt auto [dark] [light]     follow the Windows light and dark setting, Deep Contrast by default
#   zt list                    the eight themes and their short names
#   zt current                 the mode zt last set and what each tool is on now
#   zt doctor                  every installed theme file against the repo copy, exit 1 on drift
#   zt <theme> --all           the same here, then on every other device as a terminal opens there
#   zt undo [--all]            back to the theme before the last change (on every device with --all)
#   zt sync                    apply a change sent with --all from another device (run at shell start)
#   zt highlight [default]     the Windows text highlight again from the theme or Windows' own back
#   zt pin <app> <theme>       keep one app on its own theme while the rest follow zt; the theme can
#                              also be auto [dark] [light] or the app's own: default, default-dark or
#                              default-light. "terminals" as the app pins every terminal app at once
#   zt unpin <app|terminals|--all>  the app follows zt again, switched to the zt state straight away
#   zt current terminals       what each terminal app is on, with any pins (termtheme shows this)
#
# each tool is edited in place and only for its theme setting; a tool that is not installed is
# skipped. the JetBrains IDEs, Eclipse, STM32CubeIDE and the apps with their own apply script
# (Arduino IDE, Notepad++, Thonny, LTspice, Proteus, Zotero, Obsidian, MATLAB, KiCad, Vivado,
# Processing and Microchip Studio) are only changed while they are closed, since they write their
# settings back on exit. MATLAB and Microchip Studio are never started: their theme is left for
# their next start (a startup.m block and Studio's team settings file). the Windows text highlight (Hilight and HilightText under Control Panel\Colors)
# takes the theme's selection colour from the generated Windows Terminal scheme and applies at the
# next sign in. scripts/zt.py is the macOS and Linux version; both keep the same state file
# format, which Neovim reads. They share the pins file beside it too. zt.cmd and zacess-theme.cmd run
# this from Command Prompt.

$ErrorActionPreference = 'Stop'

$Themes = @(
    @{ Id = 'deep-contrast-dark'; Short = 'deep-dark'; Name = 'Zacess Deep Contrast Dark'; Dark = $true }
    @{ Id = 'deep-contrast-light'; Short = 'deep-light'; Name = 'Zacess Deep Contrast Light'; Dark = $false }
    @{ Id = 'high-contrast-dark'; Short = 'hc-dark'; Name = 'Zacess High Contrast Dark'; Dark = $true }
    @{ Id = 'high-contrast-light'; Short = 'hc-light'; Name = 'Zacess High Contrast Light'; Dark = $false }
    @{ Id = 'dark'; Short = 'dark'; Name = 'Zacess Dark'; Dark = $true }
    @{ Id = 'light'; Short = 'light'; Name = 'Zacess Light'; Dark = $false }
    @{ Id = 'cream'; Short = 'cream'; Name = 'Zacess Cream'; Dark = $false }
    @{ Id = 'yellow-on-black'; Short = 'yellow'; Name = 'Zacess Yellow on Black'; Dark = $true }
)

$StateFile = Join-Path $env:LOCALAPPDATA 'zacess\theme'
# the theme MATLAB applies at its next start, written by editors\matlab\windows\apply.ps1 -Pending
$MatlabPending = Join-Path $env:LOCALAPPDATA 'zacess\matlab-theme'
# the state before the last change, for zt undo. a second undo swaps back, so it also redoes
$PreviousFile = Join-Path $env:LOCALAPPDATA 'zacess\previous'
# --all: one push at a time in a synced folder, read by every device. all-seen is the last push
# this device handled and all-applied the state it had before applying it, so zt undo --all can
# return each device to its own previous theme
$AllSeen = Join-Path $env:LOCALAPPDATA 'zacess\all-seen'
$AllApplied = Join-Path $env:LOCALAPPDATA 'zacess\all-applied'
$EclipseWorkspace = if ($env:ZT_ECLIPSE_WORKSPACE) { $env:ZT_ECLIPSE_WORKSPACE } else { Join-Path $env:USERPROFILE 'eclipse-workspace' }
# editors\eclipse and editors\stm32cubeide sit beside shell\ in the same clone (shell\windows\scripts\zt.ps1)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$EclipseThemes = if ($env:ZT_ECLIPSE_THEMES) { $env:ZT_ECLIPSE_THEMES } else { Join-Path $RepoRoot 'editors\eclipse\theme' }
$Stm32Themes = if ($env:ZT_STM32_THEMES) { $env:ZT_STM32_THEMES } else { Join-Path $RepoRoot 'editors\stm32cubeide\shared\theme' }

# STM32CubeIDE names its default workspace after its own version, so the newest one it has
# opened is the one in use
function Get-Stm32Workspace {
    if ($env:ZT_STM32_WORKSPACE) { return $env:ZT_STM32_WORKSPACE }
    $root = Join-Path $env:USERPROFILE 'STM32CubeIDE'
    if (-not (Test-Path $root)) { return $null }
    $found = Get-ChildItem -Path $root -Directory -Filter 'workspace_*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName '.metadata') } | Sort-Object LastWriteTime -Descending
    if ($found) { return $found[0].FullName }
    return $null
}

# terminal colour slots rather than fixed colours, so the output reads in every theme
$e = [char]27
$Ok = "$e[32m"; $Skip = "$e[33m"; $Bold = "$e[1m"; $Reset = "$e[0m"
if ($env:NO_COLOR) { $Ok = $Skip = $Bold = $Reset = '' }

function Find-Theme([string]$Word) {
    $key = ($Word.Trim().ToLowerInvariant() -replace ' ', '-') -replace '^zacess-', ''
    $Themes | Where-Object { $_.Id -eq $key -or $_.Short -eq $key } | Select-Object -First 1
}

function Write-Result([string]$Tool, [string]$Message, [bool]$Changed = $true) {
    $colour = if ($Changed) { $Ok } else { $Skip }
    Write-Host ("  {0}{1,-16}{2} {3}{4}{2}" -f $Bold, $Tool, $Reset, $colour, $Message)
}

function Test-SystemDark {
    $value = Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' -ErrorAction SilentlyContinue
    return $value -eq 0
}

# JSON with comments: each value is swapped in the text itself, so comments, key order and spacing
# stay as they were. the result is parsed before it is saved
function Set-JsonKey([string]$Text, [string]$Key, [string]$Rendered) {
    $value = '(?:"(?:[^"\\]|\\.)*"|true|false|null|-?\d+(?:\.\d+)?|\{[^{}]*\})'
    $pattern = '("' + [regex]::Escape($Key) + '"\s*:\s*)' + $value
    if ([regex]::IsMatch($Text, $pattern)) {
        return ([regex]$pattern).Replace($Text, { param($m) $m.Groups[1].Value + $Rendered }, 1)
    }
    $indent = [regex]::Match($Text, '\n([ \t]+)"')
    $pad = if ($indent.Success) { $indent.Groups[1].Value } else { '    ' }
    $brace = $Text.IndexOf('{')
    return $Text.Substring(0, $brace + 1) + "`n$pad`"$Key`": $Rendered," + $Text.Substring($brace + 1)
}

function Edit-Json([string]$Path, [hashtable]$Changes) {
    $text = [IO.File]::ReadAllText($Path)
    $new = $text
    foreach ($key in $Changes.Keys) { $new = Set-JsonKey $new $key $Changes[$key] }
    $null = $new | ConvertFrom-Json
    if ($new -cne $text) { [IO.File]::WriteAllText($Path, $new) }
}

function ConvertTo-JsonValue($Value) {
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    return ($Value | ConvertTo-Json -Compress)
}

function Set-VSCode($Fixed, $Dark, $Light, $Now) {
    $path = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (-not (Test-Path $path)) { return Write-Result 'VS Code' 'not installed, skipped' $false }
    if ($Fixed) {
        Edit-Json $path @{ 'workbench.colorTheme' = (ConvertTo-JsonValue $Fixed.Name); 'window.autoDetectColorScheme' = 'false' }
        return Write-Result 'VS Code' $Fixed.Name
    }
    Edit-Json $path @{
        'workbench.colorTheme' = (ConvertTo-JsonValue $Now.Name); 'window.autoDetectColorScheme' = 'true'
        'workbench.preferredDarkColorTheme' = (ConvertTo-JsonValue $Dark.Name)
        'workbench.preferredLightColorTheme' = (ConvertTo-JsonValue $Light.Name)
    }
    Write-Result 'VS Code' "following the system: $($Dark.Name) or $($Light.Name)"
}

function Set-Zed($Fixed, $Dark, $Light, $Now) {
    $path = Join-Path $env:APPDATA 'Zed\settings.json'
    if (-not (Test-Path $path)) { return Write-Result 'Zed' 'not installed, skipped' $false }
    $mode = if (-not $Fixed) { 'system' } elseif ($Fixed.Dark) { 'dark' } else { 'light' }
    # the settings file is the repo's own copy, so a theme that is already right is left as it is:
    # rewriting it on one line left a change behind that blocked the next git pull
    $current = try { (Get-Content -Raw $path | ConvertFrom-Json).theme } catch { $null }
    $same = $current -and $current.mode -eq $mode -and $current.light -eq $Light.Name -and $current.dark -eq $Dark.Name
    if (-not $same) {
        $entries = @("`"mode`": `"$mode`"", "`"light`": `"$($Light.Name)`"", "`"dark`": `"$($Dark.Name)`"")
        $text = [IO.File]::ReadAllText($path)
        $old = [regex]::Match($text, '"theme"\s*:\s*(\{[^{}]*\})')
        # a block already spread over lines keeps that shape and its trailing comma, as
        # editors\zed\windows\apply.ps1 writes it: one line left the linked repo file changed
        $rendered = if ($old.Success -and $old.Groups[1].Value.Contains("`n")) {
            $lineStart = $text.LastIndexOf("`n", $old.Index) + 1
            $pad = [regex]::Match($text.Substring($lineStart), '^[ \t]*').Value
            $inside = [regex]::Match($old.Groups[1].Value, '\n([ \t]+)\S')
            $step = if ($inside.Success) { $inside.Groups[1].Value } else { $pad + '  ' }
            $trailing = if ($old.Groups[1].Value -match ',\s*}$') { ',' } else { '' }
            $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
            "{$nl" + (($entries | ForEach-Object { "$step$_" }) -join ",$nl") + $trailing + "$nl$pad}"
        } else {
            '{ ' + ($entries -join ', ') + ' }'
        }
        Edit-Json $path @{ 'theme' = $rendered }
    }
    # the theme file comes from the apply script, so a Zacess Themes bump in the repo reaches Zed
    # while its store extension is still older. editing settings.json alone left the old file behind
    $apply = Join-Path $RepoRoot 'editors\zed\windows\apply.ps1'
    if (Test-Path $apply) {
        $global:LASTEXITCODE = 0
        $output = @(& $apply -ThemesOnly 2>&1 | ForEach-Object { "$_" })
        if ($LASTEXITCODE -ne 0) { return Write-Result 'Zed' "theme file not refreshed: $($output | Select-Object -First 1)" $false }
    }
    if ($Fixed) { return Write-Result 'Zed' $Fixed.Name }
    Write-Result 'Zed' "following the system: $($Dark.Name) or $($Light.Name)"
}

function Set-JetBrains($Fixed, $Dark, $Light, $Now) {
    $base = Join-Path $env:APPDATA 'JetBrains'
    $dirs = @(if (Test-Path $base) { Get-ChildItem $base -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'options') } })
    if (-not $dirs) { return Write-Result 'JetBrains' 'not installed, skipped' $false }
    $ides = 'idea64', 'pycharm64', 'webstorm64', 'clion64', 'dataspell64', 'goland64', 'phpstorm64', 'rubymine64', 'rustrover64', 'rider64', 'studio64'
    if (Get-Process -Name $ides -ErrorAction SilentlyContinue) {
        return Write-Result 'JetBrains' 'an IDE is open, skipped: close it and run zt again' $false
    }
    $shown = if ($Fixed) { $Fixed } else { $Now }
    foreach ($dir in $dirs) {
        if (-not (Test-Path (Join-Path $dir.FullName 'plugins\zacess-themes'))) {
            Write-Result "  $($dir.Name)" 'Zacess Themes plugin not installed, skipped' $false
            continue
        }
        $laf = Join-Path $dir.FullName 'options\laf.xml'
        [xml]$doc = if (Test-Path $laf) { Get-Content -Raw $laf } else { '<application />' }
        $comp = $doc.DocumentElement.SelectSingleNode("component[@name='LafManager']")
        if (-not $comp) {
            $comp = $doc.CreateElement('component'); $comp.SetAttribute('name', 'LafManager')
            $null = $doc.DocumentElement.AppendChild($comp)
        }
        foreach ($child in @($comp.ChildNodes)) {
            # a remembered scheme per theme would win over the theme's own scheme
            if ($child.Name -in 'laf', 'lafs-to-previous-schemes' -or (-not $Fixed -and $child.Name -like 'preferred-*')) {
                $null = $comp.RemoveChild($child)
            }
        }
        $comp.SetAttribute('autodetect', $(if ($Fixed) { 'false' } else { 'true' }))
        $node = $doc.CreateElement('laf'); $node.SetAttribute('themeId', "zacess-$($shown.Id)"); $null = $comp.AppendChild($node)
        if (-not $Fixed) {
            $node = $doc.CreateElement('preferred-light-laf'); $node.SetAttribute('themeId', "zacess-$($Light.Id)"); $null = $comp.AppendChild($node)
            $node = $doc.CreateElement('preferred-dark-laf'); $node.SetAttribute('themeId', "zacess-$($Dark.Id)"); $null = $comp.AppendChild($node)
        }
        $doc.Save($laf)
        $schemeFile = Join-Path $dir.FullName 'options\colors.scheme.xml'
        [xml]$doc = if (Test-Path $schemeFile) { Get-Content -Raw $schemeFile } else { '<application />' }
        $comp = $doc.DocumentElement.SelectSingleNode("component[@name='EditorColorsManagerImpl']")
        if (-not $comp) {
            $comp = $doc.CreateElement('component'); $comp.SetAttribute('name', 'EditorColorsManagerImpl')
            $null = $doc.DocumentElement.AppendChild($comp)
        }
        $node = $comp.SelectSingleNode('global_color_scheme')
        if (-not $node) { $node = $doc.CreateElement('global_color_scheme'); $null = $comp.AppendChild($node) }
        $node.SetAttribute('name', $shown.Name)
        $doc.Save($schemeFile)
        $message = if ($Fixed) { $Fixed.Name } else { "Sync with OS: $($Dark.Name) or $($Light.Name)" }
        Write-Result "  $($dir.Name)" $message
    }
}

function Set-Neovim($Fixed, $Dark, $Light, $Now) {
    New-Item -ItemType Directory -Force (Split-Path $StateFile) | Out-Null
    $line = if ($Fixed) { $Fixed.Id } else { "auto $($Dark.Id) $($Light.Id)" }
    [IO.File]::WriteAllText($StateFile, "$line`n")
    if (-not (Get-Command nvim -ErrorAction SilentlyContinue)) { return Write-Result 'Neovim' 'not installed, theme saved for later' $false }
    $message = if ($Fixed) { $Fixed.Name } else { 'following the system' }
    # every running Neovim listens on a named pipe (nvim.<pid>.0), so each is told to run the same
    # apply() its focus autocmd runs, which rereads the state file written above
    $reloaded = 0
    foreach ($pipe in @(Get-ChildItem '\\.\pipe\' -ErrorAction SilentlyContinue | Where-Object Name -like 'nvim.*')) {
        nvim --server "\\.\pipe\$($pipe.Name)" --remote-expr "execute('lua require([[config.theme]]).apply()')" *> $null
        if ($LASTEXITCODE -eq 0) { $reloaded++ }
    }
    $when = if ($reloaded) { "applied to $reloaded open Neovim(s), the rest on start" } else { 'on next focus or start' }
    Write-Result 'Neovim' "$message, $when"
}

function Set-Eclipse($Fixed, $Dark, $Light, $Now) {
    Set-EclipseLike 'Eclipse' $EclipseWorkspace $EclipseThemes 'eclipse' $Fixed $Now
}

function Set-STM32CubeIDE($Fixed, $Dark, $Light, $Now) {
    $workspace = Get-Stm32Workspace
    if (-not $workspace) { return Write-Result 'STM32CubeIDE' 'no workspace, skipped' $false }
    Set-EclipseLike 'STM32CubeIDE' $workspace $Stm32Themes 'stm32cubeide' $Fixed $Now
}

# Eclipse and STM32CubeIDE (built on Eclipse) keep the theme as plain preference files in a
# workspace, written back from memory on exit, so both are changed only while closed
function Set-EclipseLike($Label, $Workspace, $ThemeDir, $ProcessName, $Fixed, $Now) {
    $settings = Join-Path $Workspace '.metadata\.plugins\org.eclipse.core.runtime\.settings'
    if (-not (Test-Path $settings)) { return Write-Result $Label 'no workspace, skipped' $false }
    if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) { return Write-Result $Label 'open, skipped: quit it and run zt again' $false }
    $theme = if ($Fixed) { $Fixed } else { $Now }
    $epf = Join-Path $ThemeDir "$($theme.Name).epf"
    if (-not (Test-Path $epf)) { return Write-Result $Label "no theme files in $ThemeDir, skipped" $false }
    $themeId = if ($theme.Dark) { 'org.eclipse.e4.ui.css.theme.e4_dark' } else { 'org.eclipse.e4.ui.css.theme.e4_default' }
    $fragments = @{ 'org.eclipse.e4.ui.css.swt.theme' = [ordered]@{ themeid = $themeId } }
    foreach ($file in $epf, (Join-Path $ThemeDir "$($theme.Name) borders.epf")) {
        if (-not (Test-Path $file)) { continue }
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if (-not $line.StartsWith('/instance/') -or -not $line.Contains('=')) { continue }
            $rest = $line.Substring(10)
            $slash = $rest.IndexOf('/')
            $plugin = $rest.Substring(0, $slash)
            $pair = $rest.Substring($slash + 1)
            $eq = $pair.IndexOf('=')
            if (-not $fragments.ContainsKey($plugin)) { $fragments[$plugin] = [ordered]@{} }
            $fragments[$plugin][$pair.Substring(0, $eq)] = $pair.Substring($eq + 1)
        }
    }
    foreach ($plugin in $fragments.Keys) {
        $target = Join-Path $settings "$plugin.prefs"
        $lines = if (Test-Path $target) { [IO.File]::ReadAllLines($target) } else { @('eclipse.preferences.version=1') }
        $keys = $fragments[$plugin]
        $done = @{}
        $out = [Collections.Generic.List[string]]::new()
        foreach ($line in $lines) {
            $i = $line.IndexOf('=')
            $key = if ($i -gt 0) { $line.Substring(0, $i) } else { $null }
            if ($key -and $keys.Contains($key)) {
                if (-not $done.ContainsKey($key)) { $out.Add("$key=$($keys[$key])"); $done[$key] = $true }
                continue
            }
            $out.Add($line)
        }
        foreach ($key in $keys.Keys) { if (-not $done.ContainsKey($key)) { $out.Add("$key=$($keys[$key])") } }
        [IO.File]::WriteAllLines($target, $out.ToArray())
    }
    $note = if ($Fixed) { '' } else { " ($Label cannot follow the system, so this matches it now)" }
    Write-Result $Label "$($theme.Name)$note"
}

function Set-WindowsTerminal($Fixed, $Dark, $Light, $Now) {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }
    if (-not $paths) { return Write-Result 'Windows Terminal' 'not installed, skipped' $false }
    foreach ($path in $paths) {
        # the file allows comments, which are dropped here; Windows Terminal writes it the same way itself
        $settings = Get-Content -Raw $path | ConvertFrom-Json
        if (-not $settings.profiles.PSObject.Properties['defaults']) {
            $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $value = if ($Fixed) { $Fixed.Name } else { [pscustomobject]@{ dark = $Dark.Name; light = $Light.Name } }
        $settings.profiles.defaults | Add-Member -Force -NotePropertyName colorScheme -NotePropertyValue $value
        $settings | ConvertTo-Json -Depth 32 | Set-Content -Path $path -Encoding utf8
    }
    $message = if ($Fixed) { $Fixed.Name } else { "following the system: $($Dark.Name) or $($Light.Name)" }
    Write-Result 'Windows Terminal' $message
}

# what a default pin leaves on the emptied import line, so switching back can put the import there
$AlacrittyMark = '# zacess: own colours, zt puts the theme import back here'

function Set-Alacritty($Fixed, $Dark, $Light, $Now) {
    $conf = Join-Path $env:APPDATA 'alacritty\alacritty.toml'
    if (-not (Test-Path $conf)) { return Write-Result 'Alacritty' 'not installed, skipped' $false }
    $theme = if ($Fixed) { $Fixed } else { $Now }
    $text = [IO.File]::ReadAllText($conf)
    if ($text -notmatch 'zacess-[\w-]+\.toml') {
        # a default pin left the marker in place of the import, so the import goes back there
        if (-not $text.Contains($AlacrittyMark)) { return Write-Result 'Alacritty' 'no Zacess import in alacritty.toml, skipped' $false }
        $text = ([regex]('(?m)^import\s*=\s*\[\s*\]\s*' + [regex]::Escape($AlacrittyMark) + '[^\r\n]*')).Replace($text, "import = [`"zacess-$($theme.Id).toml`"]", 1)
    }
    [IO.File]::WriteAllText($conf, ([regex]'zacess-[\w-]+\.toml').Replace($text, "zacess-$($theme.Id).toml", 1))
    $note = if ($Fixed) { '' } else { ' (Alacritty cannot follow the system, so this matches it now)' }
    Write-Result 'Alacritty' "$($theme.Name)$note"
}

# tmux (psmux on Windows): one config for every theme, so the colours that differ come from a
# generated file per theme that terminal\tmux\windows\tmux.conf sources through this link. a link
# rather than a copy, so the file psmux reads is always the repo's own
$TmuxLink = Join-Path $env:LOCALAPPDATA 'zacess\tmux.conf'

function Set-Tmux($Fixed, $Dark, $Light, $Now) {
    $theme = if ($Fixed) { $Fixed } else { $Now }
    $source = Join-Path $RepoRoot "terminal\tmux\windows\themes\zacess-$($theme.Id).conf"
    if (-not (Test-Path $source)) { return Write-Result 'tmux' 'no theme files in terminal\tmux\windows, skipped' $false }
    New-Item -ItemType Directory -Force (Split-Path $TmuxLink) | Out-Null
    if (Test-Path $TmuxLink) { Remove-Item $TmuxLink -Force }
    try {
        New-Item -ItemType SymbolicLink -Path $TmuxLink -Target $source -ErrorAction Stop | Out-Null
    } catch {
        # a file link needs Developer Mode or an elevated shell; a copy still works until the next switch
        Copy-Item $source $TmuxLink
    }
    $note = if ($Fixed) { '' } else { ' (tmux cannot follow the system, so this matches it now)' }
    if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) { return Write-Result 'tmux' "$($theme.Name)$note, psmux not installed, saved for later" $false }
    # psmux keeps a server per session, so the colours are sourced into each open session by name
    # (a plain source-file reaches only one). inside a pane psmux looks a session up only in that
    # pane's own server, so its variables are cleared for these calls and put back after
    $saved = @{}
    foreach ($name in 'TMUX', 'TMUX_PANE', 'PSMUX_SESSION', 'PSMUX_TARGET_SESSION') {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    try {
        $sessions = @(psmux list-sessions -F '#S' 2>$null | Where-Object { $_ })
        foreach ($session in $sessions) { psmux source-file -t "=$session" $TmuxLink *> $null }
    } finally {
        foreach ($name in $saved.Keys) { if ($null -ne $saved[$name]) { Set-Item "Env:$name" $saved[$name] } }
    }
    # tmux.conf sources the same link when a session starts
    $when = if ($sessions.Count) { "applied to the $($sessions.Count) open psmux session(s)" } else { 'at the next start' }
    Write-Result 'tmux' "$($theme.Name)$note, $when"
}

# btop4win: a generated theme per Zacess theme in terminal\btop\themes. btop4win reads btop.conf and
# a themes folder from the folder of the path it was started from, not a config folder. a winget
# portable install keeps the exe under WinGet\Packages and puts a link to it, named btop.exe, in
# WinGet\Links. btop started through that link reads WinGet\Links instead, so both folders get
# the settings: the exe's own folder holds the themes (the shipped ones and the eight Zacess ones,
# linked in) and the link's folder gets a link to that themes folder. each btop.conf has only
# color_theme and theme_background rewritten. Get-BtopDirs returns the exe's folder first
function Get-BtopDirs {
    $command = Get-Command btop4win, btop -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return @() }
    $item = Get-Item -LiteralPath $command.Source
    if (-not $item.LinkType) { return @(Split-Path $item.FullName) }
    $exe = @($item.Target)[0]
    if (-not [IO.Path]::IsPathRooted($exe)) { $exe = Join-Path (Split-Path $item.FullName) $exe }
    @((Split-Path $exe), (Split-Path $item.FullName))
}

function Set-BtopConf([string]$Conf, [string]$ThemeFile) {
    # a list rather than an array, since PowerShell would unwrap a one-line file into a plain string
    $lines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Conf) { $lines.AddRange([IO.File]::ReadAllLines($Conf)) } else { $lines.Add('#? btop config, started by zt for the Zacess theme') }
    foreach ($pair in @(@('color_theme', "`"$ThemeFile`""), @('theme_background', 'True'))) {
        $index = $lines.FindIndex([Predicate[string]] { param($l) $l -match "^$($pair[0])\s*=" })
        if ($index -ge 0) { $lines[$index] = "$($pair[0]) = $($pair[1])" } else { $lines.Add("$($pair[0]) = $($pair[1])") }
    }
    [IO.File]::WriteAllText($Conf, (($lines -join "`n") + "`n"))
}

function Set-Btop($Fixed, $Dark, $Light, $Now) {
    $theme = if ($Fixed) { $Fixed } else { $Now }
    $sourceDir = Join-Path $RepoRoot 'terminal\btop\themes'
    if (-not (Test-Path (Join-Path $sourceDir "zacess-$($theme.Id).theme"))) { return Write-Result 'btop' 'no theme files in terminal\btop, skipped' $false }
    $dirs = @(Get-BtopDirs)
    if (-not $dirs) { return Write-Result 'btop' 'btop4win not installed, skipped' $false }
    $dir = $dirs[0]
    $themes = Join-Path $dir 'themes'
    New-Item -ItemType Directory -Force $themes | Out-Null
    foreach ($source in Get-ChildItem -LiteralPath $sourceDir -Filter 'zacess-*.theme') {
        $link = Join-Path $themes $source.Name
        if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force }
        # a file link needs Developer Mode or an elevated shell; a copy still works until the next switch
        try { New-Item -ItemType SymbolicLink -Path $link -Target $source.FullName -ErrorAction Stop | Out-Null } catch { Copy-Item -LiteralPath $source.FullName $link }
    }
    foreach ($other in $dirs | Select-Object -Skip 1) {
        # the link's folder sees the same themes through a folder link (a junction needs no rights)
        $linked = Join-Path $other 'themes'
        if (-not (Test-Path -LiteralPath $linked)) { New-Item -ItemType Junction -Path $linked -Target $themes | Out-Null }
    }
    foreach ($each in $dirs) { Set-BtopConf (Join-Path $each 'btop.conf') (Join-Path $each "themes\zacess-$($theme.Id).theme") }
    $note = if ($Fixed) { '' } else { ' (btop cannot follow the system, so this matches it now)' }
    # btop4win has no signal or command that rereads its config, so an open one keeps its colours
    $open = if (Get-Process btop4win, btop -ErrorAction SilentlyContinue) { ', reopen btop to apply' } else { ', at its next start' }
    Write-Result 'btop' "$($theme.Name)$note$open"
}

# the apps below have an apply script of their own beside their settings, which finds the app,
# refuses while it is open and changes only its own keys, so zt runs that script. none of them can
# follow the system, so following it sets the theme for the current mode
# the apply script runs in this process rather than a new pwsh, which cost most of a second for
# each app. its exit only ends the script. the reason a script gives on standard error is caught
# by swapping the console's error writer while it runs. in a parallel run ($ZtErrors) the writer
# is one per process, so the run swaps it once for all tools and the reason is printed after
function Invoke-AppScript($Label, $Script, $Fixed, $Now, [string]$Process, [hashtable]$Extra = @{}, [string]$Later) {
    $theme = if ($Fixed) { $Fixed } else { $Now }
    $path = Join-Path $RepoRoot $Script
    if (-not (Test-Path $path)) { return Write-Result $Label "no apply script at $Script, skipped" $false }
    if ($Process -and (Get-Process -Name $Process -ErrorAction SilentlyContinue)) {
        return Write-Result $Label 'open, skipped: quit it and run zt again' $false
    }
    $errors = [IO.StringWriter]::new()
    $console = [Console]::Error
    if (-not $ZtErrors) { [Console]::SetError($errors) }
    try {
        $global:LASTEXITCODE = 0
        $output = @(& $path -Theme $theme.Id @Extra 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } catch {
        $output = @($_.Exception.Message)
        $code = 1
    } finally {
        if (-not $ZtErrors) { [Console]::SetError($console) }
    }
    if ($code -ne 0) {
        $reason = @($errors.ToString() -split "`r?`n") + $output | Where-Object { $_.Trim() } | Select-Object -First 1
        if (-not $reason) { $reason = 'see the message after the list' }
        return Write-Result $Label "skipped: $reason" $false
    }
    # a script whose app is not set up here says so on its first line and exits cleanly
    if ($output.Count -and $output[0] -match 'skipped') { return Write-Result $Label 'not installed, skipped' $false }
    # every apply script prints a line per file or value led by its status (added, changed,
    # unchanged, waiting and so on), so a run is unchanged only when every such line says so
    $statuses = @($output | ForEach-Object { if ($_ -match '^\s+([a-z]+)\s') { $Matches[1] } })
    $same = $statuses.Count -gt 0 -and -not ($statuses | Where-Object { $_ -ne 'unchanged' })
    $note = if ($same) { ', unchanged' } elseif ($Later) { ", $Later" } else { '' }
    if (-not $Fixed) { $note += " ($Label cannot follow the system, so this matches it now)" }
    Write-Result $Label "$($theme.Name)$note" (-not $same)
}

function Set-ArduinoIDE($Fixed, $Dark, $Light, $Now) {
    if (-not (Test-Path (Join-Path $env:USERPROFILE '.arduinoIDE\settings.json'))) { return Write-Result 'Arduino IDE' 'not installed, skipped' $false }
    Invoke-AppScript 'Arduino IDE' 'editors\arduino\windows\apply.ps1' $Fixed $Now 'Arduino IDE'
}

function Set-NotepadPlusPlus($Fixed, $Dark, $Light, $Now) {
    if (-not (Test-Path (Join-Path $env:APPDATA 'Notepad++\config.xml'))) { return Write-Result 'Notepad++' 'not installed, skipped' $false }
    Invoke-AppScript 'Notepad++' 'editors\notepad-plus-plus\windows\apply.ps1' $Fixed $Now 'notepad++'
}

function Set-Thonny($Fixed, $Dark, $Light, $Now) {
    if (-not (Test-Path (Join-Path $env:APPDATA 'Thonny\configuration.ini'))) { return Write-Result 'Thonny' 'not installed, skipped' $false }
    Invoke-AppScript 'Thonny' 'editors\thonny\windows\apply.ps1' $Fixed $Now 'thonny'
}

function Set-LTspice($Fixed, $Dark, $Light, $Now) {
    if (-not (Test-Path (Join-Path $env:APPDATA 'LTspice.ini')) -and -not (Test-Path (Join-Path $env:APPDATA 'LTspiceXVII.ini'))) { return Write-Result 'LTspice' 'not installed, skipped' $false }
    Invoke-AppScript 'LTspice' 'editors\ltspice\windows\apply.ps1' $Fixed $Now 'LTspice'
}

function Set-Proteus($Fixed, $Dark, $Light, $Now) {
    if (-not (Test-Path 'HKCU:\Software\Labcenter Electronics\Proteus 8 Professional\ARES')) { return Write-Result 'Proteus' 'not installed, skipped' $false }
    Invoke-AppScript 'Proteus' 'editors\proteus\windows\apply.ps1' $Fixed $Now 'PDS'
}

function Set-Zotero($Fixed, $Dark, $Light, $Now) {
    if (-not (Test-Path (Join-Path $env:APPDATA 'Zotero\Zotero\Profiles'))) { return Write-Result 'Zotero' 'not installed, skipped' $false }
    Invoke-AppScript 'Zotero' 'apps\zotero\windows\apply.ps1' $Fixed $Now 'zotero'
}

# a vault can live anywhere, so it is named once in OBSIDIAN_VAULT, which the apply script reads too.
# a synced vault carries its theme settings to every machine, so each machine's zt changes the same files
function Set-Obsidian($Fixed, $Dark, $Light, $Now) {
    if (-not (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe'))) { return Write-Result 'Obsidian' 'not installed, skipped' $false }
    if (-not $env:OBSIDIAN_VAULT) { return Write-Result 'Obsidian' 'no vault named in OBSIDIAN_VAULT, skipped' $false }
    Invoke-AppScript 'Obsidian' 'apps\obsidian\windows\apply.ps1' $Fixed $Now 'Obsidian'
}

# MATLAB applies settings only through a running session, so the theme is left in $MatlabPending
# for the startup.m block the apply script adds. MATLAB is never started here. nothing is left
# when its saved settings already hold the theme and its desktop
function Set-MATLAB($Fixed, $Dark, $Light, $Now) {
    if (-not (Get-ChildItem 'C:\Program Files\MATLAB' -Filter 'R20*' -Directory -ErrorAction SilentlyContinue)) { return Write-Result 'MATLAB' 'not installed, skipped' $false }
    $theme = if ($Fixed) { $Fixed } else { $Now }
    $current = Get-CurrentMATLAB
    $file = Join-Path $RepoRoot "editors\matlab\shared\themes\$($theme.Name).json"
    $desktop = if (Test-Path $file) { (Get-Content -Raw $file | ConvertFrom-Json).settings.'matlab.appearance.MATLABTheme' }
    if ($current -and $current.Theme -and $current.Theme.Id -eq $theme.Id -and $current.Mode -eq $desktop) {
        # a theme still waiting from an earlier switch would undo this one at the next start
        Remove-Item $MatlabPending -Force -ErrorAction SilentlyContinue
        return Write-Result 'MATLAB' "$($theme.Name), unchanged" $false
    }
    Invoke-AppScript 'MATLAB' 'editors\matlab\windows\apply.ps1' $Fixed $Now '' @{ Pending = $true } 'on next start'
}

# Microchip Studio only imports colours through a running Studio, so the theme's .vssettings
# becomes its team settings file, which Studio imports by itself at its next start. Studio is
# never started here, but it is skipped while open since it writes its profile back on exit
function Set-MicrochipStudio($Fixed, $Dark, $Light, $Now) {
    if (-not (Test-Path 'C:\Program Files (x86)\Atmel\Studio\7.0\AtmelStudio.exe')) { return Write-Result 'Microchip Studio' 'not installed, skipped' $false }
    Invoke-AppScript 'Microchip Studio' 'editors\microchip-studio\windows\apply.ps1' $Fixed $Now 'AtmelStudio' @{ Pending = $true } 'on next start'
}

function Set-KiCad($Fixed, $Dark, $Light, $Now) { Invoke-AppScript 'KiCad' 'editors\kicad\windows\apply.ps1' $Fixed $Now 'kicad' }
function Set-Vivado($Fixed, $Dark, $Light, $Now) { Invoke-AppScript 'Vivado' 'editors\vivado\windows\apply.ps1' $Fixed $Now 'vivado' }
function Set-Processing($Fixed, $Dark, $Light, $Now) { Invoke-AppScript 'Processing' 'editors\processing\windows\apply.ps1' $Fixed $Now 'Processing' }

# ---------------------------------------------------------------------------------------------------
# pins: one app kept on its own theme while every other app follows zt. The pins file sits beside the
# state file, one app per line followed by its value: a Zacess theme id, "auto <dark id> <light id>"
# to follow the system on its own or the app's own built-in theme as "default" (following the
# system where the app can), "default-dark" or "default-light". A switch, an undo and a sync run each
# pinned app with its pin instead of the zt state, so a pin holds until zt unpin. scripts/zt.py
# keeps the same format
# ---------------------------------------------------------------------------------------------------

$PinsFile = Join-Path $env:LOCALAPPDATA 'zacess\pins'
$DefaultValues = @('default', 'default-dark', 'default-light')
$VSCodeDefaults = @{ dark = 'Default Dark Modern'; light = 'Default Light Modern' }
$ZedDefaults = @{ dark = 'One Dark'; light = 'One Light' }
# the schemes Windows Terminal ships with: Campbell is its own default, One Half Light its light one
$TerminalDefaults = @{ dark = 'Campbell'; light = 'One Half Light' }

# every app a pin can name: the tools that switch it, other names for it and the default values it
# supports. An app with none can still be pinned to a Zacess theme or auto
$PinApps = [ordered]@{
    'vscode' = @{ Tools = @('Set-VSCode'); Aliases = @('code', 'vs-code', 'visual-studio-code'); Defaults = $DefaultValues }
    'zed' = @{ Tools = @('Set-Zed'); Aliases = @(); Defaults = $DefaultValues }
    'jetbrains' = @{ Tools = @('Set-JetBrains'); Aliases = @('idea', 'intellij', 'pycharm', 'webstorm', 'clion', 'rider'); Defaults = @('default') }
    'neovim' = @{ Tools = @('Set-Neovim'); Aliases = @('nvim', 'vim'); Defaults = $DefaultValues }
    'eclipse' = @{ Tools = @('Set-Eclipse'); Aliases = @(); Defaults = @() }
    'stm32cubeide' = @{ Tools = @('Set-STM32CubeIDE'); Aliases = @('stm32'); Defaults = @() }
    'kicad' = @{ Tools = @('Set-KiCad'); Aliases = @(); Defaults = @() }
    'vivado' = @{ Tools = @('Set-Vivado'); Aliases = @(); Defaults = @() }
    'windows-terminal' = @{ Tools = @('Set-WindowsTerminal'); Aliases = @('wt', 'terminal', 'console'); Defaults = $DefaultValues }
    'alacritty' = @{ Tools = @('Set-Alacritty'); Aliases = @(); Defaults = @('default') }
    'tmux' = @{ Tools = @('Set-Tmux'); Aliases = @('psmux'); Defaults = @() }
    'btop' = @{ Tools = @('Set-Btop'); Aliases = @('btop4win'); Defaults = @() }
    'arduino' = @{ Tools = @('Set-ArduinoIDE'); Aliases = @('arduino-ide'); Defaults = @() }
    'notepad++' = @{ Tools = @('Set-NotepadPlusPlus'); Aliases = @('notepadplusplus', 'npp'); Defaults = @() }
    'thonny' = @{ Tools = @('Set-Thonny'); Aliases = @(); Defaults = @() }
    'ltspice' = @{ Tools = @('Set-LTspice'); Aliases = @(); Defaults = @() }
    'proteus' = @{ Tools = @('Set-Proteus'); Aliases = @(); Defaults = @() }
    'zotero' = @{ Tools = @('Set-Zotero'); Aliases = @(); Defaults = @() }
    'obsidian' = @{ Tools = @('Set-Obsidian'); Aliases = @(); Defaults = @() }
    'matlab' = @{ Tools = @('Set-MATLAB'); Aliases = @(); Defaults = @() }
    'processing' = @{ Tools = @('Set-Processing'); Aliases = @(); Defaults = @() }
    'microchip-studio' = @{ Tools = @('Set-MicrochipStudio'); Aliases = @('microchip'); Defaults = @() }
    'highlight' = @{ Tools = @('Set-Highlight'); Aliases = @('selection'); Defaults = @('default') }
}
# termtheme and zt pin terminals: every terminal app zt switches on Windows
$Terminals = @('windows-terminal', 'alacritty')
$ToolApp = @{}
foreach ($app in $PinApps.Keys) { foreach ($tool in $PinApps[$app].Tools) { $ToolApp[$tool] = $app } }
# the labels zt prints, for zt doctor and zt current to find a pinned app
$LabelApp = @{
    'vs code' = 'vscode'; 'zed' = 'zed'; 'jetbrains' = 'jetbrains'; 'neovim' = 'neovim'; 'eclipse' = 'eclipse'
    'stm32cubeide' = 'stm32cubeide'; 'kicad' = 'kicad'; 'vivado' = 'vivado'; 'windows terminal' = 'windows-terminal'
    'alacritty' = 'alacritty'; 'tmux' = 'tmux'; 'btop' = 'btop'; 'arduino ide' = 'arduino'; 'notepad++' = 'notepad++'; 'thonny' = 'thonny'
    'ltspice' = 'ltspice'; 'proteus' = 'proteus'; 'zotero' = 'zotero'; 'obsidian' = 'obsidian'; 'matlab' = 'matlab'
    'processing' = 'processing'; 'microchip studio' = 'microchip-studio'; 'highlight' = 'highlight'
}

function Find-App([string]$Word) {
    $key = $Word.Trim().ToLowerInvariant()
    foreach ($app in $PinApps.Keys) { if ($key -eq $app -or $PinApps[$app].Aliases -contains $key) { return $app } }
    return $null
}

function Get-LabelApp([string]$Label) {
    $key = $Label.Trim().ToLowerInvariant()
    if ($LabelApp.ContainsKey($key)) { return $LabelApp[$key] }
    # a JetBrains IDE's folder is shown under its own name
    $base = Join-Path $env:APPDATA 'JetBrains'
    if ((Test-Path $base) -and (Get-ChildItem $base -Directory | Where-Object { $_.Name.ToLowerInvariant() -eq $key })) { return 'jetbrains' }
    return $null
}

function Read-Pins {
    $pins = [ordered]@{}
    if (-not [IO.File]::Exists($PinsFile)) { return $pins }
    foreach ($line in [IO.File]::ReadAllLines($PinsFile)) {
        $parts = @($line.Trim() -split '\s+' | Where-Object { $_ })
        if ($parts.Count -ge 2 -and -not $parts[0].StartsWith('#') -and $PinApps.Contains($parts[0])) {
            $pins[$parts[0]] = ($parts[1..($parts.Count - 1)] -join ' ')
        }
    }
    return $pins
}

function Write-Pins($Pins) {
    if (-not $Pins.Count) { if ([IO.File]::Exists($PinsFile)) { Remove-Item $PinsFile }; return }
    $lines = @('# zt pins: an app, then the theme it keeps: a Zacess theme id, auto <dark> <light>,',
        '# default, default-dark or default-light. Written by zt pin and zt unpin')
    $lines += @($Pins.Keys | Sort-Object | ForEach-Object { "$_ $($Pins[$_])" })
    Write-Atomic $PinsFile (($lines -join "`n") + "`n")
}

# a pin's value from the words after the app: a theme, auto with an optional pair or a default.
# returns the value or throws with the reason
function ConvertTo-PinValue([string[]]$Words) {
    if (-not $Words.Count) { throw 'a pin needs a theme, auto, default, default-dark or default-light' }
    $first = $Words[0].ToLowerInvariant()
    if ($first -in $DefaultValues -and $Words.Count -eq 1) { return $first }
    if ($first -eq 'auto') {
        $dark = Find-Theme $(if ($Words.Count -gt 1) { $Words[1] } else { 'deep-contrast-dark' })
        $light = Find-Theme $(if ($Words.Count -gt 2) { $Words[2] } else { 'deep-contrast-light' })
        if (-not $dark -or -not $light -or $Words.Count -gt 3) { throw 'auto takes a dark theme and a light theme. Run zt list for the names' }
        return "auto $($dark.Id) $($light.Id)"
    }
    $theme = Find-Theme ($Words -join ' ')
    if (-not $theme) { throw "unknown theme: $($Words -join ' '). Run zt list for the names" }
    return $theme.Id
}

function Get-PinText([string]$Value) {
    switch ($Value) {
        'default' { return 'its own theme, following the system where it can' }
        'default-dark' { return 'its own dark theme' }
        'default-light' { return 'its own light theme' }
    }
    $parts = $Value -split '\s+'
    if ($parts[0] -eq 'auto') {
        # a hand-edited auto line may leave out the pair, which then means the Deep Contrast pair
        $darkId = if ($parts.Count -gt 1) { $parts[1] } else { 'deep-contrast-dark' }
        $lightId = if ($parts.Count -gt 2) { $parts[2] } else { 'deep-contrast-light' }
        return "following the system: $(Get-ThemeName $darkId) or $(Get-ThemeName $lightId)"
    }
    return Get-ThemeName $parts[0]
}

function Set-VSCodeSettingsDefault([string]$Label, [string]$Path, [string]$Mode) {
    if ($Mode -eq 'default') {
        $now = if (Test-SystemDark) { $VSCodeDefaults.dark } else { $VSCodeDefaults.light }
        Edit-Json $Path @{ 'workbench.colorTheme' = (ConvertTo-JsonValue $now); 'window.autoDetectColorScheme' = 'true'
            'workbench.preferredDarkColorTheme' = (ConvertTo-JsonValue $VSCodeDefaults.dark)
            'workbench.preferredLightColorTheme' = (ConvertTo-JsonValue $VSCodeDefaults.light) }
        return Write-Result $Label "its own theme, following the system: $($VSCodeDefaults.dark) or $($VSCodeDefaults.light)"
    }
    $name = $VSCodeDefaults[$Mode.Split('-')[1]]
    Edit-Json $Path @{ 'workbench.colorTheme' = (ConvertTo-JsonValue $name); 'window.autoDetectColorScheme' = 'false' }
    Write-Result $Label "its own theme, $name"
}

function Set-VSCodeDefault([string]$Mode) {
    $path = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (-not (Test-Path $path)) { return Write-Result 'VS Code' 'not installed, skipped' $false }
    Set-VSCodeSettingsDefault 'VS Code' $path $Mode
}

function Set-ZedDefault([string]$Mode) {
    $path = Join-Path $env:APPDATA 'Zed\settings.json'
    if (-not (Test-Path $path)) { return Write-Result 'Zed' 'not installed, skipped' $false }
    $look = if ($Mode -eq 'default') { 'system' } else { $Mode.Split('-')[1] }
    Edit-Json $path @{ 'theme' = "{ `"mode`": `"$look`", `"light`": `"$($ZedDefaults.light)`", `"dark`": `"$($ZedDefaults.dark)`" }" }
    $text = if ($look -eq 'system') { "following the system: $($ZedDefaults.dark) or $($ZedDefaults.light)" } else { $ZedDefaults[$look] }
    Write-Result 'Zed' "its own theme, $text"
}

function Set-JetBrainsDefault([string]$Mode) {
    $base = Join-Path $env:APPDATA 'JetBrains'
    $dirs = @(if (Test-Path $base) { Get-ChildItem $base -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'options') } })
    if (-not $dirs) { return Write-Result 'JetBrains' 'not installed, skipped' $false }
    $ides = 'idea64', 'pycharm64', 'webstorm64', 'clion64', 'dataspell64', 'goland64', 'phpstorm64', 'rubymine64', 'rustrover64', 'rider64', 'studio64'
    if (Get-Process -Name $ides -ErrorAction SilentlyContinue) {
        return Write-Result 'JetBrains' 'an IDE is open, skipped: close it and run zt again' $false
    }
    foreach ($dir in $dirs) {
        # with no theme named and Sync with OS on, each IDE uses its own light and dark pair
        $laf = Join-Path $dir.FullName 'options\laf.xml'
        if (Test-Path $laf) {
            [xml]$doc = Get-Content -Raw $laf
            $comp = $doc.DocumentElement.SelectSingleNode("component[@name='LafManager']")
            if ($comp) {
                foreach ($child in @($comp.ChildNodes)) {
                    if ($child.Name -in 'laf', 'lafs-to-previous-schemes' -or $child.Name -like 'preferred-*') { $null = $comp.RemoveChild($child) }
                }
                $comp.SetAttribute('autodetect', 'true')
                $doc.Save($laf)
            }
        }
        $schemeFile = Join-Path $dir.FullName 'options\colors.scheme.xml'
        if (Test-Path $schemeFile) {
            [xml]$doc = Get-Content -Raw $schemeFile
            $node = $doc.DocumentElement.SelectSingleNode("component[@name='EditorColorsManagerImpl']/global_color_scheme")
            if ($node) { $null = $node.ParentNode.RemoveChild($node); $doc.Save($schemeFile) }
        }
        Write-Result "  $($dir.Name)" 'its own theme, Sync with OS'
    }
}

function Set-WindowsTerminalDefault([string]$Mode) {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }
    if (-not $paths) { return Write-Result 'Windows Terminal' 'not installed, skipped' $false }
    $value = if ($Mode -eq 'default') { [pscustomobject]@{ dark = $TerminalDefaults.dark; light = $TerminalDefaults.light } } else { $TerminalDefaults[$Mode.Split('-')[1]] }
    foreach ($path in $paths) {
        $settings = Get-Content -Raw $path | ConvertFrom-Json
        if (-not $settings.profiles.PSObject.Properties['defaults']) {
            $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $settings.profiles.defaults | Add-Member -Force -NotePropertyName colorScheme -NotePropertyValue $value
        $settings | ConvertTo-Json -Depth 32 | Set-Content -Path $path -Encoding utf8
    }
    $text = if ($Mode -eq 'default') { "following the system: $($TerminalDefaults.dark) or $($TerminalDefaults.light)" } else { $value }
    Write-Result 'Windows Terminal' "its own schemes, $text"
}

function Set-AlacrittyDefault([string]$Mode) {
    $conf = Join-Path $env:APPDATA 'alacritty\alacritty.toml'
    if (-not (Test-Path $conf)) { return Write-Result 'Alacritty' 'not installed, skipped' $false }
    $text = [IO.File]::ReadAllText($conf)
    if ($text -match 'zacess-[\w-]+\.toml') {
        $text = $text -replace '"[^"]*zacess-[\w-]+\.toml"\s*,?\s*', ''
        $text = ([regex]'(?m)^(import\s*=\s*\[\s*\])[ \t]*$').Replace($text, "`$1 $AlacrittyMark", 1)
        [IO.File]::WriteAllText($conf, $text)
    }
    Write-Result 'Alacritty' 'its own colours'
}

$HighlightDefaulted = Join-Path $env:LOCALAPPDATA 'zacess\highlight.pinned-default'

# restored once when pinned; later switches leave the highlight alone, since restoring again with the
# record gone would put back Windows' own colours over one chosen by hand since
function Set-HighlightDefault([string]$Mode) {
    if (Test-Path $HighlightDefaulted) { return Write-Result 'Highlight' 'its own, left as it is' $false }
    Restore-Highlight
    Write-Atomic $HighlightDefaulted "1`n"
}

# the function that sets each tool's own theme
$DefaultHandlers = @{
    'Set-VSCode' = 'Set-VSCodeDefault'; 'Set-Zed' = 'Set-ZedDefault'
    'Set-JetBrains' = 'Set-JetBrainsDefault'; 'Set-WindowsTerminal' = 'Set-WindowsTerminalDefault'
    'Set-Alacritty' = 'Set-AlacrittyDefault'; 'Set-Highlight' = 'Set-HighlightDefault'
}

# runs one tool with its app's pin rather than the zt state
function Invoke-Pin([string]$Tool, [string]$Value) {
    if ($Value -in $DefaultValues) {
        if ($DefaultHandlers.ContainsKey($Tool)) { & $DefaultHandlers[$Tool] $Value }
        return
    }
    $pinPair = ConvertFrom-StateText $Value
    & $Tool $pinPair.Fixed $pinPair.Dark $pinPair.Light $pinPair.Now
}

function Show-Pins($Only) {
    $pins = Read-Pins
    $shown = @($pins.Keys | Where-Object { -not $Only -or $Only -contains $_ })
    if ($shown.Count) {
        # apps sharing a value, as termtheme leaves every terminal, are named together
        $groups = [ordered]@{}
        foreach ($app in ($shown | Sort-Object)) { $groups[$pins[$app]] = @($groups[$pins[$app]]) + $app | Where-Object { $_ } }
        Write-Host ("${Bold}Pinned${Reset}: " + (($groups.Keys | ForEach-Object { "$($groups[$_] -join ', ') on $(Get-PinText $_)" }) -join '; '))
    } elseif (-not $Only) {
        Write-Host 'Pinned: nothing, every app follows zt'
    }
}

function Get-ThemeName([string]$Id) {
    if (-not $Id) { return 'not set' }
    $theme = Find-Theme ($Id -replace '^zacess-', '')
    if ($theme) { return $theme.Name }
    return $Id
}

function Read-Prefs([string]$Path) {
    $map = @{}
    if (Test-Path $Path) {
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $map[$line.Substring(0, $i)] = $line.Substring($i + 1) }
        }
    }
    return $map
}

# each reader adds what a tool is on now, in the same words zt prints when it sets it
$script:Current = [Collections.Generic.List[object]]::new()
function Add-Current([string]$Tool, [string]$Text) { $script:Current.Add([pscustomobject]@{ Tool = $Tool; Text = $Text }) }

function Get-CurrentEclipse {
    return Get-CurrentEclipseLike $EclipseWorkspace $EclipseThemes
}

function Get-CurrentSTM32CubeIDE {
    $workspace = Get-Stm32Workspace
    if (-not $workspace) { return $null }
    return Get-CurrentEclipseLike $workspace $Stm32Themes
}

function Get-CurrentEclipseLike($Workspace, $ThemeDir) {
    $settings = Join-Path $Workspace '.metadata\.plugins\org.eclipse.core.runtime\.settings'
    if (-not (Test-Path $settings)) { return $null }
    # Eclipse keeps no theme name, so the editor colours are compared with each theme's file
    $best = $null; $bestScore = 0.0; $cache = @{}; $found = $false
    foreach ($theme in $Themes) {
        $epf = Join-Path $ThemeDir "$($theme.Name).epf"
        if (-not (Test-Path $epf)) { continue }
        $found = $true
        $total = 0; $hits = 0
        foreach ($line in [IO.File]::ReadAllLines($epf)) {
            if (-not $line.StartsWith('/instance/') -or -not $line.Contains('=')) { continue }
            $rest = $line.Substring(10)
            $slash = $rest.IndexOf('/')
            $plugin = $rest.Substring(0, $slash)
            $pair = $rest.Substring($slash + 1)
            $eq = $pair.IndexOf('=')
            if (-not $cache.ContainsKey($plugin)) { $cache[$plugin] = Read-Prefs (Join-Path $settings "$plugin.prefs") }
            $total++
            if ($cache[$plugin][$pair.Substring(0, $eq)] -ceq $pair.Substring($eq + 1)) { $hits++ }
        }
        $score = if ($total) { $hits / $total } else { 0 }
        if ($score -gt $bestScore) { $best = $theme; $bestScore = $score }
    }
    if (-not $found) { return 'no Zacess theme files to compare with' }
    if (-not $best) { return 'not a Zacess theme' }
    $workbench = (Read-Prefs (Join-Path $settings 'org.eclipse.e4.ui.css.swt.theme.prefs'))['themeid']
    $look = if ("$workbench".EndsWith('e4_dark')) { 'Dark' } else { 'Light' }
    if ($bestScore -eq 1) { return "fixed: $($best.Name), $look workbench" }
    return "not a Zacess theme (closest $($best.Name), $([math]::Round($bestScore * 100))% of its colours), $look workbench"
}

function Get-NewestVersionFolder([string]$Base, [string]$Pattern) {
    if (-not (Test-Path $Base)) { return $null }
    $found = Get-ChildItem $Base -Directory | Where-Object { $_.Name -match $Pattern } | Sort-Object { [version]($_.Name -replace '[^\d.]', '') } | Select-Object -Last 1
    if ($found) { return $found.FullName }
    return $null
}

function Get-CurrentKiCad {
    $base = if ($env:KICAD_CONFIG_HOME) { $env:KICAD_CONFIG_HOME } else { Join-Path $env:APPDATA 'kicad' }
    $config = Get-NewestVersionFolder $base '^\d+\.\d+$'
    $file = if ($config) { Join-Path $config 'eeschema.json' }
    if (-not $file -or -not (Test-Path $file)) { return $null }
    $value = (Get-Content -Raw $file | ConvertFrom-Json).appearance.color_theme
    if (-not $value) { return 'fixed: KiCad default' }
    if ($value -like 'zacess-*') { return "fixed: $(Get-ThemeName $value)" }
    return "fixed: $value"
}

# Vivado keeps no theme name, so its colours are compared with each theme's file
function Get-CurrentVivado {
    $config = Get-NewestVersionFolder (Join-Path $env:APPDATA 'Xilinx\Vivado') '^20\d\d\.\d+'
    $file = if ($config) { Join-Path $config 'vivado.xml' }
    if (-not $file -or -not (Test-Path $file)) { return $null }
    $colours = ([xml](Get-Content -Raw $file)).DocumentElement.SelectSingleNode('general_color')
    foreach ($theme in $Themes) {
        $path = Join-Path $RepoRoot "editors\vivado\shared\themes\zacess-$($theme.Id).json"
        if (-not (Test-Path $path)) { continue }
        $wanted = (Get-Content -Raw $path | ConvertFrom-Json).general_color
        $match = $null -ne $colours
        foreach ($property in $wanted.PSObject.Properties) {
            $node = if ($colours) { $colours.SelectSingleNode($property.Name) }
            if ($null -eq $node -or $node.GetAttribute('color') -ne $property.Value) { $match = $false; break }
        }
        if ($match) { return "fixed: $($theme.Name)" }
    }
    return 'not a Zacess theme'
}

# the Zacess theme MATLAB is on, matched by its keyword colour (each theme's is different), with
# its Dark or Light desktop. $null when MATLAB has never saved settings
function Get-CurrentMATLAB {
    $mlsettings = Get-ChildItem (Join-Path $env:APPDATA 'MathWorks\MATLAB') -Directory -Filter 'R20*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'matlab.mlsettings' } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $mlsettings) { return $null }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($mlsettings)
    try {
        $read = { param($entry) $e = $zip.Entries | Where-Object FullName -eq $entry; if ($e) { $r = New-Object IO.StreamReader($e.Open()); try { $r.ReadToEnd() } finally { $r.Close() } } }
        # MATLAB writes a value as {"mwdata":[...]} and the Color Theme Extensions add-on as a plain
        # string or array, so both forms are read
        $mode = [regex]::Match("$(& $read 'fsroot/settingstree/matlab/appearance/settings.json')", 'MATLABTheme","value":"(?:\{\\"mwdata\\":\[)?\\"(Dark|Light)\\"').Groups[1].Value
        $keyword = [regex]::Match("$(& $read 'fsroot/settingstree/matlab/colors/settings.json')", 'KeywordColor","value":"(?:\{\\"mwdata\\":)?\[(\d+),(\d+),(\d+)')
    } finally { $zip.Dispose() }
    $match = if ($keyword.Success) {
        $Themes | Where-Object {
            $file = Join-Path $RepoRoot "editors\matlab\shared\themes\$($_.Name).json"
            (Test-Path $file) -and ((Get-Content -Raw $file | ConvertFrom-Json).settings.'matlab.colors.KeywordColor' -join ',') -eq "$($keyword.Groups[1].Value),$($keyword.Groups[2].Value),$($keyword.Groups[3].Value)"
        } | Select-Object -First 1
    }
    $pending = if (Test-Path $MatlabPending) { ([IO.File]::ReadAllText($MatlabPending)).Trim() }
    return @{ Theme = $match; Mode = $mode; Pending = $pending }
}

# Microchip Studio keeps imported colours in its own binary store, so only its dark or light
# environment theme can be read back. the team settings file names the Zacess theme. its stored
# time says whether Studio has imported it yet
function Get-CurrentMicrochipStudio {
    $key = 'HKCU:\Software\Atmel\AtmelStudio\7.0\ApplicationPrivateSettings\Microsoft\VisualStudio'
    $value = "$((Get-ItemProperty -Path $key -Name ColorTheme -ErrorAction SilentlyContinue).ColorTheme)"
    $environment = if ($value -match '1ded0138-47ce-435e-84ef-9ec1f439b749') { 'dark' } elseif ($value -match 'de3dbbcd-f642-433c-8353-8f1df4370aba') { 'light' }
    $team = Get-ItemProperty -Path 'HKCU:\Software\Atmel\AtmelStudio\7.0\Profile' -ErrorAction SilentlyContinue
    if ($team -and $team.TrackTeamSettings -eq 1 -and $team.TeamSettingsFile -and (Test-Path $team.TeamSettingsFile)) {
        $name = [IO.Path]::GetFileNameWithoutExtension($team.TeamSettingsFile)
        $stored = ([int64][uint32]$team.TeamSettingsFILETIMEHigh -shl 32) -bor [int64][uint32]$team.TeamSettingsFILETIMELow
        if ($stored -ne (Get-Item $team.TeamSettingsFile).LastWriteTimeUtc.ToFileTimeUtc()) { return "fixed: $name, on next start" }
        return "fixed: $name, $environment environment theme"
    }
    if (-not $value) { return $null }
    if ($environment) { return "$environment environment theme (the Zacess theme itself is not recorded)" }
    return 'not a Zacess environment theme'
}

# the theme Processing uses is the theme.txt in its sketchbook, which names itself on its first line
function Get-CurrentProcessing {
    $prefs = Read-Prefs (Join-Path $env:APPDATA 'Processing\preferences.txt')
    $sketchbook = $prefs['sketchbook.path.four']
    if (-not $sketchbook) { return $null }
    $file = Join-Path $sketchbook 'theme.txt'
    if (-not (Test-Path $file)) { return "fixed: $(if ($prefs['theme']) { $prefs['theme'] } else { 'default' })" }
    $first = [IO.File]::ReadLines($file) | Select-Object -First 1
    if ($first -match '^# Zacess theme for Processing: (.+)$') { return "fixed: $($Matches[1])" }
    return 'fixed: a theme.txt that is not a Zacess theme'
}

function Get-StateText {
    $state = @(if (Test-Path $StateFile) { ([IO.File]::ReadAllText($StateFile)).Trim() -split '\s+' } else { @('deep-contrast-dark') })
    if ($state[0] -eq 'auto') {
        $dark = if ($state.Count -gt 1) { $state[1] } else { 'deep-contrast-dark' }
        $light = if ($state.Count -gt 2) { $state[2] } else { 'deep-contrast-light' }
        return "following the system: $(Get-ThemeName $dark) or $(Get-ThemeName $light)"
    }
    return "fixed: $(Get-ThemeName $state[0])"
}

function Get-CurrentState {
    $script:Current.Clear()
    $neovim = Get-StateText

    $vs = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (Test-Path $vs) {
        $data = Get-Content -Raw $vs | ConvertFrom-Json
        $text = if ($data.'window.autoDetectColorScheme') {
            "following the system: $($data.'workbench.preferredDarkColorTheme') or $($data.'workbench.preferredLightColorTheme')"
        } else { "fixed: $($data.'workbench.colorTheme')" }
        Add-Current 'VS Code' $text
    }

    $zed =Join-Path $env:APPDATA 'Zed\settings.json'
    if (Test-Path $zed) {
        $theme = (Get-Content -Raw $zed | ConvertFrom-Json).theme
        $text = if ($theme -is [string]) { "fixed: $theme" }
                elseif (-not $theme) { 'fixed: default' }
                elseif ($theme.mode -eq 'system' -or -not $theme.mode) { "following the system: $($theme.dark) or $($theme.light)" }
                else { "fixed: $($theme.($theme.mode))" }
        Add-Current 'Zed' $text
    }

    $base = Join-Path $env:APPDATA 'JetBrains'
    if (Test-Path $base) {
        foreach ($dir in Get-ChildItem $base -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'options') }) {
            $laf = Join-Path $dir.FullName 'options\laf.xml'
            $schemeFile = Join-Path $dir.FullName 'options\colors.scheme.xml'
            $comp = if (Test-Path $laf) { ([xml](Get-Content -Raw $laf)).DocumentElement.SelectSingleNode("component[@name='LafManager']") }
            $node = if (Test-Path $schemeFile) { ([xml](Get-Content -Raw $schemeFile)).DocumentElement.SelectSingleNode('//global_color_scheme') }
            $editor = if ($node) { $node.GetAttribute('name') } else { 'default' }
            $text = if ($comp -and $comp.GetAttribute('autodetect') -eq 'true') {
                $d = $comp.SelectSingleNode('preferred-dark-laf'); $l = $comp.SelectSingleNode('preferred-light-laf')
                "Sync with OS: $(Get-ThemeName $(if ($d) { $d.GetAttribute('themeId') })) or $(Get-ThemeName $(if ($l) { $l.GetAttribute('themeId') }))"
            } else {
                $n = if ($comp) { $comp.SelectSingleNode('laf') }
                "fixed: $(Get-ThemeName $(if ($n) { $n.GetAttribute('themeId') }))"
            }
            $plugin = if (Test-Path (Join-Path $dir.FullName 'plugins\zacess-themes')) { '' } else { ' (no Zacess plugin)' }
            Add-Current "  $($dir.Name)" "$text, editor $editor$plugin"
        }
    }

    Add-Current 'Neovim' $neovim

    $eclipse = Get-CurrentEclipse
    if ($eclipse) { Add-Current 'Eclipse' $eclipse }
    $stm32 = Get-CurrentSTM32CubeIDE
    if ($stm32) { Add-Current 'STM32CubeIDE' $stm32 }
    $kicad = Get-CurrentKiCad
    if ($kicad) { Add-Current 'KiCad' $kicad }
    $vivado = Get-CurrentVivado
    if ($vivado) { Add-Current 'Vivado' $vivado }
    $processing = Get-CurrentProcessing
    if ($processing) { Add-Current 'Processing' $processing }
    $microchip = Get-CurrentMicrochipStudio
    if ($microchip) { Add-Current 'Microchip Studio' $microchip }

    $terminals = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }
    foreach ($path in $terminals) {
        $scheme = (Get-Content -Raw $path | ConvertFrom-Json).profiles.defaults.colorScheme
        $text = if ($scheme -is [string]) { "fixed: $scheme" }
                elseif ($scheme) { "following the system: $($scheme.dark) or $($scheme.light)" }
                else { 'fixed: default' }
        Add-Current 'Windows Terminal' $text
    }

    $alacritty = Join-Path $env:APPDATA 'alacritty\alacritty.toml'
    if (Test-Path $alacritty) {
        $m = [regex]::Match([IO.File]::ReadAllText($alacritty), 'zacess-([\w-]+)\.toml')
        Add-Current 'Alacritty' $(if ($m.Success) { "fixed: $(Get-ThemeName $m.Groups[1].Value)" } else { 'fixed: no Zacess import' })
    }

    $arduino = Join-Path $env:USERPROFILE '.arduinoIDE\settings.json'
    if (Test-Path $arduino) { Add-Current 'Arduino IDE' "fixed: $((Get-Content -Raw $arduino | ConvertFrom-Json).'workbench.colorTheme')" }

    $npp = Join-Path $env:APPDATA 'Notepad++\config.xml'
    if (Test-Path $npp) {
        $mode = ([xml](Get-Content -Raw $npp)).NotepadPlus.GUIConfigs.GUIConfig | Where-Object { $_.name -eq 'DarkMode' }
        $file = if ($mode.enable -eq 'yes') { $mode.darkThemeName } else { $mode.lightThemeName }
        Add-Current 'Notepad++' "fixed: $(if ($file) { $file -replace '\.xml$', '' } else { 'default' })"
    }

    $thonny = Join-Path $env:APPDATA 'Thonny\configuration.ini'
    if (Test-Path $thonny) {
        $m = Select-String -Path $thonny -Pattern '^syntax_theme = (.+)$' | Select-Object -First 1
        Add-Current 'Thonny' "fixed: $(if ($m) { $m.Matches[0].Groups[1].Value } else { 'default' })"
    }

    $ltspice = @((Join-Path $env:APPDATA 'LTspice.ini'), (Join-Path $env:APPDATA 'LTspiceXVII.ini')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($ltspice) {
        # LTspice 26 writes the whole ini as UTF-16; older versions write a UTF-16 start followed by
        # plain bytes, which latin-1 reads byte for byte
        $bytes = [IO.File]::ReadAllBytes($ltspice)
        $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            $wide = [Text.Encoding]::Unicode.GetString($bytes)
            if ($wide -match '(?m)^\[Colors\]\r?$') { $text = $wide }
        }
        $match = $Themes | Where-Object {
            $file = Join-Path $RepoRoot "editors\ltspice\shared\themes\$($_.Name).ini"
            (Test-Path $file) -and -not (Get-Content $file | Where-Object { $_ -match '^\w+=\d+$' -and $text -notmatch "(?m)^$([regex]::Escape($_))\r?$" })
        } | Select-Object -First 1
        Add-Current 'LTspice' $(if ($match) { "fixed: $($match.Name)" } else { 'fixed: not a Zacess theme' })
    }

    $proteus = 'HKCU:\Software\Labcenter Electronics\Proteus 8 Professional\ARES\Settings'
    if (Test-Path $proteus) {
        $set = (Get-ItemProperty $proteus).'Active Colour Set'
        $match = $Themes | Where-Object {
            $file = Join-Path $RepoRoot "editors\proteus\shared\themes\$($_.Name).json"
            (Test-Path $file) -and (Get-Content -Raw $file | ConvertFrom-Json).set -eq $set
        } | Select-Object -First 1
        Add-Current 'Proteus' "fixed: $(if ($match) { $match.Name } else { $set })"
    }

    $zotero = Get-ChildItem (Join-Path $env:APPDATA 'Zotero\Zotero\Profiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'user.js' } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($zotero) {
        $js = [IO.File]::ReadAllText($zotero)
        # several Zacess themes share one Zotero mode and reader theme, so every match is named as
        # zt.py does. doctor then finds the active theme among them
        $prefs = @{}
        foreach ($m in [regex]::Matches($js, 'user_pref\("([^"]+)",\s*(.+?)\);')) { $prefs[$m.Groups[1].Value] = $m.Groups[2].Value.Trim('"') }
        $map = Get-Content -Raw (Join-Path $RepoRoot 'apps\zotero\shared\themes.json') | ConvertFrom-Json
        $names = @(foreach ($theme in $map.PSObject.Properties) {
            if (-not @($theme.Value.PSObject.Properties | Where-Object { "$($prefs[$_.Name])" -ne "$($_.Value)" })) { $theme.Name.Replace('Zacess ', '') }
        })
        $mode = if ($prefs['browser.theme.toolbar-theme'] -eq '0') { 'dark' } else { 'light' }
        Add-Current 'Zotero' $(if ($names) { "fixed: $mode mode for $($names -join ' or ')" } else { 'not a Zacess theme' })
    }

    $vault = if ($env:OBSIDIAN_VAULT) { Join-Path $env:OBSIDIAN_VAULT '.obsidian' }
    if ($vault -and (Test-Path (Join-Path $vault 'appearance.json'))) {
        $look = Get-Content -Raw (Join-Path $vault 'appearance.json') | ConvertFrom-Json
        $style = Join-Path $vault 'plugins\obsidian-style-settings\data.json'
        $contrast = if (Test-Path $style) { (Get-Content -Raw $style | ConvertFrom-Json).'zacess-theme@@zacess-contrast' }
        $text = if ($look.cssTheme -ne 'Zacess') { "fixed: $($look.cssTheme) theme" }
                elseif ($contrast -and $contrast -ne 'zacess-follow') { "fixed: $(Get-ThemeName ($contrast -replace '^zacess-', ''))" }
                elseif ($look.theme -eq 'obsidian') { 'fixed: Zacess Dark' } else { 'fixed: Zacess Light' }
        Add-Current 'Obsidian' $text
    }

    $matlab = Get-CurrentMATLAB
    if ($matlab -and $matlab.Pending -and -not ($matlab.Theme -and $matlab.Theme.Name -eq $matlab.Pending)) {
        Add-Current 'MATLAB' "fixed: $($matlab.Pending), on next start"
    } elseif ($matlab) {
        Add-Current 'MATLAB' "fixed: $(if ($matlab.Theme) { $matlab.Theme.Name } else { 'not a Zacess theme' }), $(if ($matlab.Mode) { $matlab.Mode } else { 'System' }) desktop"
    }

    $highlight = Get-CurrentHighlight
    if ($highlight) { Add-Current 'Highlight' $highlight }
    return $script:Current.ToArray()
}

function Show-Current($Only) {
    if (-not $Only) { Write-Host "zt state: $(Get-StateText)" }
    Show-Pins $Only
    $pins = Read-Pins
    foreach ($item in Get-CurrentState) {
        $app = Get-LabelApp $item.Tool
        if ($Only -and $Only -notcontains $app) { continue }
        $text = $item.Text
        if ($app -eq 'neovim' -and $pins.Contains('neovim')) { $text = "pinned to $(Get-PinText $pins.neovim)" }
        elseif ($app -and $pins.Contains($app)) { $text += " (pinned to $(Get-PinText $pins[$app]))" }
        Write-Result $item.Tool $text $false
    }
    if ($Only) { return }
    $push = Read-JsonFile (Get-SharedFile)
    if ($push) {
        $what = if ($push.undo_of) { 'undo of the last push' } else { $push.state }
        $here = if ($push.id -eq (Read-Text $AllSeen)) { 'applied here' } else { 'not applied here yet' }
        Write-Host "--all: last push $what from $($push.from) at $($push.at), $here"
    }
}

# ---------------------------------------------------------------------------------------------------
# the Windows text highlight: the active theme's selection colour, read from the generated Windows
# Terminal scheme (its selectionBackground) and, since a scheme carries no selection text colour, the
# palette that scheme is built from. Windows reads both values at the next sign in, which is when
# these machines pull the dotfiles anyway. The values found before the first change are recorded, so
# `zt highlight default` can put them back
# ---------------------------------------------------------------------------------------------------

$HighlightRecord = Join-Path $env:LOCALAPPDATA 'zacess\highlight.default'
$ColoursKey = 'HKCU:\Control Panel\Colors'
$WindowsHighlight = @{ Hilight = '0 120 215'; HilightText = '255 255 255' }

function Get-SelectionColour($Theme) {
    $fragment = Join-Path $RepoRoot 'terminal\terminal\windows\windows-terminal\zacess.json'
    $scheme = (Get-Content -Raw $fragment | ConvertFrom-Json).schemes | Where-Object { $_.name -eq $Theme.Name } | Select-Object -First 1
    $palette = Join-Path $RepoRoot 'terminal\terminal\palette\zacess.json'
    $entry = (Get-Content -Raw $palette | ConvertFrom-Json).themes | Where-Object { $_.id -eq $Theme.Id } | Select-Object -First 1
    return @{ Background = $scheme.selectionBackground; Foreground = $entry.selection_foreground }
}

# "r g b" in decimal, the form the Colors key holds
function ConvertTo-RegistryColour([string]$Hex) {
    return (@(1, 3, 5) | ForEach-Object { [Convert]::ToInt32($Hex.Substring($_, 2), 16) }) -join ' '
}

function Set-Highlight($Fixed, $Dark, $Light, $Now) {
    $theme = if ($Fixed) { $Fixed } else { $Now }
    $colour = Get-SelectionColour $theme
    $wanted = @{ Hilight = ConvertTo-RegistryColour $colour.Background; HilightText = ConvertTo-RegistryColour $colour.Foreground }
    $current = Get-ItemProperty -Path $ColoursKey -ErrorAction SilentlyContinue
    if (-not $current) { return Write-Result 'Highlight' 'no Colors key to set, skipped' $false }
    if (-not (Test-Path $HighlightRecord)) {
        New-Item -ItemType Directory -Force (Split-Path $HighlightRecord) | Out-Null
        [IO.File]::WriteAllText($HighlightRecord, "Hilight=$($current.Hilight)`nHilightText=$($current.HilightText)`n")
    }
    $changed = $false
    foreach ($name in 'Hilight', 'HilightText') {
        if ("$($current.$name)" -ne $wanted[$name]) { Set-ItemProperty -Path $ColoursKey -Name $name -Value $wanted[$name]; $changed = $true }
    }
    $note = if ($Fixed) { '' } else { ' (the highlight cannot follow the system, so this matches it now)' }
    $when = if ($changed) { 'from the next sign in' } else { 'already set' }
    Write-Result 'Highlight' "$($colour.Background) with $($colour.Foreground) text, $($theme.Name)'s selection$note, $when"
}

function Restore-Highlight {
    $values = $WindowsHighlight.Clone()
    if (Test-Path $HighlightRecord) {
        foreach ($line in [IO.File]::ReadAllLines($HighlightRecord)) {
            $i = $line.IndexOf('=')
            if ($i -gt 0 -and $line.Substring($i + 1)) { $values[$line.Substring(0, $i)] = $line.Substring($i + 1) }
        }
    }
    if (-not (Test-Path $ColoursKey)) { return Write-Result 'Highlight' 'no Colors key to restore, skipped' $false }
    foreach ($name in 'Hilight', 'HilightText') { Set-ItemProperty -Path $ColoursKey -Name $name -Value $values[$name] }
    if (Test-Path $HighlightRecord) { Remove-Item $HighlightRecord }
    Write-Result 'Highlight' "restored: $($values.Hilight) with $($values.HilightText) text, from the next sign in"
}

function Get-CurrentHighlight {
    $current = Get-ItemProperty -Path $ColoursKey -ErrorAction SilentlyContinue
    if (-not $current) { return $null }
    foreach ($theme in $Themes) {
        $colour = Get-SelectionColour $theme
        if ("$($current.Hilight)" -eq (ConvertTo-RegistryColour $colour.Background)) {
            return "fixed: $($theme.Name)'s selection ($($colour.Background)), from the next sign in"
        }
    }
    if ("$($current.Hilight)" -eq $WindowsHighlight.Hilight) { return 'the Windows default' }
    return "not a Zacess selection ($($current.Hilight))"
}

# ---------------------------------------------------------------------------------------------------
# zt doctor: every installed theme file against the repo copy for the active theme and every tool's
# own setting against the state, so a copy that stopped matching the repo or a tool switched by hand
# shows up. Exit 1 on any drift
# ---------------------------------------------------------------------------------------------------

function Read-Text([string]$Path) {
    if ($Path -and [IO.File]::Exists($Path)) { return ([IO.File]::ReadAllText($Path)).Trim() }
    return ''
}

# a file another device is still writing or one that is not JSON reads as nothing, so the next run
# tries again. -DateKind String keeps the push time as written instead of a local date
function Read-JsonFile([string]$Path) {
    if (-not ($Path -and [IO.File]::Exists($Path))) { return $null }
    try { return [IO.File]::ReadAllText($Path) | ConvertFrom-Json -DateKind String } catch { return $null }
}

# a temp file in the same folder then a rename, so a syncing device never reads half a file
function Write-Atomic([string]$Path, [string]$Text) {
    $folder = Split-Path $Path
    New-Item -ItemType Directory -Force $folder | Out-Null
    $temp = Join-Path $folder ".$(Split-Path $Path -Leaf).$([guid]::NewGuid().ToString('N'))"
    [IO.File]::WriteAllText($temp, $Text, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp, $Path, $true)
}

# zt-all.json in the synced folder: ZACESS_SHARED_DIR, else .zacess in OneDrive Personal. $null on a
# device with neither
function Get-SharedFile {
    if ($env:ZACESS_SHARED_DIR) { return Join-Path $env:ZACESS_SHARED_DIR 'zt-all.json' }
    $root = if ($env:OneDriveConsumer) { $env:OneDriveConsumer } else { $env:OneDrive }
    if ($root -and (Test-Path $root)) { return Join-Path $root '.zacess\zt-all.json' }
    return $null
}

function New-Push([string]$State, $UndoOf) {
    [ordered]@{
        id = [guid]::NewGuid().ToString(); state = $State; undo_of = $UndoOf
        from = [Environment]::MachineName; at = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    }
}

function Get-ActivePair { ConvertFrom-StateText (Read-Text $StateFile) }

# a state file's text (a theme id or auto with a dark and a light id) as the themes it names
function ConvertFrom-StateText([string]$Text) {
    $state = @($Text.Trim() -split '\s+' | Where-Object { $_ })
    if ($state.Count -and $state[0] -eq 'auto') {
        $dark = $(if ($state.Count -gt 1) { Find-Theme $state[1] })
        if (-not $dark) { $dark = Find-Theme 'deep-contrast-dark' }
        $light = $(if ($state.Count -gt 2) { Find-Theme $state[2] })
        if (-not $light) { $light = Find-Theme 'deep-contrast-light' }
        return @{ Fixed = $null; Dark = $dark; Light = $light; Now = $(if (Test-SystemDark) { $dark } else { $light }) }
    }
    $fixed = $(if ($state.Count) { Find-Theme $state[0] })
    if (-not $fixed) { $fixed = Find-Theme 'deep-contrast-dark' }
    $dark = if ($fixed.Dark) { $fixed } else { Find-Theme 'deep-contrast-dark' }
    $light = if (-not $fixed.Dark) { $fixed } else { Find-Theme 'deep-contrast-light' }
    return @{ Fixed = $fixed; Dark = $dark; Light = $light; Now = $fixed }
}

$script:Drift = 0
$Bad = if ($env:NO_COLOR) { '' } else { "$e[31m" }

function Write-Doctor([string]$Tool, [string]$Status, [string]$Text) {
    $colour = switch ($Status) { 'ok' { $Ok } 'drift' { $Bad } default { $Skip } }
    Write-Host ("  {0}{1,-16}{2} {3}{4}: {5}{2}" -f $Bold, $Tool, $Reset, $colour, $Status, $Text)
    if ($Status -eq 'drift') { $script:Drift++ }
}

# whether a tool's own reading names the theme zt last set
function Test-Agrees($Pair, [string]$Text) {
    if ($Pair.Fixed) { return $Text.Contains($Pair.Fixed.Name) -or $Text.Contains($Pair.Fixed.Name.Replace('Zacess ', '')) }
    if ($Text.Contains('following the system') -or $Text.Contains('Sync with OS')) {
        $mentioned = @($Themes | Where-Object { $Text.Contains($_.Name) })
        return (-not $mentioned) -or ($Text.Contains($Pair.Dark.Name) -and $Text.Contains($Pair.Light.Name))
    }
    # a tool that cannot follow the system was set to the theme matching the appearance then
    return $Text.Contains($Pair.Now.Name)
}

function Test-Setting($Pair, [string]$Tool, $Text) {
    if ($null -eq $Text -or $Tool -eq 'Highlight') { return }
    $app = Get-LabelApp $Tool
    $pins = Read-Pins
    # a pinned app is meant to differ from the zt state
    if ($app -and $pins.Contains($app)) { return Write-Doctor $Tool 'ok' "pinned to $(Get-PinText $pins[$app]): $Text" }
    if ($Text.StartsWith('could not read') -or $Text.Contains('not a Zacess')) { return Write-Doctor $Tool 'drift' $Text }
    # Microchip Studio records only its dark or light environment, never the Zacess theme, so the
    # environment matching the active theme's appearance is all that can be checked
    if ($Tool -eq 'Microchip Studio' -and -not $Text.StartsWith('fixed:')) {
        return Write-Doctor $Tool $(if ($Text.StartsWith('dark') -eq [bool]$Pair.Now.Dark) { 'ok' } else { 'drift' }) $Text
    }
    Write-Doctor $Tool $(if (Test-Agrees $Pair $Text) { 'ok' } else { 'drift' }) $Text
}

function Compare-Bytes([string]$A, [string]$B) {
    $x = [IO.File]::ReadAllBytes($A); $y = [IO.File]::ReadAllBytes($B)
    if ($x.Length -ne $y.Length) { return $false }
    return [Linq.Enumerable]::SequenceEqual($x, $y)
}

# installed files against their repo copies: pairs of (installed, repo); a folder pair compares
# every file under the repo folder
function Test-Files([string]$Tool, $Pairs, [string]$What) {
    $problems = @()
    foreach ($pair in $Pairs) {
        $installed = [string]$pair[0]; $repo = [string]$pair[1]
        if (-not $repo -or -not (Test-Path $repo)) { continue }
        $shown = $installed.Replace($env:USERPROFILE, '~')
        if (-not (Test-Path $installed)) { $problems += "$shown missing"; continue }
        if (Test-Path $repo -PathType Container) {
            foreach ($file in Get-ChildItem $repo -Recurse -File) {
                $rel = $file.FullName.Substring($repo.Length).TrimStart('\', '/')
                $other = Join-Path $installed $rel
                if (-not (Test-Path $other)) { $problems += "$shown\$rel missing" }
                elseif (-not (Compare-Bytes $other $file.FullName)) { $problems += "$shown\$rel differs from the repo" }
            }
        } elseif (-not (Compare-Bytes $installed $repo)) {
            $problems += "$shown differs from $($repo.Replace($RepoRoot, '').TrimStart('\', '/'))"
        }
    }
    if ($problems) { return Write-Doctor $Tool 'drift' ($problems -join '; ') }
    Write-Doctor $Tool 'ok' $What
}

function Get-PinnedExtension([string]$Listing, [string]$Prefix) {
    if (-not (Test-Path $Listing)) { return $null }
    $m = Select-String -Path $Listing -Pattern ('^' + [regex]::Escape($Prefix) + '@(\S+)') | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
}

function Get-InstalledExtension([string]$Folder, [string]$Prefix) {
    if (-not (Test-Path $Folder)) { return $null }
    $found = Get-ChildItem $Folder -Directory -Filter "$Prefix-*" | ForEach-Object { if ($_.Name -match '-(\d+\.\d+\.\d+)') { [version]$Matches[1] } } | Sort-Object | Select-Object -Last 1
    if ($found) { return $found.ToString() }
}

function Invoke-Doctor {
    $pair = Get-ActivePair
    $wanted = @(if ($pair.Fixed) { $pair.Now } else { $pair.Dark; $pair.Light })
    $mode = if ($pair.Fixed) { "fixed $($pair.Now.Name)" } else { "following the system: $($pair.Dark.Name) or $($pair.Light.Name) (now $($pair.Now.Name))" }
    Write-Host "${Bold}zt state${Reset}: $mode"
    foreach ($item in Get-CurrentState) { Test-Setting $pair $item.Tool $item.Text }

    $vs = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (Test-Path $vs) {
        Test-Files 'VS Code' @(
            @($vs, (Join-Path $RepoRoot 'editors\vscode\windows\settings.json')),
            @((Join-Path $env:APPDATA 'Code\User\keybindings.json'), (Join-Path $RepoRoot 'editors\vscode\windows\keybindings.json')),
            @((Join-Path $env:APPDATA 'Code\User\snippets\global.code-snippets'), (Join-Path $RepoRoot 'editors\vscode\windows\global.code-snippets'))
        ) 'settings, key bindings and snippets match the repo'
        $pin = Get-PinnedExtension (Join-Path $RepoRoot 'editors\vscode\windows\extensions.txt') 'zacess.zacess-themes'
        $installed = Get-InstalledExtension (Join-Path $env:USERPROFILE '.vscode\extensions') 'zacess.zacess-themes'
        if ($pin -and $installed) {
            $status = if ([version]$installed -lt [version]$pin) { 'drift' } else { 'ok' }
            Write-Doctor 'VS Code' $status "Zacess Themes $installed installed, $pin pinned in extensions.txt"
        }
    }
    # the Zacess Themes plugin in each JetBrains IDE against the pinned release
    $jbPin = (Get-Content -Raw (Join-Path $RepoRoot 'editors\jetbrains\shared\theme-package.json') | ConvertFrom-Json).version
    foreach ($dir in Get-ChildItem (Join-Path $env:APPDATA 'JetBrains') -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'plugins\zacess-themes\lib') }) {
        $jar = Get-ChildItem (Join-Path $dir.FullName 'plugins\zacess-themes\lib') -Filter '*.jar' | Sort-Object Name | Select-Object -First 1
        $version = $null
        if ($jar) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [IO.Compression.ZipFile]::OpenRead($jar.FullName)
            try {
                $entry = $zip.GetEntry('META-INF/plugin.xml')
                if ($entry) { $r = [IO.StreamReader]::new($entry.Open()); try { $version = [regex]::Match($r.ReadToEnd(), '<version>\s*([^<]+?)\s*</version>').Groups[1].Value } finally { $r.Dispose() } }
            } finally { $zip.Dispose() }
        }
        $parsed = $null
        $status = if ($version -and [version]::TryParse($version, [ref]$parsed) -and $parsed -ge [version]$jbPin) { 'ok' } else { 'drift' }
        Write-Doctor "  $($dir.Name)" $status "Zacess Themes $(if ($version) { $version } else { 'unknown' }) installed, $jbPin pinned in theme-package.json"
    }
    $zed = Join-Path $env:APPDATA 'Zed\settings.json'
    if (Test-Path $zed) {
        $pairs = @(, @($zed, (Join-Path $RepoRoot 'editors\zed\windows\settings.json')))
        $local = Join-Path $env:APPDATA 'Zed\themes\zacess.json'
        if (Test-Path $local) { $pairs += , @($local, (Join-Path $RepoRoot 'editors\zed\shared\themes\zacess.json')) }
        Test-Files 'Zed' $pairs 'settings match the repo'
    }
    $nvim = Join-Path $env:LOCALAPPDATA 'nvim'
    if (Test-Path $nvim) { Test-Files 'Neovim' @(, @($nvim, (Join-Path $RepoRoot 'editors\neovim\windows\nvim'))) 'the config files match the repo' }
    $fragment = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\Zacess\zacess.json'
    if (Test-Path $fragment) { Test-Files 'Windows Terminal' @(, @($fragment, (Join-Path $RepoRoot 'terminal\terminal\windows\windows-terminal\zacess.json'))) 'the scheme fragment matches the repo' }
    $alacritty = Join-Path $env:APPDATA 'alacritty'
    if (Test-Path (Join-Path $alacritty 'alacritty.toml')) {
        $pairs = @($wanted | ForEach-Object { , @((Join-Path $alacritty "zacess-$($_.Id).toml"), (Join-Path $RepoRoot "terminal\terminal\windows\alacritty\zacess-$($_.Id).toml")) })
        Test-Files 'Alacritty' $pairs 'the theme files match the repo'
    }
    $highlight = Get-CurrentHighlight
    $pins = Read-Pins
    if ($highlight -and $pins.Contains('highlight') -and $pins.highlight -in $DefaultValues) {
        Write-Doctor 'Highlight' 'ok' "pinned to Windows' own: $highlight"
    } elseif ($highlight) {
        # a theme pin is checked against that theme's selection
        if ($pins.Contains('highlight')) { $pair = ConvertFrom-StateText $pins.highlight }
        $expected = (Get-SelectionColour $pair.Now).Background
        if ($highlight.Contains($expected)) { Write-Doctor 'Highlight' 'ok' $highlight }
        else { Write-Doctor 'Highlight' 'drift' "$highlight, $($pair.Now.Name)'s selection is $expected" }
    }
    if ($script:Drift) { Write-Host "$Bad$($script:Drift) drift$Reset"; return 1 }
    Write-Host "${Ok}no drift${Reset}"
    return 0
}

$command = if ($args.Count) { [string]$args[0] } else { 'help' }
switch ($command) {
    { $_ -in 'help', '-h', '--help' } {
        Get-Content $PSCommandPath | Select-Object -Skip 2 -First 8 | ForEach-Object { $_.TrimStart('#').TrimStart() }
        exit 0
    }
    'list' {
        $current = @(if (Test-Path $StateFile) { ([IO.File]::ReadAllText($StateFile)).Trim() -split '\s+' } else { @('deep-contrast-dark') })
        foreach ($theme in $Themes) {
            $mark = if ($current -contains $theme.Id) { ' *' } else { '' }
            Write-Host ("  {0,-11} {1}{2}" -f $theme.Short, $theme.Name, $mark)
        }
        exit 0
    }
    'current' {
        $only = $null
        if ($args.Count -gt 1) {
            $only = if ($args[1] -eq 'terminals') { $Terminals } else { @(Find-App $args[1]) | Where-Object { $_ } }
            if (-not $only) { [Console]::Error.WriteLine("Unknown app: $($args[1])"); exit 1 }
        }
        try { Show-Current $only } catch { [Console]::Error.WriteLine("could not read a setting: $($_.Exception.Message)") }
        exit 0
    }
    'doctor' {
        try { exit (Invoke-Doctor) } catch { [Console]::Error.WriteLine("could not check a setting: $($_.Exception.Message)"); exit 1 }
    }
    'highlight' {
        if ($args.Count -eq 2 -and $args[1] -eq 'default') { Restore-Highlight; exit 0 }
        if ($args.Count -gt 1) { [Console]::Error.WriteLine('Usage: zt highlight [default]'); exit 1 }
        $pair = Get-ActivePair
        Set-Highlight $pair.Fixed $pair.Dark $pair.Light $pair.Now
        exit 0
    }
}

# every command below comes down to a state file's text to apply: a theme, auto, zt undo going back
# to the state before the last change or zt sync taking a push another device left with --all
$all = $args -contains '--all'
$words = @($args | Where-Object { $_ -ne '--all' })
if (-not $words) { [Console]::Error.WriteLine('Usage: zt <theme> --all or zt undo --all'); exit 1 }
$before = Read-Text $StateFile
$quiet = $false
$send = $false
$after = @()
# zt pin and zt unpin run only the apps they name, on the zt state or their pin
$onlyApps = $null
switch ($words[0]) {
    'pin' {
        if ($words.Count -lt 3) {
            [Console]::Error.WriteLine("Usage: zt pin <app> <theme|auto [dark] [light]|default|default-dark|default-light>`nApps: $($PinApps.Keys -join ', '). terminals pins $($Terminals -join ', ')")
            exit 1
        }
        $group = $words[1] -eq 'terminals'
        $app = if ($group) { $null } else { Find-App $words[1] }
        if (-not $group -and -not $app) {
            [Console]::Error.WriteLine("Unknown app: $($words[1]). The apps are $($PinApps.Keys -join ', '). terminals pins every terminal.")
            exit 1
        }
        try { $value = ConvertTo-PinValue @($words[2..($words.Count - 1)]) } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
        $names = if ($group) { $Terminals } else { @($app) }
        $chosen = @(); $skipped = @()
        foreach ($name in $names) {
            if ($value -in $DefaultValues -and $PinApps[$name].Defaults -notcontains $value) { $skipped += "$name (no built-in theme of that kind zt can set)" }
            else { $chosen += $name }
        }
        if (-not $group -and $skipped) {
            $supported = $PinApps[$app].Defaults
            if ($supported) { [Console]::Error.WriteLine("$app has no built-in $($value.Split('-')[-1]) theme zt can switch to; it supports $($supported -join ', ').") }
            else { [Console]::Error.WriteLine("$app has no built-in theme zt can switch to, so it can be pinned to a Zacess theme or auto only.") }
            exit 1
        }
        # a fresh highlight pin starts over: a default pin restores once again
        if ($chosen -contains 'highlight' -and (Test-Path $HighlightDefaulted)) { Remove-Item $HighlightDefaulted }
        $pins = Read-Pins
        $state = if ($before) { $before } else { 'deep-contrast-dark' }
        # an auto pin that matches zt's own auto state is the same as no pin
        $same = $value.StartsWith('auto') -and $state -eq $value
        foreach ($name in $chosen) { if ($same) { $pins.Remove($name) } else { $pins[$name] = $value } }
        Write-Pins $pins
        if ($same) { Write-Host "${Bold}Following zt again${Reset}: $($chosen -join ', ') (zt already follows the system with that pair)" }
        else { Write-Host "${Bold}Pinned${Reset} $($chosen -join ', ') to $(Get-PinText $value)" }
        if ($skipped) { Write-Host "  ${Skip}left as they were: $($skipped -join '; ')${Reset}" }
        $onlyApps = $chosen; $target = $state; $quiet = $true
    }
    'unpin' {
        if ($words.Count -lt 2 -and -not $all) { [Console]::Error.WriteLine('Usage: zt unpin <app|terminals|--all>'); exit 1 }
        $pins = Read-Pins
        $names = if ($all) { @($pins.Keys) }
            elseif ($words[1] -eq 'terminals') { @($Terminals | Where-Object { $pins.Contains($_) }) }
            else {
                $app = Find-App $words[1]
                if (-not $app) { [Console]::Error.WriteLine("Unknown app: $($words[1]). The apps are $($PinApps.Keys -join ', ')."); exit 1 }
                @($app | Where-Object { $pins.Contains($_) })
            }
        if (-not $names) { Write-Host 'Nothing pinned there'; exit 0 }
        foreach ($name in $names) { $pins.Remove($name) }
        Write-Pins $pins
        if ($names -contains 'highlight' -and (Test-Path $HighlightDefaulted)) { Remove-Item $HighlightDefaulted }
        Write-Host "${Bold}Following zt again${Reset}: $($names -join ', ')"
        $onlyApps = $names; $target = if ($before) { $before } else { 'deep-contrast-dark' }; $quiet = $true
    }
    'undo' {
        if (-not $all) {
            $target = Read-Text $PreviousFile
            if (-not $target) { Write-Host 'Nothing to undo'; exit 0 }
            break
        }
        $shared = Get-SharedFile
        $push = Read-JsonFile $shared
        if (-not $push -or $push.undo_of) { Write-Host 'Nothing to undo on every device'; exit 0 }
        $entry = New-Push '' $push.id
        Write-Atomic $shared ($entry | ConvertTo-Json -Compress)
        Write-Atomic $AllSeen $entry.id
        $after += 'Undone on every device: each one goes back to its own previous theme when a terminal next opens there'
        $applied = Read-JsonFile $AllApplied
        if (-not ($applied -and $applied.id -eq $push.id -and $applied.previous)) { $after | ForEach-Object { Write-Host $_ }; exit 0 }
        $target = $applied.previous
    }
    'sync' {
        # started hidden at shell start, so it prints nothing
        $quiet = $true
        $push = Read-JsonFile (Get-SharedFile)
        if (-not $push -or $push.id -eq (Read-Text $AllSeen)) { exit 0 }
        # claimed first, so two terminals opening together never apply the same push twice
        Write-Atomic $AllSeen $push.id
        if ($push.undo_of) {
            $applied = Read-JsonFile $AllApplied
            if (-not ($applied -and $applied.id -eq $push.undo_of -and $applied.previous)) { exit 0 }
            $target = $applied.previous
        } else {
            Write-Atomic $AllApplied ([ordered]@{ id = $push.id; previous = $before } | ConvertTo-Json -Compress)
            $target = $push.state
        }
    }
    'auto' {
        $dark = Find-Theme $(if ($words.Count -gt 1) { $words[1] } else { 'deep-contrast-dark' })
        $light = Find-Theme $(if ($words.Count -gt 2) { $words[2] } else { 'deep-contrast-light' })
        if (-not $dark -or -not $light) { [Console]::Error.WriteLine('Unknown theme. Run zt list for the names.'); exit 1 }
        $target = "auto $($dark.Id) $($light.Id)"
        $send = $all
    }
    default {
        $fixed = Find-Theme ($words -join ' ')
        if (-not $fixed) { [Console]::Error.WriteLine("Unknown theme: $($words -join ' '). Run zt list for the names."); exit 1 }
        $target = $fixed.Id
        $send = $all
    }
}

$pair = ConvertFrom-StateText $target
$fixed = $pair.Fixed; $dark = $pair.Dark; $light = $pair.Light; $now = $pair.Now
if ($before -and $before -ne $target -and -not $onlyApps) { Write-Atomic $PreviousFile $before }
$Pins = Read-Pins
# a pin run prints its own lines, so it keeps quiet only about the heading
$showLines = -not $quiet -or $onlyApps
if (-not $quiet) {
    if ($fixed) { Write-Host "${Bold}$($fixed.Name)${Reset} everywhere, not following the system" }
    else { Write-Host "${Bold}Following the system${Reset}: $($dark.Name) in dark mode, $($light.Name) in light mode (now $(if ($now.Dark) { 'dark' } else { 'light' }))" }
    if ($Pins.Count) { Write-Host "  ${Skip}pinned, kept on their own theme: $(@($Pins.Keys | Sort-Object) -join ', ')${Reset}" }
}

# every tool runs at once in a runspace pool, so a switch takes about as long as the slowest tool.
# each group's lines are collected and printed in this order, so the output reads as it always has
$groups = @('Set-VSCode', 'Set-Zed', 'Set-JetBrains', 'Set-Neovim', 'Set-Eclipse', 'Set-STM32CubeIDE', 'Set-KiCad', 'Set-Vivado',
    'Set-WindowsTerminal', 'Set-Alacritty', 'Set-Tmux', 'Set-Btop', 'Set-ArduinoIDE', 'Set-NotepadPlusPlus', 'Set-Thonny', 'Set-LTspice', 'Set-Proteus', 'Set-Zotero',
    'Set-Obsidian', 'Set-MATLAB', 'Set-Processing', 'Set-MicrochipStudio', 'Set-Highlight')

# each runspace starts with this script's functions and top-level values
$script:Ast = [Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$null, [ref]$null)
$iss = [InitialSessionState]::CreateDefault2()
foreach ($definition in $script:Ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] }) {
    $iss.Commands.Add([Management.Automation.Runspaces.SessionStateFunctionEntry]::new($definition.Name, (Get-Item "function:$($definition.Name)").Definition))
}
# only values set before this point: the session state and pool below must not be copied into it
$cut = $script:Ast.Find({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and "$($node.Left)" -eq '$groups' }, $false).Extent.StartOffset
$names = $script:Ast.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Extent.StartOffset -lt $cut }, $false) |
    ForEach-Object { $_.Left.VariablePath.UserPath -replace '^script:', '' } | Sort-Object -Unique
# a name the default state already holds (ErrorActionPreference) is replaced, not added again.
# $null and other constants are left out
foreach ($name in $names) {
    $variable = Get-Variable -Name $name -ErrorAction SilentlyContinue
    if ($variable -and -not ($variable.Options -band ([Management.Automation.ScopedItemOptions]::Constant -bor [Management.Automation.ScopedItemOptions]::ReadOnly))) {
        $iss.Variables.Remove($name, $null)
        $iss.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new($name, $variable.Value, ''))
    }
}
# the apply scripts write their reasons to the console's error writer, which is one per process, so
# one shared writer collects them for the whole run and Invoke-AppScript leaves it in place
$errors = [IO.StringWriter]::new()
$iss.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new('ZtErrors', $true, ''))
$console = [Console]::Error
[Console]::SetError([IO.TextWriter]::Synchronized($errors))
# zt pin and zt unpin run only the tools of the apps they name
$run = if ($onlyApps) {
    @(foreach ($group in $groups) {
        $kept = @(@($group) | Where-Object { $onlyApps -contains $ToolApp[$_] })
        if ($kept.Count) { , $kept }
    })
} else { $groups }
$pool = [runspacefactory]::CreateRunspacePool($iss)
$null = $pool.SetMaxRunspaces([Math]::Max(1, $run.Count))
$pool.Open()
try {
    $jobs = foreach ($group in $run) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $null = $ps.AddScript({
            param($Tools, $Fixed, $Dark, $Light, $Now)
            foreach ($tool in $Tools) {
                try {
                    $app = $ToolApp[$tool]
                    if ($app -and $Pins.Contains($app) -and $app -ne 'neovim') {
                        Invoke-Pin $tool $Pins[$app]
                    } elseif ($app -eq 'neovim' -and $Pins.Contains('neovim')) {
                        # Neovim's state file is zt's own state, so it is written either way and the
                        # pin is read by Neovim itself
                        & $tool $Fixed $Dark $Light $Now 6>$null
                        Write-Result 'Neovim' "pinned to $(Get-PinText $Pins.neovim), on next focus or start"
                    } else {
                        & $tool $Fixed $Dark $Light $Now
                    }
                } catch {
                    # one broken config never stops the other tools
                    Write-Result ($tool -replace '^Set-', '') "failed: $($_.Exception.Message)" $false
                }
            }
        }).AddArgument(@($group)).AddArgument($fixed).AddArgument($dark).AddArgument($light).AddArgument($now)
        [pscustomobject]@{ Shell = $ps; Handle = $ps.BeginInvoke(); Name = (@($group)[0] -replace '^Set-', '') }
    }
    foreach ($job in $jobs) {
        try { $null = $job.Shell.EndInvoke($job.Handle) } catch { Write-Result $job.Name "failed: $($_.Exception.InnerException.Message)" $false }
        if ($showLines) { foreach ($record in $job.Shell.Streams.Information) { Write-Host $record.MessageData.ToString() } }
        $job.Shell.Dispose()
    }
} finally {
    [Console]::SetError($console)
    $pool.Close()
}
$messages = $errors.ToString().Trim()
if ($messages -and -not $quiet) { [Console]::Error.WriteLine($messages) }

if ($send) {
    $shared = Get-SharedFile
    if (-not $shared) {
        Write-Host 'No OneDrive on this device, so only this device changed'
    } else {
        $push = New-Push $target $null
        Write-Atomic $shared ($push | ConvertTo-Json -Compress)
        Write-Atomic $AllSeen $push.id
        Write-Atomic $AllApplied ([ordered]@{ id = $push.id; previous = $before } | ConvertTo-Json -Compress)
        Write-Host 'Sent to every device: each one switches when a terminal next opens there'
    }
}
$after | ForEach-Object { Write-Host $_ }
