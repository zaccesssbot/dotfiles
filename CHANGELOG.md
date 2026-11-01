# Changelog

All notable changes to this dotfiles repository are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
A patch step for fixes, a minor step for additions and a major step when the layout or the paths change.

---

## [Unreleased]

### Added

- psmux runs tmux natively on Windows. `~/.tmux.conf` links to `terminal/tmux/windows/tmux.conf`, written for psmux: the Zacess theme from `%LOCALAPPDATA%\zacess`, the vim-tmux-navigator bindings written out and `Ctrl+B` then `f` opening the project list in a window of its own. `ta`, `tn`, `tls`, `tk`, `tka` and `tkillother` use psmux in PowerShell and Command Prompt. WSL keeps its own tmux and the Linux config.
- Seven project layouts beside `ide` on macOS, Linux and Windows: `idev` (the dev server's logs), `imon` (btop and `docker ps`), `ilab` (build and serial monitor shells), `ilog` (two log shells), `iplay` (Zacess Games), `ireview` (`gh pr status` and lazygit) and `itest` (a test watcher for vitest, npm, artisan, pytest or cargo watch). Each opens a session named after the folder with a Zacess Scenes pane. Shared helpers keep every layout short.
- btop and btop4win in the eight Zacess themes: `terminal/btop/themes`, generated from the palette by `build-themes.py` with every text colour at 4.5:1 or more. `zt` links them into btop's themes folder and sets `color_theme` and `theme_background` in `btop.conf`. On Windows that covers both folders btop4win reads, beside the exe and in `WinGet\Links`. The Brewfile and the Windows package list install btop.
- Neovim: a debugger (nvim-dap with its panel, each language's adapter installed through Mason with `:DapInstall`), diffview on `Space g d` and `Space g h`, `Space x e` for a line's full error and `Space c r` to run the current file in the pane below. The run key covers Python, C and C++, Java, JavaScript, TypeScript, Lua, shell, PowerShell, Rust, Go and PHP.

### Changed

- `zt` updates programs that are already open: every psmux session (each one by name, since psmux keeps a server per session), every running Neovim over its socket or named pipe and btop on macOS and Linux through `SIGUSR2`. btop4win cannot reload, so `zt` says to reopen it.
- `ta` and `tn` switch to the session from inside tmux or psmux instead of nesting, on every platform.
- Inside psmux on Windows, `ide-pick` shows a numbered list read with `Read-Host`, since a real keyboard reached fzf there as plain letters. Outside psmux it keeps fzf.
- `imon`'s Docker pane shows one short line and checks again every five seconds while Docker is not running, rather than repeating a connection error.
- CI checks that each psmux theme is the shared tmux theme without the two options psmux rejects.

### Fixed

- The welcome banner shows in psmux panes, which psmux starts as `pwsh -NoExit -Command`.
- `tkillother` on Windows keeps the session it is run from. psmux's `kill-session -a` closes the current session instead. A session made from outside psmux also keeps its spare server's name in `PSMUX_SESSION`, so the session is now read from `display-message`.
- `Ctrl+H/J/K/L` reach Neovim in psmux once a language server is running. psmux names a pane after its newest child process, so Neovim marks its own pane instead.

## [2.4.1] - 2026-10-30

### Fixed

- tmux shows a session name of up to 40 characters, since `ide` names each session after its project folder. The default of 10 cut longer names short.
- The mouse wheel over a Zacess scene pane no longer enters tmux's scroll mode, which froze the picture until `q`.
- Terminal.app's eight Zacess profiles use GeistMono Nerd Font, the font every other terminal here uses. SF Mono has none of the icons the prompt and Neovim draw, so they showed as boxes. Terminal.app does not borrow them from another font either.
- On Linux `~/.cargo/bin` joins `PATH` even when cargo came from the package manager, which has no `~/.cargo/env`, so `cargo install` tools such as bacon are found.
- `zt doctor` checks Ptyxis on Linux, so a Ptyxis still on its own palette counts as drift instead of passing unseen.
- `zt` themes Ptyxis 50, which renamed its `palette-name` setting to `palette`. A refused palette change is now reported rather than shown as a success.

## [2.4.0] - 2026-10-30

### Added

- `ide` (or `ide <folder>`) opens a project in its own tmux session: Neovim on the top 70 percent, a shell bottom left, a Zacess Scenes follow scene bottom right and a `git` window running lazygit in a repository. Running it again goes back to the open session. `Ctrl+B` then `f` lists the folders in `IDE_ROOTS` with fzf and opens the one picked.
- vim-tmux-navigator in tmux and Neovim: `Ctrl+H/J/K/L` move across tmux panes and Neovim splits as one set. The prefix sends each of those keys on to a shell pane, so `Ctrl+B` then `Ctrl+L` still clears the screen.
- Neovim: snacks.nvim (a start screen, a file tree on `Space e`, lazygit on `Space g g`, indent guides with no animation and a quieter message area), conform.nvim (format on save with an installed formatter, never the language server), nvim-autopairs and trouble.nvim (`Space x x`). `lua/config/servers.lua` adds marksman everywhere and rust_analyzer, gopls, jdtls, html, cssls, jsonls and bashls only where their runtime is installed.
- `zt pin <app> <theme>` keeps one app on its own theme while every other app follows `zt` on macOS, Linux and Windows. A pin can also be `auto` with its own pair or the app's built-in theme (`default`, `default-dark` or `default-light`). `zt unpin` hands an app back and `zt current` and `zt doctor` show the pins.
- The shell topics load the Zacess Scenes follow hook for zsh, bash and PowerShell, so a scene running `zsf` (`zacess-scenes follow`) shows how each command ended. `zs` moves to another scene every five minutes and `zw` watches a project in any language.

### Changed

- Neovim uses the eight Zacess colour schemes from zacess.nvim 0.6.0, picked from the theme `zt` last set (or a `zt pin neovim` line) and checked again on focus. The earlier `high-contrast` scheme stays available through `:colorscheme high-contrast`.
- `termtheme` is the terminals-only side of `zt` on every system: a theme, `auto` or `default` pins every terminal app `zt` switches and no argument shows what each one is on.
- The example `scenes.toml` changes the scene every 5 minutes, plays the typo tone and has the new `[ambient]` (off) and `[follow]` sections, which need Zacess Scenes 0.5.0.

## [2.3.1] - 2026-10-30

### Fixed

- The Zacess Scenes and Games setup rejected every download on Fedora as a checksum mismatch, because Fedora has `sha256sum` but no `shasum`. Both setups now use `sha256sum` when it exists and `shasum` otherwise.

## [2.3.0] - 2026-10-29

### Added

- Zacess Games in `apps/zacess-games`: setup scripts for macOS, Linux and Windows install the newest release binary checked against its checksum, only when it is newer. Every bootstrap runs them in its apps stage. The shell topics `zacess-games` add `zg` for the menu or one of the fourteen games by name, with `zg list` for best scores, `zg sounds` to hear every effect and each game's music, `zg snap` for SVG stills and Tab completion of the game names. The games follow the theme `zt` last set; on Windows `zg` hands it over, as the Scenes commands do.

## [2.2.0] - 2026-10-29

### Added

- Zacess Scenes in `apps/zacess-scenes`: an example `scenes.toml` linked into the config folder. Setup scripts for macOS, Linux and Windows install the newest release binary checked against its checksum plus bacon for watch mode. Every bootstrap runs them in its apps stage. The shell topics `zacess-scenes` add `zs` for a random calm scene or a scene by name, with the subcommands list, sounds, config, new, snap and themes. `zw` watches a Rust build, `zwc` with Clippy, `zwt` with the tests and `zwa` with check-all. Scenes follows the theme `zt` last set; on Windows the PowerShell commands hand it over, since `zt` keeps it under `%LOCALAPPDATA%` there.

## [2.1.0] - 2026-10-29

### Added

- KDE Plasma defaults in `setup/defaults/linux/kde`, tested on Fedora KDE Plasma 6.7:
  - High contrast light and dark global themes switching by time of day and a larger yellow pointer.
  - A see-through Windows 11-style taskbar: the Zacess Dark Plasma style at a 15 percent tint over KWin's blur, with a faint line along its top edge.
  - A centred start menu (Menu11 - Next, pinned to its release commit), with Kickoff as the fallback.
  - Wallpaper slideshows for the desktop, lock screen and login screen.
  - Windows-style keys, scroll bars, touchpad scrolling and the UK region.
- `apps/onedrive`: a personal OneDrive synced in full into `~/OneDrive` on Linux by the OneDrive client, with OneDriveGUI's tray icon started minimised at login. On Linux `zt --all` falls back to `~/OneDrive/.zacess` when `ZACESS_SHARED_DIR` is not set.
- `zt undo` returns to the theme before the last change and `zt <theme> --all` changes every device through a synced folder (`.zacess/zt-all.json` in OneDrive Personal unless `ZACESS_SHARED_DIR` names another folder). Each device applies it once when a terminal next opens there and `zt undo --all` returns each to its own previous theme. `zt` also runs every tool at once and leaves MATLAB's theme for its next start.
- A Windows PC can keep its own TranslucentTB values in `apps/translucenttb/windows/machines/<computer name>.json`.
- MATLAB and Microchip Studio take a theme change on their next start: the apply scripts gain a pending mode and a marked `startup.m` block runs `editors/matlab/shared/zacess_startup.m`, so switching a theme never has to start either app.
- `zt doctor`: every installed theme file against the repo copy for the active theme and every tool's own setting against the state, one line per tool, exit 1 on any drift. On the Mac and Linux it covers VS Code (settings, snippets and the pinned Zacess Themes extension), Zed, the JetBrains IDEs (theme and the shared copies), Neovim (every config file), the Eclipse family and every app with an apply script, Terminal.app (profile colours decoded, since Terminal.app stores them without the alpha), iTerm2, Kitty, Alacritty, Ghostty, tmux (the config, the linked theme file and a running server's copy mode colours), Xcode against a Zacess Themes clone and the system highlight. On Windows it covers VS Code, Zed, the JetBrains IDEs, Neovim, the Windows Terminal fragment, Alacritty, every app with a reader and the registry highlight.
- `zt <theme>` sets the system text highlight from the theme's selection colour, read from the generated terminal theme (iTerm2's profile on the Mac, Kitty's file on Linux, the Windows Terminal scheme on Windows): `AppleHighlightColor` on macOS with the colour change notification posted, `[Colors:Selection]` in the installed Zacess colour schemes on KDE Plasma and the GTK named colours on GNOME, `Hilight` and `HilightText` on Windows for the next sign in. The value found first is recorded and `zt highlight default` puts it back; `zt highlight` applies it again.
- tmux theme files, one per Zacess theme in `terminal/tmux/themes`, generated from the terminal palette: the status bar in the theme's text and background, the message line in its accent pair, copy mode in its selection pair, search matches in its find colour and the pane borders in two colours. `zt` links the active one to `~/.local/state/zacess/tmux.conf`, which `tmux.conf` sources. A running server reloads at once. The active pane also carries border arrows.
- `terminal/terminal/scripts/sync-palette.py` copies the palette from a pinned Zacess Themes release (`--version`, `--from <clone>` offline, `--check`), regenerates every theme file and moves the Zed theme file and zacess.nvim pins to the same release. A release without the strong selection pair keeps the selection the palette already holds.
- Ghostty theme files for the Mac and Linux, a starter config with `minimum-contrast = 4.5` and the Mac installer linking the themes.
- `apps/translucenttb`: TranslucentTB from winget with a dark acrylic taskbar over the desktop that turns solid with a maximised window or battery saver. The apps stage merges the tracked values into its settings file.
- `setup/defaults/windows/defaults.ps1` tells Windows the colour set changed after a light or dark setting is applied, so the taskbar redraws without signing out.
- `editors/stm32cubeide/<os>/plugins.txt` lists the WakaTime plugin from the Eclipse update site. The Linux README gives the `p2.director` command that installs it into STM32CubeIDE 2.2.0 without opening the IDE.

### Changed

- The Windows taskbar over the desktop is a plain `#1C1C1C` tint at 65 percent with no blur (TranslucentTB's blur accent at radius 0) instead of acrylic. Acrylic ignores `blur_radius`, so it always blurred.
- Every theme file and pin follows Zacess Themes 0.6.0: the terminal palette, Zed, the JetBrains, Arduino IDE, Obsidian and VS Code packages and the Eclipse, Notepad++, Nextpad++ and Microchip Studio builds. The Nextpad++ check holds every style to 4.5:1 on the current line, the rule 0.6.0 sets for syntax over its visible current line band.
- The selection in every terminal is the strong block with its own text colour that Zacess Themes 0.5.0 ships: Light `#0150b2` with white text, Dark `#4fbdff` with `#121212`, Yellow on Black `#09bcc4` with black, Cream `#7401ca` with `#fdf6e3`, High Contrast Dark `#bf96ff` with black, High Contrast Light `#015f5e` with white, Deep Contrast Dark `#ff70ff` with black and Deep Contrast Light `#990098` with white. The palette's selection floor is 4.5:1, Zacess Themes' own rule for text over a highlight.
- The palette carries the interface tokens the tmux files use (borders, accent, find match) and Yellow on Black's terminal text is white with a yellow cursor, as the release's own terminal files have it.
- A contrast floor for text a program prints on its own background: iTerm2 `Minimum Contrast` 0.5 in every Zacess profile, Kitty `text_fg_override_threshold 4.5 ratio`, Windows Terminal `adjustIndistinguishableColors` set to `always` by the bootstrap, VS Code `terminal.integrated.minimumContrastRatio` pinned at 4.5 and Zed `terminal.minimum_contrast` at 60. Terminal.app, Alacritty and the JetBrains terminal have no such setting.
- Diff markers that do not rest on colour alone: VS Code draws `+` and `-` in the diff editor, striped gutter marks for added and modified lines and the current line across the gutter; Zed keeps its git gutter and current line highlight pinned; Neovim marks the current line and gives each kind of git change its own sign (`+`, `~`, `_`, `‾`, `~_`, `┆`) with the line number coloured.
- The Notepad++, Nextpad++ and Microchip Studio builds read the strong selection pair for selected text from the Zacess Themes 0.5.0 package and keep the editor fill with an older one.
- `mac/tracked.txt` no longer tracks `AppleHighlightColor`, since `zt` sets it.
- On Windows the bootstrap hides dot folders only and keeps dot files shown, showing again any it hid before. Node and Electron apps cannot overwrite a hidden file on Windows (EPERM), so a save to a hidden dot file failed silently.
- Windows pointer size is no longer captured: each PC keeps its own size. The colour and style are still captured.
- On Windows the display now stays on for 60 minutes after Win+L on mains and 15 on battery, so the lock screen and screen saver show. Windows' hidden lock screen timeout had turned it off after a minute.
- `setup/defaults/windows/defaults.ps1` turns the display off at 60 minutes on battery and mains and sleeps at 60 on battery (never on mains), so a screen saver started at 15 minutes runs for a while first.
- The VS Code extension list pins Zacess Themes 0.4.0.
- A file the Mac, Linux and Windows bootstraps replace goes to the Bin (the Recycle Bin on Windows) instead of a backups folder. The Xcode apply script no longer exports a copy of the preferences domain and the Windows Terminal settings are no longer copied before each change.

### Removed

- The temporary forwarding files at the shell profile's old paths (`mac/`, `linux/` and `windows/` at the root) and their CI checks. Re-run the bootstrap on a machine set up before the grouped layout.

### Fixed

- `webstorm`, `phpstorm` and `datagrip` on the Mac run the real program instead of calling themselves. The PowerShell welcome banner only shows in an interactive window. The Windows bootstrap brings a VS Code extension older than its pin up to the pin.
- The four dark tmux theme files are regenerated from the Zacess Themes 0.6.0 palette, which the terminal check found out of date.
- zsh and bash on Linux start without Ubuntu's global compinit audit on every start and without PATH searches through Windows folders under WSL: the new `shell/linux/zshenv` turns the global compinit off and `zshrc` runs it with the audit once a day.
- The JetBrains apply script replaces an older Zacess Themes plugin with the pinned release and the Terminal.app installer updates an existing Zacess profile while Terminal.app is closed. Both used to keep an old copy.
- New PowerShell windows on Windows load the topics as one cached file, rebuilt whenever a topic is added, removed or edited. A bundle that cannot be parsed falls back to the separate files.
- Starship starts from a cached init script made again only after an upgrade or a change to `starship.toml`. The continuation prompt is written into the cache, so Starship is no longer started on every new window.
- The pre-commit hooks split staged file lists on newlines only, so a path with a space is checked as one file instead of being skipped by every check.
- `windows/defaults.ps1 -Plan` no longer applies the power plan timeouts; it only says it would.
- The Mac, Linux and Windows bootstraps link VS Code's global snippets as well as its settings and keybindings. `argv.json` stays VS Code's own file, because VS Code writes each install's crash reporter id into it.
- `zt current` on Windows reads an LTspice ini written entirely as UTF-16, which it had reported as not a Zacess theme.
- Windows Terminal finds Geist Mono: Windows lists the Nerd Font builds as `GeistMono NF` and `GeistMono NFM`, so the long family name the Mac and Linux use made Terminal fall back to its default font.
- The Microchip Studio apply script keeps its temporary theme file until Studio has closed. When an earlier run had already set the environment theme, the script deleted the file before Studio imported it.
- The MATLAB apply script on Windows waits only for MATLAB itself, for at most ten minutes. It used to wait for every process MATLAB started, so a crash reporter left behind after MATLAB exited held the run indefinitely.
- The LTspice apply script on Windows reads an ini that LTspice 26 wrote entirely as UTF-16, which it had reported as having no `[Colors]` section.
- `setup/defaults/windows/defaults.ps1` sets the display and sleep timeouts with `powercfg` instead of leaving them as a step done by hand.
- The Linux bootstrap updates a uv installed as a uv tool with `uv tool upgrade uv`, since `uv self update` only works for uv's own installer.

## [2.0.0] - 2026-10-23

### Added

- Every public config now lives in this one repository, grouped by what it is for. Each folder keeps its own README, guides, accessibility statement and screenshots. Each came from its own repository:

  | Folder | Came from |
  | --- | --- |
  | `setup/mac-bootstrap/` | `zaccesss/mac-bootstrap` |
  | `setup/linux-bootstrap/` | `zaccesss/linux-bootstrap` |
  | `setup/windows-bootstrap/` | `zaccesss/windows-bootstrap` |
  | `setup/defaults/` | `zaccesss/system-defaults` |
  | `terminal/terminal/` | `zaccesss/terminal-config` |
  | `terminal/tmux/` | `zaccesss/tmux-config` |
  | `terminal/cli-tools/` | `zaccesss/cli-tools-config` |
  | `git/gitconfig/` | `zaccesss/git-config` |
  | `git/git-hooks/` | `zaccesss/git-hooks` |
  | `git/ssh/` | `zaccesss/ssh-config` |
  | `editors/vscode/` | `zaccesss/vscode-config` |
  | `editors/zed/` | `zaccesss/zed-config` |
  | `editors/jetbrains/` | `zaccesss/jetbrains-config` |
  | `editors/eclipse/` | `zaccesss/eclipse-config` |
  | `editors/stm32cubeide/` | `zaccesss/stm32cubeide-config` |
  | `editors/xcode/` | `zaccesss/xcode-config` |
  | `editors/neovim/` | `zaccesss/neovim-config` |
  | `apps/raycast/` | `zaccesss/raycast-config` |
  | `apps/rectangle/` | `zaccesss/rectangle-config` |

- A README for each group (`setup`, `shell`, `terminal`, `git`, `editors` and `apps`) and a master README at the root that links them all.
- One CI workflow for the whole repository that runs each folder's checks only when that folder changes, including the macOS, Windows and Ubuntu test jobs. `.github/ABOUT.md` lists every job, form and template.
- Issue forms with a "Which tool?" dropdown and a pull request template with a checklist of every folder.
- Windows screenshots of the PowerShell banner, `cmds`, `gs` and `glog` and the Command Prompt prompt in Zacess Deep Contrast Dark and Light, in the shell README.
- The Zacess themes for eleven more editors, each in its own folder under `editors/` with apply scripts, a validator and its own CI job: `arduino` (Arduino IDE 2), `microchip-studio` (Microchip Studio 7), `kicad`, `vivado`, `processing`, `notepad-plus-plus`, `nextpad-plus-plus`, `thonny`, `matlab`, `ltspice` and `proteus`.
- `apps/obsidian` and `apps/zotero`: the Zacess theme in an Obsidian vault named by the caller or `OBSIDIAN_VAULT` and Zotero's mode and reader theme matched to the Zacess theme.
- `zt` switches STM32CubeIDE and every new editor and app above by running each folder's own apply script while that app is closed. `zt current` reads each one back.
- Temporary forwarding files at the shell profile's old paths (`mac/`, `linux/` and `windows/` at the root) keep a machine working if it pulls before its bootstrap re-runs. Each forwards to `shell/` and prints one line saying to run the bootstrap.
- The three bootstraps end with an Apps stage that runs the apply script of every installed editor and app, printing one line per app. An app that is open, not installed or not started once is skipped and the run carries on. On macOS and Linux the stage uses the theme `zt` last set and `--apps-only` runs it again on its own; on Windows it is the `apps` stage. On macOS Rectangle is offered its config once. Obsidian is applied when `OBSIDIAN_VAULT` names its vault.
- `editors/zed` and `editors/jetbrains` have apply scripts like every other editor folder, each with a validator in CI. Zed's installs the Zacess theme file (the 0.4.0 release, kept in `shared/themes` while the extension store still serves 0.2.1 and removed once the installed extension catches up) and sets the theme in `settings.json`, reusing `zt`'s own theme block and JSON-with-comments editing. JetBrains' installs the Zacess Themes plugin into every IDE with the IDE's own `installPlugins` command (or the pinned release when no launcher is found), copies in the colour schemes, file template, keymap and fonts, sets the theme through `zt`'s own function and points new projects at `~/dev/projects`. The Mac bootstrap's configs stage links Zed's `settings.json`.
- One projects folder for every editor: MATLAB starts in `~/dev/projects/matlab`, Thonny in `~/dev/projects/python`, the Arduino IDE sketchbook is `~/dev/projects/arduino`, the Processing sketchbook is `~/dev/projects/processing`, Microchip Studio puts new projects in `~\dev\projects\avr` and every JetBrains IDE offers `~/dev/projects` for a new project. Each folder is made when it is missing. Moving an existing sketchbook is a step of its own, in the Arduino and Processing READMEs.
- Thonny runs code in its own virtual environment, `~/.venvs/thonny`, made once from Python 3.15 on every OS (Homebrew's `python@3.15` on macOS, the Python install manager on Windows, `uv` or `python3.15` on Linux), so packages from **Tools > Manage packages** stay out of the system Python. The apply script makes it Thonny's interpreter and keeps earlier choices in Thonny's recent list.
- MATLAB's dark theme gets the Zacess syntax, editor and Command Window colours from code. Each theme also has a colour scheme in `editors/matlab/shared/schemes`, applied with `import_scheme` from MathWorks' Color Theme Extensions add-on, which the apply scripts download at a pinned commit and check against its digests. The add-on's template is kept unchanged with its BSD 3-Clause licence, credited in `NOTICE.md`.
- `zt` on Windows switches Microchip Studio too: its apply script's new `-Close` starts Studio, imports the theme and closes it so the colours are saved. `zt current` reads back its dark or light environment theme.
- CI lints `shell/scripts` with ruff, gives the forwarding zshrc files zsh's own syntax check and parses the forwarding PowerShell files. The shell checks also run when `editors/` or `apps/` change, since `zt` calls their apply scripts.
- The Mac Brewfile installs Nextpad++ from its Homebrew cask.
- The `zacess-theme` shell topics name every tool `zt` switches, the shell guide has a `zt` entry and `CONTRIBUTING.md` lists the validators every `editors/` and `apps/` folder is checked with.

### Changed

- The Mac moves to Python 3.15: the Brewfile installs `python@3.15` and the PATH shim points `python` and `pip` at it, so they match `python3`.
- The shell profile, its scripts, guides, journal and screenshots move into `shell/`. `DOTFILES` now points at that folder, so the default is `~/dev/github/repos/dotfiles/shell`. `dot` now asks git whether that folder is inside a clone.
- The three bootstraps clone only this repository and link every config from its folder, instead of cloning a repository per tool. The clone goes to `~/dev/github/repos/dotfiles` (`%USERPROFILE%\dev\github\repos\dotfiles` on Windows), the folder the shell profile already expects, instead of `~/.dotfiles`. `BOOTSTRAP_CONFIG_DIR` still changes the parent folder and every README and guide uses the new path.
- A machine set up by an earlier release is re-pointed when its bootstrap runs again. On Windows that covers the Neovim and Git hooks junctions into an old clone in `~\.dotfiles` (only the clones earlier releases made), the old `zt` folder on the user `PATH`, the old Command Prompt `AutoRun` call and a Windows PowerShell 5.1 profile pointing at the old loader, with tests. `~/.dotfiles` can then be deleted.
- The Processing apply scripts set the sketchbook themselves instead of reading it from `preferences.txt`. The Zotero Windows script's `-Profile` is now `-ProfileDir`, so it no longer shadows PowerShell's own `$PROFILE`.
- `zt` reads the Eclipse themes from `editors/eclipse/theme` in the same clone unless `ZT_ECLIPSE_THEMES` says otherwise.
- The PowerShell profile and the Command Prompt start-up treat a `DOTFILES` that names the clone's root as unset, so a window opened before the move still loads the profile. An elevated PowerShell window moves from System32 to the home folder.
- The Windows bootstrap moves a Windows PowerShell 5.1 profile that points at the old loader to the new one, with a test.
- Python bytecode (`__pycache__` and `*.pyc`) is ignored.
- The root community files (contributing guide, security policy, support, accessibility statement and notice) now cover every folder. The bootstraps stay under the Apache License 2.0 with their own `LICENSE` and `NOTICE.md`; everything else is MIT.

### Fixed

- On macOS, `zt`, `termtheme` and every Mac apply script see an app as open when they run inside its own terminal. macOS `pgrep` leaves out its own ancestors unless given `-a`, so `zt` run from Terminal.app wrote the defaults without switching the open tabs and an apply script run from an IDE's terminal changed settings the IDE then wrote over.
- `zt` on Linux sees a JetBrains IDE installed from a tarball as open, by the paths selector its Java process carries.
- The Linux Thonny script finds a Thonny installed with apt or dnf when `uv`'s Python comes first on `PATH`.
- The Command Prompt start-up only accepts a `DOTFILES` that holds the shell folder's macros, so a window opened before the move no longer loads the root's stand-in.
- Ruff findings in `shell/scripts/games.py`, the Microchip Studio scripts and the Proteus build script.

## [1.0.10] - 2026-10-22

### Added

- The screenshots and clips are recorded again in Zacess Deep Contrast Dark and Light, using the real config in a throwaway demo project.
- `zt` (and `zacess-theme`) on macOS, Linux and Windows switches every installed editor and terminal to one of the eight Zacess themes at once: VS Code, Zed, the JetBrains IDEs, Neovim, Eclipse, Terminal.app, iTerm2, Kitty, Alacritty, Ghostty and Windows Terminal. `zt <theme>` fixes one theme and stops following the system, `zt auto [dark] [light]` follows the system light and dark appearance where a tool can, `zt list` lists the themes and `zt current` reads each tool's setting back. `scripts/zt.py` does the work on macOS and Linux and `windows/scripts/zt.ps1` on Windows, with `zt.cmd` and `zacess-theme.cmd` for Command Prompt.
- Command Prompt setup in `windows/cmd/`: `autorun.cmd` runs from the `AutoRun` value for interactive windows only, sets a prompt and prints the banner in the terminal's 16 colour slots and loads doskey macros made from the PowerShell aliases and short functions by `scripts/build-cmd-macros.py`. `windows/cmd/README.md` lists the functions that stay PowerShell-only and why. `.gitattributes` keeps `.cmd` and `.doskey` files on Windows line endings.

### Changed

- `termtheme` uses the Zacess Deep Contrast Dark and Light profiles and schemes in Terminal.app and Windows Terminal in place of the High Contrast ones.

### Fixed

- `ls` draws other-writable folders like any other folder. On macOS the last two `LSCOLORS` pairs are now bold cyan instead of black or blue on a yellow or green background. On Linux `LS_COLORS` gets `ow` and `tw` set to the machine's own `di` colour. Both were unreadable in every theme.
- `zt` keeps a JSON object that is already spread over several lines (such as Zed's theme setting) in its existing layout and trailing comma, so a settings file only changes where a value really changed.
- `zt` on Linux only treats a running JetBrains IDE launcher as an open IDE, so the Toolbox app running in the background no longer makes it skip the JetBrains theme.

## [1.0.9] - 2026-10-19

### Added

- `copyout <command>`: runs a command, shows its output as normal and copies all of it (output and errors) to the clipboard, then says how many lines were copied. It uses `pbcopy` on macOS, `clip.exe` under WSL, `wl-copy` or `xclip` on other Linux and `Set-Clipboard` on Windows. The command's exit status is kept.
- `logrun <command>`: runs a command with its output shown live and saved to `~/logs/<YYYY-MM-DD_HHMMSS>-<command>.log`, then prints the log's path. The command's exit status is kept.
- Command marks (OSC 133 shell integration) on every platform. Each prompt, command and output is marked, with the exit status of every command that ran, so Windows Terminal, tmux and other terminals that read the marks can jump between commands and select one command's output. Terminal.app keeps its own built-in marks. VS Code uses its own shell integration, so the profile's marks are skipped there. The Windows guide shows the Windows Terminal actions, which live in its own settings.
- zsh is now the default shell on Linux, matching the macOS profile. `linux/zshrc` loads the new `linux/topics-zsh/` port of every topic, keeping the Linux specifics (apt or dnf, `/etc/os-release`, `xdg-open`, Linux paths). `linux/bashrc` stays as the fallback for a machine without zsh. The welcome banner on Linux zsh reads `Shell     zsh <version>` with the same layout and colours as the Mac.
- Typed-command colours on macOS and Linux through zsh-syntax-highlighting, sourced last and silently skipped when the package is absent: known commands, aliases, functions and builtins green, an unknown command red, quoted strings yellow and options cyan, in the normal (not bright) ANSI colours a high contrast palette reads best. `zsh-syntax-highlighting` is now in the Mac Brewfile.
- Windows `paste` (Get-Clipboard) plus `sha256` and `sha512`, which print the lowercase hash then the path, the same as the Mac's.
- Linux `speedtest` and the Swift `sf2` alias (`swift format`).
- `speedtest` runs the installed `speedtest-cli` on macOS and Linux instead of downloading a script on each run. It also hides the tool's Python deprecation notice. The Brewfile installs it on the Mac.
- `games`: a menu of six terminal games (2048, Snake, Blocks, Meteors, Word and a typing test) on every platform, in `scripts/games.py`. Arrows or W and S choose, Enter plays and Q or Esc leaves any game. Best scores are kept per machine.
- `update`: lists everything out of date on the machine (Homebrew, winget, apt or dnf, global npm packages and uv or pipx tools), then upgrades it all only after a yes.
- `sysinfo`: a full system summary through fastfetch on demand, kept out of the banner so new tabs stay fast.
- `DOTFILES_NO_BANNER=1` hides the welcome banner.
- Screenshots and short animations of the config in action, dark and light, in the README's In action section.
- `termtheme` on macOS, Linux and Windows switches the terminal's High Contrast colours: `dark` or `light` pins one, `auto` follows the system's light and dark setting and no argument shows the current mode. It drives Terminal.app (with the login helper for `auto`), Ptyxis and Windows Terminal. Inside OrbStack or WSL it points to the host's terminal instead.
- `docker-clean` on macOS, Linux and Windows: shows Docker's disk use, asks, removes every unused container, image, volume and the build cache, then shows the space again.
- `orbls` and `orbsh` for OrbStack on macOS.
- `typw` to rebuild a Typst document on save, `linkcheck` to check every link under a folder with lychee and `trivyscan` to scan a folder for vulnerable dependencies, leaked secrets and misconfigurations.
- Linux `PATH` entries for swiftly's Swift toolchains, the Flutter SDK and .NET global tools. On WSL without wslview, links open through Windows with `BROWSER=explorer.exe`.
- `ACCESSIBILITY.md`: how the colours, the prompt and the aliases support people with low or monocular vision, colour vision differences and typing fatigue, plus the known gaps.

### Changed

- Under WSL, `BROWSER` is only set to `explorer.exe` when it is not already set. WSL is now recognised by `WSL_DISTRO_NAME` as well as `/proc/version`.
- The zsh syntax highlighting topic is now `37-syntax-highlighting.zsh` on macOS and `38-syntax-highlighting.zsh` on Linux, so it still loads last after the new command marks topic.
- The welcome banner shows in every terminal: editor terminals in VS Code and editors built on it show it too.
- The games share one colour scheme: titles bold cyan, good things green, the next or current thing yellow and danger or mistakes red, with borders and empty cells in the plain text colour. In the typing test, correct letters turn green and the next letter to type is yellow and underlined.
- The welcome banner is plain text with labels and no emoji: a bold cyan heading, then Machine (with the OS), Shell (with its version) and Session (date and time) between line-drawing borders. It lives in one `welcome` function per platform that the profile and `cls` or `refresh` both call.
- The Windows banner uses the normal green and cyan, matching the Mac and Linux, instead of the paler bright variants that `Write-Host` picks.
- The welcome banner's dashed top and bottom lines use the terminal's own text colour instead of bold cyan, so they no longer blend into the cyan welcome line and stay full contrast in light and dark mode.
- `ACCESSIBILITY.md` describes the High Contrast palette in light and dark mode, the four-colour banner and fzf's colours.
- The welcome banner's machine line is magenta on every platform, so each of its 4 lines has its own colour: cyan, green, magenta and yellow.
- macOS and Linux set `RIPGREP_CONFIG_PATH` when `~/.ripgreprc` exists, so ripgrep picks up its defaults file.
- Windows `cmds` pages through `less -RF` (from Git for Windows) when `less` is available, with `LESSCHARSET=utf-8` so the banner's box characters survive. It falls back to plain output otherwise.
- `linux/bashrc` returns early in a non-interactive shell, so a login shell running a single command (`ssh host cmd`, `scp` or `rsync`) no longer loads the profile or prints the banner. `linux/zshrc` only runs for interactive shells.
- The font advice in the platform guides and `ACCESSIBILITY.md` now matches the real setup: the prompt needs no Nerd Font, only the Node.js module shows a Nerd Font glyph and the Mac's terminals run Monaco 12 in iTerm2 and Warp's default font at size 13.
- `ACCESSIBILITY.md`: a note that the settings are preferences and a link to the shared accessibility statement.
- Tidied code comments and the contributor guide.

### Fixed

- Linux zsh and bash no longer print `nvm not found` before every `node`, `npm` or `npx` call on a machine without nvm, where Node comes from apt, dnf or another manager. With no `$NVM_DIR/nvm.sh`, no `node`, `npm` or `npx` wrappers are defined and only `nvm` and its helpers remain to print the install hint, matching macOS.
- macOS no longer prints `nvm not found` (or `command not found: _nvm_load`) before every `node`, `npm` or `npx` call on a Mac where Node comes from Homebrew. With no `$NVM_DIR/nvm.sh`, no `node`, `npm` or `npx` wrappers are defined and only `nvm` and its helpers remain to print the install hint. Where nvm is installed, its default Node is put on `PATH` at shell start the same way as on Linux, the wrappers are only defined when no default resolves and `nvmls`, `nvmuse` and the other helpers no longer disappear after the first nvm call.
- Linux zsh and bash put nvm's default Node on `PATH` at shell start without loading nvm, reading `$NVM_DIR/alias/default` the way nvm does (aliases such as `lts/*` and partial versions such as `26` resolve to the highest installed match). `node`, `npm` and `npx` are now real binaries, so a process started through `sh` no longer fails with `node: not found`. The lazy wrappers for them are only defined when no default resolves. `nvmls`, `nvmuse` and the other helpers no longer disappear after the first nvm call and a missing `bash_completion` no longer makes the first `nvm` call fail.
- Opening Windows PowerShell 5.1 with the profile no longer prints a screen of parse errors. The topic files use PowerShell 7 syntax (the backtick-e escape and `&&`), so the loader now stops before loading any topic when the major version is below 7 and prints one dim line: `dotfiles need PowerShell 7: run pwsh`.
- Windows `Reload-Profile` and `dot` keep what the reload defines. Dot-sourcing the profile inside a function only reached that function's own scope, so new or changed functions, aliases and variables were lost as soon as it returned. Both now run the loader through `Import-ProfileGlobal`, which copies them into the global scope.
- The PowerShell loader snippet in the Windows and documentation guides matches the real loader: it reads the topic files from the `DOTFILES` path, not `$PSScriptRoot`.
- Windows `dot` leaves a `$PROFILE` that is a one-line pointer to the repo's loader in place instead of overwriting it with a full copy, matching how macOS and Linux treat a linked profile. The Windows guide shows the pointer form.
- Loading the Windows profile in `pwsh` on macOS or Linux no longer prints registry errors from the welcome banner.
- Windows adds LibreOffice's `program` folder to the end of `PATH` when it is installed, so `soffice` is found.
- Linux zsh and bash share one `ssh-agent` on `~/.ssh/agent.sock` instead of `ssha` starting a new agent each time. It starts only when no agent answers there and is skipped when `SSH_AUTH_SOCK` already reaches a live agent. A key added once stays loaded for every terminal. Keys are never added automatically.
- The topic file counts in the guides and READMEs match the real files. The SSH and `dot` rows in the command reference describe what the commands really do.
- Starship waits up to 500 ms to scan a folder instead of 100 ms, so the home folder no longer prints a scan timeout warning above the prompt.
- Windows gains the `speedtest` command its `cmds` help already listed, through `speedtest-cli` or Ookla's `speedtest`. It prints an install hint when neither is present.
- `dot` on macOS and Linux no longer copies the profile onto itself when `~/.zshrc` or `~/.bashrc` is already a link to the repo copy.
- fzf on Linux and Windows uses terminal colour names, so it follows the terminal's light or dark palette. Its file list uses `rg` when ripgrep is installed.
- Inside an OrbStack machine, the Linux prompt no longer shows the user and machine name on every line, since OrbStack's shell arrives over a loopback SSH connection. A real SSH session still shows both.
- Starship waits up to 100 ms to scan a folder, so a large folder such as the home folder no longer prints a timeout warning above the prompt.
- `rg` runs ripgrep again on every platform. The Rails generator moved to `rgen`, the clipboard paste to `clippaste`, Elixir to `elx` and the R docs builder to `rdocs`, so none of them hide a real command. `rg2` stays as an extra name for ripgrep.
- On Linux, `ping4` keeps its real meaning (IPv4 only) while still sending four pings.
- The Linux prompt no longer tags every line with the container type inside WSL and other containers.
- The `cmds` reference lists the real Rails aliases (`rdm`, `rgen`, `rdreset`) on macOS, Linux and Windows, in place of names that no longer existed.
- Leaving the Windows `cmds` pager with Q no longer prints an error.
- Linux `digga` and `dns` give a friendly install hint when `dig` is missing, matching `sysinfo`'s fastfetch hint.
- `bdump` no longer passes `--describe`, which `brew bundle dump` has dropped since descriptions are now its default.
- The Starship Node.js module now uses the plain-text symbol `"node "` in every platform's `starship.toml`, so the whole prompt reads correctly without a Nerd Font. The font tips match.
- The README and `guides/new-device.md` now clone to `~/dev/github/repos/dotfiles`, the path every loader defaults to, with a note on setting `DOTFILES` for any other location.
- `mac/Brewfile` now installs `php@8.4`, `composer` and `avr-gcc@14` from the `osx-cross/avr` tap, with a `guides/mac.md` note on putting the keg-only PHP 8.4 on `PATH`.
- Linux JetBrains launchers now support manual IDE installations under `~/dev/tools/jetbrains` while retaining JetBrains Toolbox shell-script support

## [1.0.8] - 2026-09-18

### Added

- `zipf` in `07-utilities`, across mac, linux and windows, zipping a file or folder into a same-named `.zip`. The counterpart to `extract` in `08-community`, which already unpacks a zip among other archive formats but had no equivalent for creating one
- `zipf` documented in `guides/documentation.md`, the three platform guides and `cmds`

---

## [1.0.7] - 2026-09-17

### Added

- A red team and blue team section in `12-security`, authorised testing only: `revshell`, `listener`, `hydra-ssh`, `fuzz`, `subenum` and `msfq` for red team; `authfails`, `conns`, `fwstatus`, `sigcheck` and `lastlogins` for blue team
- Sixteen more quick-launcher functions: `vt`, `shodan`, `cve`, `maps`, `yt`, `wiki`, `godocs`, `crates`, `dockerhub`, `packagist`, `rubygems`, `nugetpkg`, `mvnrepo`, `hexpm`, `archive` and `bundlephobia`, matching every language ecosystem I already have tooling for
- All of the above documented in `guides/documentation.md`, the three platform guides and the `cmds` cheat-sheet

## [1.0.6] - 2026-09-17

### Added

- `battery`, `flushdns` and `please`, three genuine gaps found while auditing the existing alias set
- `kn` and `kgpw`, switching the current namespace and watching pods live, since `kuse` only switched context and `kgp` only listed pods once
- `dip`, printing a container's IP address in one step
- Eleven quick-launcher functions sharing one internal helper: `gh-search`, `so`, `mdn`, `npmjs`, `pypi`, `caniuse`, `leetcode`, `neetcode`, `codeforces`, `translate`, `regex101`
- All of the above documented in `guides/documentation.md`, the three platform guides and the `cmds` cheat-sheet

## [1.0.5] - 2026-09-17

### Changed

- `reload-profile` now hard-clears the terminal, including scrollback, before re-sourcing the profile, so the reprinted welcome banner lands on a clean screen instead of stacking under the old one

## [1.0.4] - 2026-09-17

### Added

- `gclean-branches`, deleting every local branch already merged into main in one step, a gap found while writing git-practice-lab's daily-workflow module since `gdone` only takes one branch at a time
- `google`, opening the default browser straight to a Google search for the given query, on every platform

## [1.0.3] - 2026-09-17

### Added

- `.github/ISSUE_TEMPLATE/config.yml` disabling the blank issue option, pointing to the security policy and my contact channels instead

## [1.0.2] - 2026-09-15

### Changed

- Issue templates converted from markdown frontmatter to YAML issue forms

## [1.0.1] - 2026-09-08

### Added

- `mac/Brewfile`, every Homebrew formula, cask and global npm package on this machine, produced by
  `brew bundle dump --describe --no-vscode` (VS Code extensions excluded, the separate `.vscode`
  repo's own `extensions.txt` is the source of truth for those)
- `bbundle`/`bdump` aliases in `16-brew.zsh` to install from and regenerate `mac/Brewfile`

---

## [1.0.0] - 2026-08-19

### Added

- Initial public release: cross-platform aliases and functions for macOS, Linux and Windows, a
  shared Starship prompt theme, install and setup guides and the topic-file structure that
  keeps each platform folder self-contained.
