# =============================================================================
# dotfiles - Windows PowerShell profile
# github.com/zaccesss/dotfiles - MIT licence
#
# topic loader - all functions and aliases live in windows/topics/*.ps1.
# deploy on a new machine by copying this file to $PROFILE:
#   Copy-Item windows\Microsoft.PowerShell_profile.ps1 $PROFILE -Force
# All topic files are dot-sourced in numbered order from the DOTFILES path.
# =============================================================================

# the topic files use PowerShell 7 syntax that Windows PowerShell 5.1 cannot parse, so 5.1 stops
# here with one hint instead of a screen of parse errors. this block must stay 5.1-compatible
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "dotfiles need PowerShell 7: run pwsh" -ForegroundColor DarkGray
    return
}

# a window started from one opened before the shell/ move can inherit DOTFILES naming the clone's
# root, which has no topics, so a value without them counts as unset
$env:DOTFILES = if ($env:DOTFILES -and (Test-Path (Join-Path $env:DOTFILES 'windows\topics'))) { $env:DOTFILES } else { "$HOME\dev\github\repos\dotfiles\shell" }

# an elevated window starts in System32 whatever the terminal profile says, so it moves home
if ((Get-Location).Path -eq [Environment]::SystemDirectory) { Set-Location $HOME }

# the topics load as one cached file: Windows parses and virus-scans every file it opens, so dozens of
# small files cost seconds where one costs a fraction. the first line of the bundle records which
# topics it was made from and when, so adding, removing or editing a topic rebuilds it. a bundle
# that cannot be parsed falls back to loading each topic on its own
$topics = Get-ChildItem "$env:DOTFILES\windows\topics\*.ps1" | Sort-Object Name
$bundle = Join-Path $HOME '.cache/dotfiles/topics.ps1'
$bundleKey = '# topics: ' + (($topics | ForEach-Object { '{0}@{1}' -f $_.Name, $_.LastWriteTimeUtc.Ticks }) -join ' ')
if (-not (Test-Path $bundle) -or (Get-Content $bundle -TotalCount 1) -ne $bundleKey) {
    New-Item -ItemType Directory -Force -Path (Split-Path $bundle) | Out-Null
    $parts = @($bundleKey) + ($topics | ForEach-Object { "# --- $($_.Name)"; Get-Content $_.FullName -Raw })
    Set-Content -Path $bundle -Value $parts -Encoding utf8
}
try {
    . $bundle
} catch [System.Management.Automation.ParseException] {
    foreach ($topic in $topics) { . $topic.FullName }
}

# =============================================================================
# Welcome banner - printed after all topics load so welcome is defined
# =============================================================================

# a program that runs pwsh -Command or -File reads everything printed as its result, so the
# banner only shows in an interactive window
$batch = [Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^[-/](c|co|com|comm|comma|comman|command|f|fi|fil|file|e|ec|en|enc\w*|noni\w*)$' }
# -NoExit keeps the window interactive after its command, which is how psmux starts every pane
# (pwsh -NoExit -Command, loading the profile itself), so the banner shows there as it does in tmux
$stays = [Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^[-/]noe\w*$' }
if ((-not $batch -or $stays) -and -not [Console]::IsOutputRedirected) { welcome }
Remove-Variable batch, stays
