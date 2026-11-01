#!/usr/bin/env python3
"""zt: switch every installed editor and terminal to one Zacess theme at once (macOS and Linux).

    zt <theme>                     fix that theme everywhere and stop following the system
    zt <theme> --all               the same here, then on every other device as a terminal opens there
    zt undo [--all]                back to the theme before the last change (on every device with --all)
    zt auto [dark] [light]         follow the system light and dark appearance, Deep Contrast by default
    zt list                        the eight themes and their short names
    zt current                     the mode zt last set and what each tool is on now
    zt doctor                      every installed theme file against the repo copy, exit 1 on drift
    zt highlight [default]         the system text highlight again from the theme or the system's own back
    zt sync                        apply a change sent with --all from another device (run at shell start)
    zt pin <app> <theme>           keep one app on its own theme while the rest follow zt; the theme can
                                   also be auto [dark] [light] or the app's own: default, default-dark or
                                   default-light. "terminals" as the app pins every terminal app at once
    zt unpin <app|terminals|--all> the app follows zt again, switched to the zt state straight away
    zt current terminals           what each terminal app is on, with any pins (termtheme shows this)

Each tool is edited in place and only for its theme setting; a tool that is not installed is skipped.
Tools that keep settings in memory (JetBrains IDEs, Eclipse, STM32CubeIDE, KiCad, Processing, Nextpad++,
Vivado, Arduino IDE, Thonny, MATLAB, LTspice, Zotero and Obsidian) are only changed while they are closed,
since they write their settings back on exit. tmux takes its colours from a theme file linked into the
state folder and the system text highlight (macOS, KDE Plasma or GNOME) takes the theme's selection
colour, read from the generated terminal theme. Pins live in the pins file beside the state file and
every switch, undo and sync runs a pinned app with its pin. Windows has its own version in
windows/scripts/zt.ps1.
"""

import concurrent.futures
import json
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

THEMES = [
    # id, short name, full name, appearance
    ("deep-contrast-dark", "deep-dark", "Zacess Deep Contrast Dark", "dark"),
    ("deep-contrast-light", "deep-light", "Zacess Deep Contrast Light", "light"),
    ("high-contrast-dark", "hc-dark", "Zacess High Contrast Dark", "dark"),
    ("high-contrast-light", "hc-light", "Zacess High Contrast Light", "light"),
    ("dark", "dark", "Zacess Dark", "dark"),
    ("light", "light", "Zacess Light", "light"),
    ("cream", "cream", "Zacess Cream", "light"),
    ("yellow-on-black", "yellow", "Zacess Yellow on Black", "dark"),
]
DEFAULT_DARK = "deep-contrast-dark"
DEFAULT_LIGHT = "deep-contrast-light"

HOME = Path.home()
MAC = platform.system() == "Darwin"
XDG_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
XDG_STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local" / "state")
STATE_FILE = XDG_STATE / "zacess" / "theme"
# the theme left for MATLAB's next start, applied by its startup.m and then removed
MATLAB_PENDING = XDG_STATE / "zacess" / "matlab-theme"
# the state before the last change, for zt undo. a second undo swaps back, so it also redoes
PREVIOUS_FILE = XDG_STATE / "zacess" / "previous"
# --all: one push at a time in a synced folder, read by every device. all-seen is the last push this
# device handled and all-applied the state it had before applying it, so zt undo --all can return
# each device to its own previous theme
ALL_SEEN = XDG_STATE / "zacess" / "all-seen"
ALL_APPLIED = XDG_STATE / "zacess" / "all-applied"


def shared_file():
    """zt-all.json in the synced folder (None on a device with no such folder)."""
    if os.environ.get("ZACESS_SHARED_DIR"):
        return Path(os.environ["ZACESS_SHARED_DIR"]) / "zt-all.json"
    # Linux syncs it with the OneDrive client into ~/OneDrive
    onedrive = HOME / "Library" / "CloudStorage" / "OneDrive-Personal" if MAC else HOME / "OneDrive"
    return onedrive / ".zacess" / "zt-all.json" if onedrive.is_dir() else None


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def write_atomic(path, text):
    # a temp file in the same folder then a rename, so a syncing device never reads half a file
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{uuid.uuid4().hex}")
    temp.write_text(text, encoding="utf-8")
    os.replace(temp, path)


def current_state():
    return STATE_FILE.read_text().strip() if STATE_FILE.exists() else ""
ECLIPSE_WORKSPACE = Path(os.environ.get("ZT_ECLIPSE_WORKSPACE") or HOME / "eclipse-workspace")
# editors/eclipse and editors/stm32cubeide sit beside shell/ in the same clone (shell/scripts/zt.py)
REPO_ROOT = Path(__file__).resolve().parents[2]
ECLIPSE_THEMES = Path(os.environ.get("ZT_ECLIPSE_THEMES") or REPO_ROOT / "editors" / "eclipse" / "theme")
STM32_THEMES = Path(os.environ.get("ZT_STM32_THEMES") or REPO_ROOT / "editors" / "stm32cubeide" / "shared" / "theme")
EDITORS = REPO_ROOT / "editors"
APPS = REPO_ROOT / "apps"
TERMINAL_HELPER = HOME / ".local" / "bin" / "terminal-appearance"
TERMINAL_AGENT = "local.terminal-config.appearance"
TERMINAL_AGENT_PLIST = HOME / "Library" / "LaunchAgents" / f"{TERMINAL_AGENT}.plist"
ITERM_PROFILES = HOME / "Library" / "Application Support" / "iTerm2" / "DynamicProfiles"
ITERM_AUTO_GUID = str(uuid.uuid5(uuid.NAMESPACE_URL, "terminal-config/zacess-auto"))

if sys.stdout.isatty() and not os.environ.get("NO_COLOR"):
    # terminal colour slots rather than fixed colours, so the output reads in every theme
    OK, SKIP, DRIFT, BOLD, RESET = "\033[32m", "\033[33m", "\033[31m", "\033[1m", "\033[0m"
else:
    OK = SKIP = DRIFT = BOLD = RESET = ""


class Theme:
    def __init__(self, row):
        self.id, self.short, self.name, self.appearance = row

    @property
    def dark(self):
        return self.appearance == "dark"


def find_theme(word):
    key = word.strip().lower().replace(" ", "-")
    key = re.sub(r"^zacess-", "", key)
    for row in THEMES:
        if key in (row[0], row[1]):
            return Theme(row)
    return None


# the tools run at once (see main), so each one collects its lines here and they are printed
# afterwards in TOOLS order, never interleaved
_lines = threading.local()


def report(tool, message, changed=True):
    colour = OK if changed else SKIP
    line = f"  {BOLD}{tool:<16}{RESET} {colour}{message}{RESET}"
    buffer = getattr(_lines, "buffer", None)
    if buffer is None:
        print(line)
    else:
        buffer.append(line)


def run(*args, **kwargs):
    return subprocess.run(list(args), capture_output=True, text=True, **kwargs)


def pgrep(*args):
    # macOS pgrep leaves out its own ancestors unless given -a, so an app whose built-in terminal
    # runs zt (Terminal.app, an IDE) would look closed. procps pgrep on Linux has no such exclusion
    # and its -a lists command lines instead
    return run("pgrep", *(["-a"] if MAC else []), *args).returncode == 0


def running(pattern):
    return pgrep("-if", pattern)


def system_is_dark():
    if MAC:
        return run("defaults", "read", "-g", "AppleInterfaceStyle").stdout.strip() == "Dark"
    if "KDE" in os.environ.get("XDG_CURRENT_DESKTOP", "").upper():
        for tool in ("kreadconfig6", "kreadconfig5"):
            if shutil.which(tool):
                scheme = run(tool, "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme").stdout
                return "dark" in scheme.lower()
    if shutil.which("gsettings"):
        out = run("gsettings", "get", "org.gnome.desktop.interface", "color-scheme")
        if out.returncode == 0:
            return "dark" in out.stdout
    # with no desktop to ask (a server, WSL or OrbStack) dark is the default
    return True


# ---------------------------------------------------------------------------------------------------
# JSON with comments (VS Code and Zed both allow them): values are swapped in the text itself, so
# comments, key order and spacing stay as they were. the result is parsed before it is saved
# ---------------------------------------------------------------------------------------------------

def strip_jsonc(text):
    out, i, in_string = [], 0, False
    while i < len(text):
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\":
                out.append(text[i + 1])
                i += 1
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
            out.append(c)
        elif text.startswith("//", i):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            i = text.index("*/", i) + 1
        else:
            out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def parse_jsonc(text):
    return json.loads(strip_jsonc(text) or "{}")


VALUE = r'(?:"(?:[^"\\]|\\.)*"|true|false|null|-?\d+(?:\.\d+)?|\{[^{}]*\})'


def set_key(text, key, value):
    pattern = re.compile(r'("' + re.escape(key) + r'"\s*:\s*)' + VALUE)
    match = pattern.search(text)
    if match:
        line_start = text.rfind("\n", 0, match.start()) + 1
        pad = re.match(r"[ \t]*", text[line_start:]).group(0)
        old = match.group(0)[len(match.group(1)):]
        rendered = json.dumps(value) if not isinstance(value, dict) else render_object(value, pad, old)
        return text[:match.start()] + match.group(1) + rendered + text[match.end():]
    rendered = json.dumps(value) if not isinstance(value, dict) else render_object(value)
    # a new key goes first, after the opening brace, with the file's own indent
    indent = re.search(r'\n([ \t]+)"', text)
    pad = indent.group(1) if indent else "    "
    brace = text.index("{")
    return text[:brace + 1] + f'\n{pad}"{key}": {rendered},' + text[brace + 1:]


def render_object(value, pad="", old=""):
    # an object that was already spread over lines keeps that shape (and its trailing comma), so a linked
    # settings file in a config repo only changes where a value really changed
    if "\n" not in old:
        inner = ", ".join(f"{json.dumps(k)}: {json.dumps(v)}" for k, v in value.items())
        return "{ " + inner + " }"
    inside = re.search(r"\n([ \t]+)\S", old)
    step = inside.group(1) if inside else pad + "  "
    trailing = "," if re.search(r",\s*}\s*$", old) else ""
    lines = [f"{step}{json.dumps(k)}: {json.dumps(v)}" for k, v in value.items()]
    return "{\n" + ",\n".join(lines) + trailing + "\n" + pad + "}"


def edit_jsonc(path, changes):
    text = path.read_text()
    original = text
    for key, value in changes.items():
        text = set_key(text, key, value)
    parse_jsonc(text)
    if text != original:
        # writing through the path keeps a symlinked settings file linked
        with open(path, "w") as f:
            f.write(text)
    return text != original


# ---------------------------------------------------------------------------------------------------
# the tools
# ---------------------------------------------------------------------------------------------------

def vscode_settings_root():
    return HOME / "Library" / "Application Support" if MAC else XDG_CONFIG


def vscode_settings():
    return vscode_settings_root() / "Code" / "User" / "settings.json"


def vscode(fixed, dark, light, now):
    path = vscode_settings()
    if not path.exists():
        return report("VS Code", "not installed, skipped", False)
    if fixed:
        edit_jsonc(path, {"workbench.colorTheme": fixed.name, "window.autoDetectColorScheme": False})
        return report("VS Code", fixed.name)
    edit_jsonc(path, {"workbench.colorTheme": now.name, "window.autoDetectColorScheme": True,
                      "workbench.preferredDarkColorTheme": dark.name,
                      "workbench.preferredLightColorTheme": light.name})
    report("VS Code", f"following the system: {dark.name} or {light.name}")


def zed_theme(current, fixed, dark, light):
    """The theme block for Zed's settings.json. editors/zed/shared/apply.py writes the same block."""
    pair = current if isinstance(current, dict) else {}
    if fixed:
        # a fixed theme keeps the other half of the pair, so switching back to auto needs no second step
        return {"mode": fixed.appearance,
                "light": fixed.name if not fixed.dark else pair.get("light", Theme(THEMES[1]).name),
                "dark": fixed.name if fixed.dark else pair.get("dark", Theme(THEMES[0]).name)}
    return {"mode": "system", "light": light.name, "dark": dark.name}


def zed(fixed, dark, light, now):
    path = XDG_CONFIG / "zed" / "settings.json"
    if not path.exists():
        return report("Zed", "not installed, skipped", False)
    current = parse_jsonc(path.read_text()).get("theme")
    edit_jsonc(path, {"theme": zed_theme(current, fixed, dark, light)})
    report("Zed", fixed.name if fixed else f"following the system: {dark.name} or {light.name}")


JETBRAINS_CONFIG = HOME / "Library" / "Application Support" / "JetBrains" if MAC else XDG_CONFIG / "JetBrains"
# only the IDE launchers: the Toolbox app and its jetbrainsd helper run all the time. A tarball
# install's bin/<ide>.sh execs java, so on Linux that process is known by the paths selector every
# IntelliJ platform JVM carries
JETBRAINS_PROCESS = (r"/Applications/.*\.app/Contents/MacOS/(idea|pycharm|webstorm|clion|dataspell|goland|"
                     r"phpstorm|rubymine|rustrover|rider|studio)" if MAC else
                     r"/bin/(idea|pycharm|webstorm|clion|dataspell|goland|phpstorm|rubymine|rustrover|rider|studio)(\.sh)?( |$)"
                     r"|-Didea\.paths\.selector=")


def jetbrains_dirs(base=None):
    """Each IDE's config folder (one that has options/) and whether the Zacess Themes plugin is in it."""
    base = base or JETBRAINS_CONFIG
    if not base.is_dir():
        return []
    dirs = []
    for d in sorted(base.iterdir()):
        if not (d / "options").is_dir():
            continue
        plugin_places = [d / "plugins" / "zacess-themes",
                         HOME / ".local" / "share" / "JetBrains" / d.name / "zacess-themes"]
        dirs.append((d, any(p.is_dir() for p in plugin_places)))
    return dirs


def jetbrains_theme_files(d, fixed, dark, light, shown):
    """Writes one IDE's laf.xml and colors.scheme.xml. editors/jetbrains/shared/apply.py calls this too."""
    laf = d / "options" / "laf.xml"
    root = ET.parse(laf).getroot() if laf.exists() else ET.Element("application")
    comp = root.find("component[@name='LafManager']")
    if comp is None:
        comp = ET.SubElement(root, "component", name="LafManager")
    for child in list(comp):
        # a remembered scheme per theme would win over the theme's own scheme
        if child.tag in ("laf", "lafs-to-previous-schemes") or (not fixed and child.tag.startswith("preferred-")):
            comp.remove(child)
    comp.set("autodetect", "false" if fixed else "true")
    ET.SubElement(comp, "laf", themeId=f"zacess-{shown.id}")
    if not fixed:
        ET.SubElement(comp, "preferred-light-laf", themeId=f"zacess-{light.id}")
        ET.SubElement(comp, "preferred-dark-laf", themeId=f"zacess-{dark.id}")
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(laf, encoding="unicode")
    scheme = d / "options" / "colors.scheme.xml"
    root = ET.parse(scheme).getroot() if scheme.exists() else ET.Element("application")
    comp = root.find("component[@name='EditorColorsManagerImpl']")
    if comp is None:
        comp = ET.SubElement(root, "component", name="EditorColorsManagerImpl")
    node = comp.find("global_color_scheme")
    if node is None:
        node = ET.SubElement(comp, "global_color_scheme")
    node.set("name", shown.name)
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(scheme, encoding="unicode")


def jetbrains(fixed, dark, light, now):
    dirs = jetbrains_dirs()
    if not dirs:
        return report("JetBrains", "not installed, skipped", False)
    if running(JETBRAINS_PROCESS):
        return report("JetBrains", "an IDE is open, skipped: close it and run zt again", False)
    shown = fixed or now
    for d, has_plugin in dirs:
        if not has_plugin:
            report(f"  {d.name}", "Zacess Themes plugin not installed, skipped", False)
            continue
        jetbrains_theme_files(d, fixed, dark, light, shown)
        report(f"  {d.name}", shown.name if fixed else f"Sync with OS: {dark.name} or {light.name}")


def neovim(fixed, dark, light, now):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text((fixed.id if fixed else f"auto {dark.id} {light.id}") + "\n")
    if not shutil.which("nvim"):
        return report("Neovim", "not installed, theme saved for later", False)
    reloaded = 0
    for sock in nvim_sockets():
        # the same apply() its focus autocmd runs, which rereads the state file written above. A
        # socket left by a Neovim that has gone fails at once. A timeout covers one that hangs
        try:
            done = subprocess.run(["nvim", "--headless", "--server", str(sock), "--remote-expr",
                                   "execute('lua require([[config.theme]]).apply()')"],
                                  capture_output=True, timeout=5)
            reloaded += done.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            pass
    when = f"applied to {reloaded} open Neovim(s), the rest on start" if reloaded else "on next focus or start"
    report("Neovim", (fixed.name if fixed else "following the system") + ", " + when)


def nvim_sockets():
    """Every running Neovim's socket: nvim.<pid>.0 in $XDG_RUNTIME_DIR on Linux or in a folder under
    $TMPDIR on macOS."""
    found = set()
    for root in filter(None, (os.environ.get("XDG_RUNTIME_DIR"), os.environ.get("TMPDIR"), "/tmp")):
        base = Path(root)
        found.update(base.glob("nvim.*.0"))
        found.update(base.glob("nvim.*/*/nvim.*.0"))
    return sorted(found)


def workspace_settings(workspace):
    return workspace / ".metadata" / ".plugins" / "org.eclipse.core.runtime" / ".settings"


def stm32_workspace():
    # STM32CubeIDE names its default workspace after its own version, so the newest one it has
    # opened is the one in use
    if os.environ.get("ZT_STM32_WORKSPACE"):
        return Path(os.environ["ZT_STM32_WORKSPACE"])
    found = [p for p in (HOME / "STM32CubeIDE").glob("workspace_*") if (p / ".metadata").is_dir()]
    return max(found, key=lambda p: p.stat().st_mtime) if found else None


def eclipse(fixed, dark, light, now):
    eclipse_like("Eclipse", ECLIPSE_WORKSPACE, ECLIPSE_THEMES,
                 r"/eclipse( |$)|Eclipse.*\.app/Contents/MacOS/eclipse", fixed, now)


def stm32cubeide(fixed, dark, light, now):
    workspace = stm32_workspace()
    if workspace is None:
        return report("STM32CubeIDE", "no workspace, skipped", False)
    eclipse_like("STM32CubeIDE", workspace, STM32_THEMES,
                 r"STM32CubeIDE\.app/Contents/MacOS|/stm32cubeide( |$)", fixed, now)


# Eclipse and STM32CubeIDE (built on Eclipse) keep the theme as plain preference files in a
# workspace, written back from memory on exit, so both are changed only while closed
def eclipse_like(label, workspace, themes, process, fixed, now):
    settings = workspace_settings(workspace)
    if not settings.is_dir():
        return report(label, "no workspace, skipped", False)
    if running(process):
        return report(label, "open, skipped: quit it and run zt again", False)
    theme = fixed or now
    epfs = [themes / f"{theme.name}.epf", themes / f"{theme.name} borders.epf"]
    if not epfs[0].exists():
        return report(label, f"no theme files in {themes}, skipped", False)
    fragments = {"org.eclipse.e4.ui.css.swt.theme": {
        "themeid": "org.eclipse.e4.ui.css.theme.e4_dark" if theme.dark else "org.eclipse.e4.ui.css.theme.e4_default"}}
    for epf in epfs:
        if not epf.exists():
            continue
        for line in epf.read_text().splitlines():
            if not line.startswith("/instance/") or "=" not in line:
                continue
            plugin, _, rest = line[len("/instance/"):].partition("/")
            key, _, value = rest.partition("=")
            fragments.setdefault(plugin, {})[key] = value
    for plugin, keys in fragments.items():
        target = settings / f"{plugin}.prefs"
        lines = target.read_text().splitlines() if target.exists() else ["eclipse.preferences.version=1"]
        done = set()
        out = []
        for line in lines:
            key = line.split("=", 1)[0] if "=" in line else None
            if key in keys:
                if key not in done:
                    out.append(f"{key}={keys[key]}")
                    done.add(key)
                continue
            out.append(line)
        out += [f"{k}={v}" for k, v in keys.items() if k not in done]
        target.write_text("\n".join(out) + "\n")
    note = "" if fixed else f" ({label} cannot follow the system, so this matches it now)"
    report(label, theme.name + note)


def set_terminal_profile(name, basic_too=False):
    """Terminal.app's default, startup and open Zacess tabs on one profile, with the switching agent stopped.
    Tabs on the Basic profile are left alone unless basic_too, which undoing a default pin sets, since
    a Basic tab is otherwise someone's own choice."""
    uid = os.getuid()
    run("launchctl", "bootout", f"gui/{uid}/{TERMINAL_AGENT}")
    if TERMINAL_AGENT_PLIST.exists():
        TERMINAL_AGENT_PLIST.unlink()
    if pgrep("-x", "Terminal"):
        script = f'''tell application "Terminal"
            set default settings to settings set "{name}"
            set startup settings to settings set "{name}"
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        set n to name of current settings of t
                        if n starts with "Zacess" or n starts with "High Contrast"{' or n is "Basic"' if basic_too else ''} then set current settings of t to settings set "{name}"
                    end repeat
                end try
            end repeat
        end tell'''
        run("osascript", "-e", script)
    else:
        run("defaults", "write", "com.apple.Terminal", "Default Window Settings", "-string", name)
        run("defaults", "write", "com.apple.Terminal", "Startup Window Settings", "-string", name)


def terminal_app(fixed, dark, light, now):
    if not MAC:
        return
    profiles = run("defaults", "read", "com.apple.Terminal", "Window Settings").stdout
    wanted = fixed or now
    if f'"{wanted.name}" =' not in profiles:
        return report("Terminal.app", "Zacess profiles not installed (run terminal/mac/install.sh), skipped", False)
    # undoing a default pin hands back the Basic tabs that pin made
    set_terminal_profile(wanted.name, basic_too=getattr(_lines, "undo_default", False))
    if fixed:
        return report("Terminal.app", fixed.name)
    if f'"{dark.name}" =' not in profiles or f'"{light.name}" =' not in profiles:
        return report("Terminal.app", f"{now.name}; the pair's profiles are not all installed, so it stays fixed", False)
    if not TERMINAL_HELPER.exists():
        return report("Terminal.app", f"{now.name}; the switching helper is missing (run terminal/mac/install.sh)", False)
    TERMINAL_AGENT_PLIST.parent.mkdir(parents=True, exist_ok=True)
    TERMINAL_AGENT_PLIST.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>{TERMINAL_AGENT}</string>
    <key>ProgramArguments</key><array><string>{TERMINAL_HELPER}</string><string>{dark.name}</string><string>{light.name}</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
''')
    run("launchctl", "bootstrap", f"gui/{os.getuid()}", str(TERMINAL_AGENT_PLIST))
    report("Terminal.app", f"following the system: {dark.name} or {light.name}")


def iterm_auto_profile(profiles, dark, light):
    """The Zacess Auto profile: the pair's colours as separate light and dark sets, plus the contrast floor."""
    auto = {"Name": "Zacess Auto", "Guid": ITERM_AUTO_GUID, "Dynamic Profile Parent Name": "Default",
            "Use Separate Colors for Light and Dark Mode": True, "Use Bright Bold": False}
    for theme, suffix in ((dark, " (Dark)"), (light, " (Light)")):
        for key, value in profiles[theme.name].items():
            if key.endswith("Color"):
                auto[key + suffix] = value
    # the floor is not a colour, so it is carried over by name
    if "Minimum Contrast" in profiles[dark.name]:
        auto["Minimum Contrast"] = profiles[dark.name]["Minimum Contrast"]
    return auto


def iterm2(fixed, dark, light, now):
    if not MAC:
        return
    source = ITERM_PROFILES / "zacess.json"
    if not source.exists():
        installed = Path("/Applications/iTerm.app").exists() or (HOME / "Applications" / "iTerm.app").exists()
        return report("iTerm2", "Zacess profiles not installed, skipped" if installed else "not installed, skipped", False)
    profiles = {p["Name"]: p for p in json.loads(source.read_text())["Profiles"]}
    auto_file = ITERM_PROFILES / "zacess-auto.json"
    if fixed:
        guid = profiles[fixed.name]["Guid"]
        if auto_file.exists():
            auto_file.unlink()
    else:
        auto_file.write_text(json.dumps({"Profiles": [iterm_auto_profile(profiles, dark, light)]}, indent=2) + "\n")
        guid = ITERM_AUTO_GUID
    run("defaults", "write", "com.googlecode.iterm2", "Default Bookmark Guid", "-string", guid)
    note = " (iTerm2 is open: new windows use it after a restart)" if pgrep("-x", "iTerm2") else ""
    report("iTerm2", (fixed.name if fixed else f"Zacess Auto: {dark.name} or {light.name}") + note)


def kitty(fixed, dark, light, now):
    folder = Path(os.environ.get("KITTY_CONFIG_DIRECTORY") or XDG_CONFIG / "kitty")
    conf = folder / "kitty.conf"
    if not conf.exists() or not shutil.which("kitty") and not Path("/Applications/kitty.app").exists():
        return report("Kitty", "not installed, skipped", False)
    wanted = fixed or dark
    if not (folder / f"zacess-{wanted.id}.conf").exists():
        return report("Kitty", "Zacess theme files not in the Kitty folder, skipped", False)
    text = conf.read_text()
    line = f"include zacess-{wanted.id}.conf"
    if re.search(r"^include\s+zacess-[\w-]+\.conf\s*$", text, flags=re.M):
        text = re.sub(r"^include\s+zacess-[\w-]+\.conf\s*$", line, text, count=1, flags=re.M)
    else:
        text = text.rstrip("\n") + f"\n{line}\n"
    conf.write_text(text)
    autos = {"dark-theme.auto.conf": dark, "light-theme.auto.conf": light, "no-preference-theme.auto.conf": dark}
    for name, theme in autos.items():
        target = folder / name
        if fixed:
            # only files zt wrote are removed, recognised by the theme name on their first line
            if target.exists() and target.read_text().startswith("# Zacess"):
                target.unlink()
        else:
            target.write_text((folder / f"zacess-{theme.id}.conf").read_text())
    # kitty reloads its config on SIGUSR1
    run("pkill", "-USR1", "-x", "kitty")
    report("Kitty", fixed.name if fixed else f"following the system: {dark.name} or {light.name}")


# what a default pin leaves on the emptied import line, so switching back can put the import there
ALACRITTY_MARK = "# zacess: own colours, zt puts the theme import back here"


def alacritty(fixed, dark, light, now):
    conf = XDG_CONFIG / "alacritty" / "alacritty.toml"
    if not conf.exists():
        return report("Alacritty", "not installed, skipped", False)
    wanted = fixed or now
    text = conf.read_text()
    if not re.search(r"zacess-[\w-]+\.toml", text):
        # a default pin left the marker below in place of the import, so the import goes back there
        if ALACRITTY_MARK not in text:
            return report("Alacritty", "no Zacess import in alacritty.toml, skipped", False)
        text = re.sub(r"^import\s*=\s*\[\s*\]\s*" + re.escape(ALACRITTY_MARK) + r"[^\n]*$",
                      f'import = ["zacess-{wanted.id}.toml"]', text, count=1, flags=re.M)
    conf.write_text(re.sub(r"zacess-[\w-]+\.toml", f"zacess-{wanted.id}.toml", text, count=1))
    note = "" if fixed else " (Alacritty cannot follow the system, so this matches it now)"
    report("Alacritty", wanted.name + note)


def ghostty(fixed, dark, light, now):
    conf = XDG_CONFIG / "ghostty" / "config"
    themes = XDG_CONFIG / "ghostty" / "themes"
    if not conf.exists():
        return report("Ghostty", "not installed, skipped", False)
    if not (themes / f"zacess-{(fixed or dark).id}").exists():
        return report("Ghostty", "Zacess theme files not in ghostty/themes, skipped", False)
    value = f"zacess-{fixed.id}" if fixed else f"light:zacess-{light.id},dark:zacess-{dark.id}"
    text = conf.read_text()
    if re.search(r"^theme\s*=.*$", text, flags=re.M):
        text = re.sub(r"^theme\s*=.*$", f"theme = {value}", text, count=1, flags=re.M)
    else:
        text = text.rstrip("\n") + f"\ntheme = {value}\n"
    conf.write_text(text)
    report("Ghostty", (fixed.name if fixed else f"following the system: {dark.name} or {light.name}")
           + ", in new windows")


PTYXIS_PALETTES = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local" / "share") / "org.gnome.Ptyxis" / "palettes"


def ptyxis_profile():
    """The gsettings path of Ptyxis' default profile (None when Ptyxis is not set up)."""
    if MAC or not shutil.which("gsettings"):
        return None
    if "interface-style" not in run("gsettings", "list-keys", "org.gnome.Ptyxis").stdout.split():
        return None
    uuid_value = run("gsettings", "get", "org.gnome.Ptyxis", "default-profile-uuid").stdout.strip().strip("'")
    return f"org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/{uuid_value}/" if uuid_value else None


def ptyxis_palette_key(profile):
    """The profile key that names the palette: `palette` from Ptyxis 50, `palette-name` before it.
    Setting a key a version does not have fails without a word, so the profile is asked first."""
    schema = profile.split(":", 1)[0]
    keys = run("gsettings", "list-keys", schema).stdout.split()
    return "palette" if "palette" in keys else "palette-name"


def set_ptyxis(profile, palette, style):
    """Sets the palette and the light or dark style; False when gsettings refused either."""
    first = run("gsettings", "set", profile, ptyxis_palette_key(profile), palette)
    second = run("gsettings", "set", "org.gnome.Ptyxis", "interface-style", style)
    return first.returncode == 0 and second.returncode == 0


def ptyxis(fixed, dark, light, now):
    profile = ptyxis_profile()
    if profile is None:
        return
    wanted = fixed or now
    if not (PTYXIS_PALETTES / f"zacess-{wanted.id}.palette").exists():
        return report("Ptyxis", "Zacess palettes not installed (terminal/terminal/linux/ptyxis), skipped", False)
    # a palette holds one look and the Zacess ones come one per theme, so Ptyxis is matched to the
    # theme for the current appearance, the way Alacritty is
    if not set_ptyxis(profile, f"zacess-{wanted.id}", wanted.appearance):
        return report("Ptyxis", "gsettings refused the palette, so Ptyxis was not changed", False)
    note = "" if fixed else " (Ptyxis cannot follow the system with two palettes, so this matches it now)"
    report("Ptyxis", wanted.name + note)


def current_ptyxis():
    profile = ptyxis_profile()
    if profile is None:
        return None
    palette = run("gsettings", "get", profile, ptyxis_palette_key(profile)).stdout.strip().strip("'")
    style = run("gsettings", "get", "org.gnome.Ptyxis", "interface-style").stdout.strip().strip("'")
    if palette.startswith("zacess-"):
        return f"fixed: {name_of(palette)}"
    return f"its own {palette or 'default'} palette, " + ("following the system" if style == "system" else style)


def warp(fixed, dark, light, now):
    if not (HOME / ".warp").is_dir():
        return
    report("Warp", "set by hand: Settings > Appearance > Themes", False)


# KiCad, Processing, Nextpad++, Vivado, Arduino IDE, Thonny, MATLAB, LTspice, Zotero and Obsidian are
# switched by their own apply scripts in editors/ or apps/, so zt and a fresh setup write exactly the
# same files. each script refuses to run while its app is open and says "skipped" when the app is not
# set up
def apply_script(label, tool, fixed, now, script="apply.sh", area=EDITORS):
    folder = "mac" if MAC else "linux"
    path = area / tool / folder / script
    if not path.exists():
        return None
    theme = fixed or now
    result = run("bash", str(path), "--theme", theme.short)
    out = (result.stdout + result.stderr).strip()
    if result.returncode:
        if "is running" in out:
            return report(label, "open, skipped: quit it and run zt again", False)
        return report(label, f"failed: {out.splitlines()[-1] if out else result.returncode}", False)
    if out and "skipped" in out.splitlines()[0]:
        return report(label, "not installed, skipped", False)
    note = "" if fixed else f" ({label} cannot follow the system, so this matches it now)"
    report(label, theme.name + note)


def kicad(fixed, dark, light, now):
    apply_script("KiCad", "kicad", fixed, now)


def processing(fixed, dark, light, now):
    apply_script("Processing", "processing", fixed, now)


def nextpad(fixed, dark, light, now):
    if MAC:
        apply_script("Nextpad++", "nextpad-plus-plus", fixed, now)


def vivado(fixed, dark, light, now):
    if not MAC:
        apply_script("Vivado", "vivado", fixed, now)


def first_existing(*paths):
    return next((path for path in paths if path.exists()), None)


def matlab_installs():
    if MAC:
        return sorted(Path("/Applications").glob("MATLAB_R20*.app"), reverse=True)
    return sorted(Path("/usr/local/MATLAB").glob("R20*"), reverse=True) + ([Path(shutil.which("matlab"))] if shutil.which("matlab") else [])


def thonny_config():
    if MAC:
        return HOME / "Library" / "Thonny" / "configuration.ini"
    return first_existing(XDG_CONFIG / "Thonny" / "configuration.ini",
                          HOME / ".var" / "app" / "org.thonny.Thonny" / "config" / "Thonny" / "configuration.ini")


def arduino_settings():
    return first_existing(HOME / ".arduinoIDE" / "settings.json",
                          HOME / ".var" / "app" / "cc.arduino.IDE2" / ".arduinoIDE" / "settings.json")


def zotero_profile():
    roots = [HOME / "Library" / "Application Support" / "Zotero" / "Profiles"] if MAC else \
        [HOME / ".zotero" / "zotero", HOME / ".var" / "app" / "org.zotero.Zotero" / ".zotero" / "zotero"]
    found = [p for root in roots if root.is_dir() for p in sorted(root.iterdir()) if (p / "prefs.js").exists()]
    return found[0] if found else None


def obsidian_paths():
    # a vault can live anywhere, so it is named once in OBSIDIAN_VAULT, which the apply scripts read
    # too. with none set, Obsidian is left alone
    vault = Path(os.environ["OBSIDIAN_VAULT"]).expanduser() if os.environ.get("OBSIDIAN_VAULT") else None
    if MAC:
        return vault, HOME / "Library" / "Application Support" / "obsidian" / "obsidian.json"
    flatpak = HOME / ".var" / "app" / "md.obsidian.Obsidian"
    listing = flatpak / "config" / "obsidian" / "obsidian.json" if flatpak.is_dir() else XDG_CONFIG / "obsidian" / "obsidian.json"
    return vault, listing


def ltspice_ini():
    roaming = Path(os.environ.get("WINEPREFIX") or HOME / ".wine") / "drive_c" / "users" / os.environ.get("USER", "") / "AppData" / "Roaming"
    return first_existing(roaming / "LTspice.ini", roaming / "LTspiceXVII.ini")


def arduino(fixed, dark, light, now):
    if arduino_settings():
        apply_script("Arduino IDE", "arduino", fixed, now)


def thonny(fixed, dark, light, now):
    config = thonny_config()
    if config and config.exists():
        apply_script("Thonny", "thonny", fixed, now)


def matlab(fixed, dark, light, now):
    # MATLAB saves a theme only from a running session, so a switch is left for its next start
    # rather than starting it here (about a minute). a theme it already holds needs nothing
    if not matlab_installs():
        return
    theme = fixed or now
    # only the saved settings count here: a theme still waiting for the next start is not held yet
    if (current_matlab(pending_too=False) or "").startswith(f"fixed: {theme.name},"):
        MATLAB_PENDING.unlink(missing_ok=True)
        return report("MATLAB", f"{theme.name}, unchanged")
    script = EDITORS / "matlab" / ("mac" if MAC else "linux") / "apply.sh"
    result = run("bash", str(script), "--theme", theme.short, "--pending")
    if result.returncode:
        out = (result.stdout + result.stderr).strip()
        return report("MATLAB", f"failed: {out.splitlines()[-1] if out else result.returncode}", False)
    report("MATLAB", f"{theme.name}, on next start")


def ltspice(fixed, dark, light, now):
    if (MAC and Path("/Applications/LTspice.app").exists()) or (not MAC and ltspice_ini()):
        apply_script("LTspice", "ltspice", fixed, now)


def zotero(fixed, dark, light, now):
    if zotero_profile():
        apply_script("Zotero", "zotero", fixed, now, area=APPS)


def obsidian(fixed, dark, light, now):
    vault, listing = obsidian_paths()
    if (vault / ".obsidian").is_dir():
        apply_script("Obsidian", "obsidian", fixed, now, area=APPS)


# ---------------------------------------------------------------------------------------------------
# tmux: one config for every theme, so the colours that differ (status bar, message line, copy mode
# and pane borders) come from a generated file per theme that tmux.conf sources through a link in
# the state folder. A link rather than a copy, so the file tmux reads is always the repo's own
# ---------------------------------------------------------------------------------------------------

OS_FOLDER = "mac" if MAC else "linux"
TERMINAL_THEMES = REPO_ROOT / "terminal" / "terminal"
TMUX_LINK = STATE_FILE.parent / "tmux.conf"


def repo_copy(folder, *parts):
    """The repo's copy of a config: in the OS folder where the layout keeps one, flat otherwise."""
    for candidate in (folder.joinpath(OS_FOLDER, *parts), folder.joinpath(*parts)):
        if candidate.exists():
            return candidate
    return None


def tmux(fixed, dark, light, now):
    theme = fixed or now
    source = repo_copy(REPO_ROOT / "terminal" / "tmux", "themes", f"zacess-{theme.id}.conf")
    if source is None:
        return report("tmux", "no theme files in terminal/tmux, skipped", False)
    TMUX_LINK.parent.mkdir(parents=True, exist_ok=True)
    if TMUX_LINK.is_symlink() or TMUX_LINK.exists():
        TMUX_LINK.unlink()
    TMUX_LINK.symlink_to(source)
    if not shutil.which("tmux"):
        return report("tmux", "not installed, theme saved for later", False)
    if run("tmux", "list-sessions").returncode == 0:
        # a running server takes the colours now; tmux.conf sources the same link at the next start
        run("tmux", "source-file", str(TMUX_LINK))
        when = "applied to the running server"
    else:
        when = "at the next start"
    note = "" if fixed else " (tmux cannot follow the system, so this matches it now)"
    report("tmux", f"{theme.name}{note}, {when}")


# btop: a generated theme per Zacess theme in terminal/btop/themes. All eight are linked into btop's
# own themes folder, so they sit in its Options menu beside the built-in ones. btop.conf's
# color_theme points at the current one. theme_background makes btop draw on the terminal's own
# background. Only those two keys are rewritten, so every other btop setting stays as it is
BTOP_DIR = XDG_CONFIG / "btop"


def set_btop_conf(conf, theme_file):
    lines = conf.read_text().splitlines() if conf.exists() else ["#? btop config, started by zt for the Zacess theme"]
    for key, value in (("color_theme", f'"{theme_file}"'), ("theme_background", "True")):
        for i, line in enumerate(lines):
            if re.match(rf"{key}\s*=", line):
                lines[i] = f"{key} = {value}"
                break
        else:
            lines.append(f"{key} = {value}")
    conf.parent.mkdir(parents=True, exist_ok=True)
    conf.write_text("\n".join(lines) + "\n")


def btop(fixed, dark, light, now):
    theme = fixed or now
    source_dir = REPO_ROOT / "terminal" / "btop" / "themes"
    if not (source_dir / f"zacess-{theme.id}.theme").exists():
        return report("btop", "no theme files in terminal/btop, skipped", False)
    themes = BTOP_DIR / "themes"
    themes.mkdir(parents=True, exist_ok=True)
    for source in source_dir.glob("zacess-*.theme"):
        link = themes / source.name
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(source)
    set_btop_conf(BTOP_DIR / "btop.conf", themes / f"zacess-{theme.id}.theme")
    note = "" if fixed else " (btop cannot follow the system, so this matches it now)"
    if not shutil.which("btop"):
        return report("btop", f"{theme.name}{note}, btop not installed, saved for later", False)
    # btop rereads btop.conf on SIGUSR2, so an open one takes the theme now
    signalled = run("pkill", "-USR2", "-x", "btop").returncode == 0 if shutil.which("pkill") else False
    report("btop", f"{theme.name}{note}, " + ("applied to the open btop" if signalled else "at its next start"))


def current_tmux():
    if not shutil.which("tmux") and not TMUX_LINK.is_symlink():
        return None
    if not TMUX_LINK.is_symlink():
        return "no theme file linked yet (run zt <theme>)"
    m = re.search(r"zacess-([\w-]+)\.conf$", os.readlink(TMUX_LINK))
    return f"fixed: {name_of(m.group(1)) if m else 'a file that is not a Zacess theme'}"


# ---------------------------------------------------------------------------------------------------
# the system text highlight: the active theme's selection colour, read from the generated terminal
# theme for this OS rather than typed in, so a new palette reaches it unchanged. The value found
# before the first change is recorded, so `zt highlight default` can put it back
# ---------------------------------------------------------------------------------------------------

HIGHLIGHT_RECORD = STATE_FILE.parent / "highlight.default"
KDE_SCHEMES = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local" / "share") / "color-schemes"
GTK_MARKS = ("/* zacess selection start */", "/* zacess selection end */")


def selection_colour(theme):
    """(background, text) of the theme's selection: iTerm2's generated profile on the Mac, Kitty's file on Linux."""
    if MAC:
        profiles = json.loads((TERMINAL_THEMES / "mac" / "iterm2" / "zacess.json").read_text())["Profiles"]
        profile = next(p for p in profiles if p["Name"] == theme.name)

        def to_hex(colour):
            return "#" + "".join(f"{round(colour[k] * 255):02x}"
                                 for k in ("Red Component", "Green Component", "Blue Component"))

        return to_hex(profile["Selection Color"]), to_hex(profile["Selected Text Color"])
    text = (TERMINAL_THEMES / "linux" / "kitty" / f"zacess-{theme.id}.conf").read_text()
    return (re.search(r"^selection_background\s+(\S+)", text, re.M).group(1),
            re.search(r"^selection_foreground\s+(\S+)", text, re.M).group(1))


def rgb_components(hex_colour):
    return tuple(int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))


def kde_rgb(hex_colour):
    return ",".join(str(c) for c in rgb_components(hex_colour))


def mac_highlight_value(hex_colour):
    # three 0 to 1 components and a name; "Other" is what System Settings writes for a colour outside
    # its own list
    return " ".join(f"{c / 255:.6f}" for c in rgb_components(hex_colour)) + " Other"


def record_highlight(current):
    if not HIGHLIGHT_RECORD.exists():
        HIGHLIGHT_RECORD.parent.mkdir(parents=True, exist_ok=True)
        HIGHLIGHT_RECORD.write_text(current + "\n")


def notify_mac_colours():
    # System Settings posts this after it changes the highlight colour and AppKit apps re-read the
    # colour on it; defaults write alone tells nobody. A terminal, an editor or an Electron app draws
    # its own selection colour and takes no notice either way
    run("osascript", "-l", "JavaScript", "-e",
        "ObjC.import('Foundation'); $.NSDistributedNotificationCenter.defaultCenter"
        ".postNotificationNameObjectUserInfoDeliverImmediately('AppleColorPreferencesChangedNotification', null, null, true)")


def desktop_is_kde():
    return "KDE" in os.environ.get("XDG_CURRENT_DESKTOP", "").upper()


def desktop_is_gnome():
    return "GNOME" in os.environ.get("XDG_CURRENT_DESKTOP", "").upper() and bool(shutil.which("gsettings"))


def kde_tool(name):
    return shutil.which(f"{name}6") or shutil.which(f"{name}5")


def kde_scheme_theme(scheme, dark, light):
    # the dark scheme carries the pair's dark theme and the light scheme its light theme, so the
    # colour follows the time-of-day switch between the two global themes
    return dark if "dark" in scheme.stem.lower() else light


def kde_highlight(dark, light):
    """Writes the pair's selection colours into the installed Zacess colour schemes and re-applies the active one."""
    write, read = kde_tool("kwriteconfig"), kde_tool("kreadconfig")
    schemes = sorted(KDE_SCHEMES.glob("Zacess*.colors"))
    if not write or not read or not schemes:
        return None
    before = {}
    changed = False
    for scheme in schemes:
        background, foreground = selection_colour(kde_scheme_theme(scheme, dark, light))
        for key, value in (("BackgroundNormal", kde_rgb(background)), ("ForegroundNormal", kde_rgb(foreground))):
            current = run(read, "--file", str(scheme), "--group", "Colors:Selection", "--key", key).stdout.strip()
            before[f"{scheme.stem}/{key}"] = current
            if current != value:
                run(write, "--file", str(scheme), "--group", "Colors:Selection", "--key", key, value)
                changed = True
    record_highlight(json.dumps(before))
    active = run(read, "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme").stdout.strip()
    if changed and active in [s.stem for s in schemes] and shutil.which("plasma-apply-colorscheme"):
        # applying the scheme again rewrites kdeglobals and tells every running app
        run("plasma-apply-colorscheme", active)
    return changed


def gtk_strip(text):
    return re.sub(re.escape(GTK_MARKS[0]) + r".*?" + re.escape(GTK_MARKS[1]) + r"\n?", "", text, flags=re.S)


def gtk_highlight(background, foreground):
    """The selection colours as the GTK theme's named colours, which GTK apps read when they start."""
    block = (f"{GTK_MARKS[0]}\n@define-color theme_selected_bg_color {background};\n"
             f"@define-color theme_selected_fg_color {foreground};\n{GTK_MARKS[1]}\n")
    changed = False
    for folder in ("gtk-3.0", "gtk-4.0"):
        css = XDG_CONFIG / folder / "gtk.css"
        text = css.read_text() if css.exists() else ""
        rest = gtk_strip(text).rstrip("\n")
        wanted = (rest + "\n\n" if rest else "") + block
        if text != wanted:
            css.parent.mkdir(parents=True, exist_ok=True)
            css.write_text(wanted)
            changed = True
    return changed


def highlight(fixed, dark, light, now):
    theme = fixed or now
    background, foreground = selection_colour(theme)
    if MAC:
        value = mac_highlight_value(background)
        current = run("defaults", "read", "-g", "AppleHighlightColor").stdout.strip()
        record_highlight(current)
        if current != value:
            run("defaults", "write", "-g", "AppleHighlightColor", "-string", value)
            notify_mac_colours()
        where = "Finder, Mail and the other AppKit apps, now or on their next start"
    elif desktop_is_kde():
        if kde_highlight(dark, light) is None:
            return report("Highlight", "no Zacess colour scheme installed in KDE, skipped", False)
        where = "KDE apps now, GTK apps on their next start"
    elif desktop_is_gnome():
        gtk_highlight(background, foreground)
        where = "GTK apps on their next start"
    else:
        return report("Highlight", "no desktop to set it on, skipped", False)
    note = "" if fixed else " (the highlight cannot follow the system, so this matches it now)"
    report("Highlight", f"{background} with {foreground} text, {theme.name}'s selection{note}: {where}")


def restore_highlight():
    recorded = HIGHLIGHT_RECORD.read_text().strip() if HIGHLIGHT_RECORD.exists() else ""
    if MAC:
        if recorded:
            run("defaults", "write", "-g", "AppleHighlightColor", "-string", recorded)
        else:
            run("defaults", "delete", "-g", "AppleHighlightColor")
        notify_mac_colours()
        report("Highlight", f"restored: {recorded}" if recorded else "the system default, the accent colour")
    elif desktop_is_kde():
        write, read = kde_tool("kwriteconfig"), kde_tool("kreadconfig")
        before = json.loads(recorded) if recorded else {}
        if not write or not before:
            return report("Highlight", "nothing recorded to restore", False)
        for name, value in before.items():
            scheme, key = name.split("/")
            # a key that was unset before goes back to KDE's own default selection
            value = value or {"BackgroundNormal": "61,174,233", "ForegroundNormal": "255,255,255"}[key]
            run(write, "--file", str(KDE_SCHEMES / f"{scheme}.colors"), "--group", "Colors:Selection", "--key", key, value)
        active = run(read, "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme").stdout.strip()
        if active and shutil.which("plasma-apply-colorscheme"):
            run("plasma-apply-colorscheme", active)
        report("Highlight", "restored the recorded KDE selection colours")
    elif desktop_is_gnome():
        for folder in ("gtk-3.0", "gtk-4.0"):
            css = XDG_CONFIG / folder / "gtk.css"
            if css.exists():
                css.write_text(gtk_strip(css.read_text()))
        report("Highlight", "the GTK theme's own selection colour")
    else:
        return report("Highlight", "no desktop to restore it on", False)
    if HIGHLIGHT_RECORD.exists():
        HIGHLIGHT_RECORD.unlink()


def current_highlight():
    if MAC:
        value = run("defaults", "read", "-g", "AppleHighlightColor").stdout.strip()
        if not value:
            return "the system default"
        for row in THEMES:
            theme = Theme(row)
            background = selection_colour(theme)[0]
            if value == mac_highlight_value(background):
                return f"fixed: {theme.name}'s selection ({background})"
        return f"not a Zacess selection ({value})"
    if desktop_is_kde():
        read = kde_tool("kreadconfig")
        schemes = sorted(KDE_SCHEMES.glob("Zacess*.colors"))
        if not read or not schemes:
            return None
        found = []
        for scheme in schemes:
            value = run(read, "--file", str(scheme), "--group", "Colors:Selection", "--key", "BackgroundNormal").stdout.strip()
            names = [Theme(r).name for r in THEMES if kde_rgb(selection_colour(Theme(r))[0]) == value]
            found.append(f"{scheme.stem} {names[0] if names else 'not a Zacess selection (' + value + ')'}")
        return "fixed: " + ", ".join(found)
    if desktop_is_gnome():
        css = XDG_CONFIG / "gtk-3.0" / "gtk.css"
        m = re.search(r"theme_selected_bg_color (#[0-9a-fA-F]{6})", css.read_text()) if css.exists() else None
        if not m:
            return "the GTK theme's own"
        names = [Theme(r).name for r in THEMES if selection_colour(Theme(r))[0] == m.group(1)]
        return f"fixed: {names[0]}'s selection ({m.group(1)})" if names else f"not a Zacess selection ({m.group(1)})"
    return None


TOOLS = [vscode, zed, jetbrains, neovim, tmux, btop, eclipse, stm32cubeide, kicad, processing, nextpad, vivado,
         arduino, thonny, matlab, ltspice, zotero, obsidian, terminal_app, iterm2, kitty, alacritty, ghostty, ptyxis,
         warp, highlight]


# ---------------------------------------------------------------------------------------------------
# pins: one app kept on its own theme while every other app follows zt. The pins file sits beside the
# state file, one app per line followed by its value: a Zacess theme id, "auto <dark id> <light id>"
# to follow the system on its own or the app's own built-in theme as "default" (following the
# system where the app can), "default-dark" or "default-light". A switch, an undo and a sync run each
# pinned app with its pin instead of the zt state, so a pin holds until zt unpin
# ---------------------------------------------------------------------------------------------------

PINS_FILE = STATE_FILE.parent / "pins"
DEFAULT_VALUES = ("default", "default-dark", "default-light")
VSCODE_DEFAULTS = {"dark": "Default Dark Modern", "light": "Default Light Modern"}
ZED_DEFAULTS = {"dark": "One Dark", "light": "One Light"}
# Ghostty bundles the iTerm2 colour schemes, which include the plain built-in pair
GHOSTTY_DEFAULTS = {"dark": "Builtin Dark", "light": "Builtin Light"}


def vscode_default(mode):
    path = vscode_settings()
    if not path.exists():
        return report("VS Code", "not installed, skipped", False)
    if mode == "default":
        dark, light = VSCODE_DEFAULTS["dark"], VSCODE_DEFAULTS["light"]
        edit_jsonc(path, {"workbench.colorTheme": dark if system_is_dark() else light,
                          "window.autoDetectColorScheme": True,
                          "workbench.preferredDarkColorTheme": dark,
                          "workbench.preferredLightColorTheme": light})
        return report("VS Code", f"its own theme, following the system: {dark} or {light}")
    name = VSCODE_DEFAULTS[mode.split("-")[1]]
    edit_jsonc(path, {"workbench.colorTheme": name, "window.autoDetectColorScheme": False})
    report("VS Code", f"its own theme, {name}")


def zed_default(mode):
    path = XDG_CONFIG / "zed" / "settings.json"
    if not path.exists():
        return report("Zed", "not installed, skipped", False)
    look = "system" if mode == "default" else mode.split("-")[1]
    edit_jsonc(path, {"theme": {"mode": look, "light": ZED_DEFAULTS["light"], "dark": ZED_DEFAULTS["dark"]}})
    report("Zed", "its own theme, " + ("following the system: One Dark or One Light" if look == "system"
                                       else ZED_DEFAULTS[look]))


def jetbrains_default(mode):
    dirs = jetbrains_dirs()
    if not dirs:
        return report("JetBrains", "not installed, skipped", False)
    if running(JETBRAINS_PROCESS):
        return report("JetBrains", "an IDE is open, skipped: close it and run zt again", False)
    for d, _ in dirs:
        # with no theme named and Sync with OS on, each IDE uses its own light and dark pair
        laf = d / "options" / "laf.xml"
        if laf.exists():
            root = ET.parse(laf).getroot()
            comp = root.find("component[@name='LafManager']")
            if comp is not None:
                for child in list(comp):
                    if child.tag in ("laf", "lafs-to-previous-schemes") or child.tag.startswith("preferred-"):
                        comp.remove(child)
                comp.set("autodetect", "true")
                ET.indent(root, space="  ")
                ET.ElementTree(root).write(laf, encoding="unicode")
        scheme = d / "options" / "colors.scheme.xml"
        if scheme.exists():
            root = ET.parse(scheme).getroot()
            comp = root.find("component[@name='EditorColorsManagerImpl']")
            node = comp.find("global_color_scheme") if comp is not None else None
            if node is not None:
                comp.remove(node)
                ET.indent(root, space="  ")
                ET.ElementTree(root).write(scheme, encoding="unicode")
        report(f"  {d.name}", "its own theme, Sync with OS")


def neovim_pin_report(value):
    report("Neovim", f"pinned to {describe_pin(value)}, on next focus or start")


def tmux_default(mode):
    if TMUX_LINK.is_symlink() or TMUX_LINK.exists():
        source = TMUX_LINK.resolve() if TMUX_LINK.is_symlink() else TMUX_LINK
        keys = re.findall(r"^set(?:w)? -g (\S+)", source.read_text(), flags=re.M) if source.exists() else []
        TMUX_LINK.unlink()
        if shutil.which("tmux") and run("tmux", "list-sessions").returncode == 0:
            # the running server forgets the theme's colours, falling back to tmux.conf's own
            for key in keys:
                run("tmux", "set", "-gu", key)
            run("tmux", "source-file", str(HOME / ".tmux.conf"))
    report("tmux", "its own colours, the terminal's text and background")


def terminal_app_default(mode):
    if not MAC:
        return
    set_terminal_profile("Basic")
    report("Terminal.app", "its own Basic profile, which follows the system")


def iterm_default_guid():
    out = run("defaults", "export", "com.googlecode.iterm2", "-").stdout
    try:
        prefs = plistlib.loads(out.encode())
    except Exception:  # an unreadable or empty export means no Default profile to find
        return None
    for bookmark in prefs.get("New Bookmarks", []):
        if bookmark.get("Name") == "Default":
            return bookmark.get("Guid")
    return None


def iterm2_default(mode):
    if not MAC:
        return
    guid = iterm_default_guid()
    if not guid:
        return report("iTerm2", "no Default profile found, skipped", False)
    auto_file = ITERM_PROFILES / "zacess-auto.json"
    if auto_file.exists():
        auto_file.unlink()
    run("defaults", "write", "com.googlecode.iterm2", "Default Bookmark Guid", "-string", guid)
    note = " (iTerm2 is open: new windows use it after a restart)" if pgrep("-x", "iTerm2") else ""
    report("iTerm2", "its own Default profile" + note)


def kitty_default(mode):
    folder = Path(os.environ.get("KITTY_CONFIG_DIRECTORY") or XDG_CONFIG / "kitty")
    conf = folder / "kitty.conf"
    if not conf.exists():
        return report("Kitty", "not installed, skipped", False)
    conf.write_text(re.sub(r"^include[ \t]+zacess-[\w-]+\.conf[ \t]*\n?", "", conf.read_text(), flags=re.M))
    for name in ("dark-theme.auto.conf", "light-theme.auto.conf", "no-preference-theme.auto.conf"):
        target = folder / name
        if target.exists() and target.read_text().startswith("# Zacess"):
            target.unlink()
    run("pkill", "-USR1", "-x", "kitty")
    report("Kitty", "its own colours")


def alacritty_default(mode):
    conf = XDG_CONFIG / "alacritty" / "alacritty.toml"
    if not conf.exists():
        return report("Alacritty", "not installed, skipped", False)
    text = conf.read_text()
    if re.search(r"zacess-[\w-]+\.toml", text):
        text = re.sub(r'"[^"]*zacess-[\w-]+\.toml"\s*,?\s*', "", text)
        text = re.sub(r"^(import\s*=\s*\[\s*\])[ \t]*$", r"\1 " + ALACRITTY_MARK, text, count=1, flags=re.M)
        conf.write_text(text)
    report("Alacritty", "its own colours")


def ghostty_default(mode):
    conf = XDG_CONFIG / "ghostty" / "config"
    if not conf.exists():
        return report("Ghostty", "not installed, skipped", False)
    if mode == "default":
        value = f"light:{GHOSTTY_DEFAULTS['light']},dark:{GHOSTTY_DEFAULTS['dark']}"
    else:
        value = GHOSTTY_DEFAULTS[mode.split("-")[1]]
    text = conf.read_text()
    if re.search(r"^theme\s*=.*$", text, flags=re.M):
        text = re.sub(r"^theme\s*=.*$", f"theme = {value}", text, count=1, flags=re.M)
    else:
        text = text.rstrip("\n") + f"\ntheme = {value}\n"
    conf.write_text(text)
    report("Ghostty", f"its own theme, {value}, in new windows")


def ptyxis_default(mode):
    profile = ptyxis_profile()
    if profile is None:
        return
    style = "system" if mode == "default" else mode.split("-")[1]
    # gnome is the palette Ptyxis starts with, holding a light and a dark look
    set_ptyxis(profile, "gnome", style)
    report("Ptyxis", "its own GNOME palette, " + ("following the system" if style == "system" else style))


HIGHLIGHT_DEFAULTED = STATE_FILE.parent / "highlight.pinned-default"


def highlight_default(mode):
    # restored once when pinned; later switches leave the highlight alone, since restoring again
    # with the record gone would clear a highlight chosen by hand since
    if HIGHLIGHT_DEFAULTED.exists():
        return report("Highlight", "its own, left as it is", False)
    restore_highlight()
    HIGHLIGHT_DEFAULTED.parent.mkdir(parents=True, exist_ok=True)
    HIGHLIGHT_DEFAULTED.write_text("1\n")


# every app a pin can name: (tool, aliases, default handler, the default values it supports). An app
# with no default handler can still be pinned to a Zacess theme or auto
PIN_APPS = {
    "vscode": (vscode, ("code", "vs-code", "visual-studio-code"), vscode_default, DEFAULT_VALUES),
    "zed": (zed, (), zed_default, DEFAULT_VALUES),
    "jetbrains": (jetbrains, ("idea", "intellij", "pycharm", "webstorm", "clion", "rider"), jetbrains_default,
                  ("default",)),
    "neovim": (neovim, ("nvim", "vim"), None, DEFAULT_VALUES),
    "tmux": (tmux, (), tmux_default, ("default",)),
    "btop": (btop, (), None, ()),
    "eclipse": (eclipse, (), None, ()),
    "stm32cubeide": (stm32cubeide, ("stm32",), None, ()),
    "kicad": (kicad, (), None, ()),
    "processing": (processing, (), None, ()),
    "nextpad": (nextpad, ("nextpad++",), None, ()),
    "vivado": (vivado, (), None, ()),
    "arduino": (arduino, ("arduino-ide",), None, ()),
    "thonny": (thonny, (), None, ()),
    "matlab": (matlab, (), None, ()),
    "ltspice": (ltspice, (), None, ()),
    "zotero": (zotero, (), None, ()),
    "obsidian": (obsidian, (), None, ()),
    "terminal": (terminal_app, ("terminal.app", "apple-terminal", "terminal-app"), terminal_app_default, ("default",)),
    "iterm2": (iterm2, ("iterm", "iterm.app"), iterm2_default, ("default",)),
    "kitty": (kitty, (), kitty_default, ("default",)),
    "alacritty": (alacritty, (), alacritty_default, ("default",)),
    "ghostty": (ghostty, (), ghostty_default, DEFAULT_VALUES),
    "ptyxis": (ptyxis, (), ptyxis_default, DEFAULT_VALUES),
    "warp": (warp, (), None, ()),
    "highlight": (highlight, ("selection",), highlight_default, ("default",)),
}
# termtheme and zt pin terminals: every terminal app zt switches on this system
TERMINALS = ("terminal", "iterm2", "ghostty", "kitty", "alacritty", "warp", "tmux") if MAC else \
    ("ptyxis", "ghostty", "kitty", "alacritty", "tmux")
TOOL_APP = {entry[0]: app for app, entry in PIN_APPS.items()}
# the labels zt prints, for zt doctor and zt current to find a pinned app
LABEL_APP = {"vs code": "vscode", "zed": "zed", "jetbrains": "jetbrains", "neovim": "neovim", "zacess.nvim": "neovim",
             "tmux": "tmux", "tmux server": "tmux", "btop": "btop", "eclipse": "eclipse", "stm32cubeide": "stm32cubeide",
             "kicad": "kicad", "processing": "processing", "nextpad++": "nextpad", "vivado": "vivado",
             "arduino ide": "arduino", "thonny": "thonny", "matlab": "matlab", "ltspice": "ltspice",
             "zotero": "zotero", "obsidian": "obsidian", "terminal.app": "terminal", "iterm2": "iterm2",
             "kitty": "kitty", "alacritty": "alacritty", "ghostty": "ghostty", "ptyxis": "ptyxis", "warp": "warp",
             "highlight": "highlight"}


def app_for_label(label):
    key = label.strip().lower()
    if key in LABEL_APP:
        return LABEL_APP[key]
    # a JetBrains IDE's folder is shown under its own name
    if any(key == d.name.lower() for d, _ in jetbrains_dirs()):
        return "jetbrains"
    return None


# apps that exist on one system only, so a pin elsewhere is refused rather than quietly doing nothing
MAC_ONLY = {"terminal", "iterm2", "nextpad"}
LINUX_ONLY = {"ptyxis", "vivado"}


def on_this_system(app):
    return not ((app in MAC_ONLY and not MAC) or (app in LINUX_ONLY and MAC))


def find_app(word):
    """The app a word names. Aliases point at an app of this system first: "console" is Ptyxis on
    Linux and Terminal.app on macOS, "terminal" is Terminal.app on macOS and Ptyxis on Linux."""
    key = word.strip().lower()
    if key in ("terminal", "console"):
        return "terminal" if MAC else "ptyxis"
    for app, (_, aliases, _, _) in PIN_APPS.items():
        if key == app or key in aliases:
            return app
    return None


def read_pins():
    pins = {}
    if not PINS_FILE.exists():
        return pins
    for line in PINS_FILE.read_text().splitlines():
        words = line.split()
        if len(words) >= 2 and not words[0].startswith("#") and words[0] in PIN_APPS:
            pins[words[0]] = " ".join(words[1:])
    return pins


def write_pins(pins):
    lines = ["# zt pins: an app, then the theme it keeps: a Zacess theme id, auto <dark> <light>,",
             "# default, default-dark or default-light. Written by zt pin and zt unpin"]
    lines += [f"{app} {value}" for app, value in sorted(pins.items())]
    if pins:
        write_atomic(PINS_FILE, "\n".join(lines) + "\n")
    elif PINS_FILE.exists():
        PINS_FILE.unlink()


def parse_pin_value(words):
    """A pin's value from the words after the app: a theme, auto with an optional pair or a default."""
    if not words:
        return None, "a pin needs a theme, auto, default, default-dark or default-light"
    first = words[0].lower()
    if first in DEFAULT_VALUES and len(words) == 1:
        return first, None
    if first == "auto":
        dark = find_theme(words[1]) if len(words) > 1 else find_theme(DEFAULT_DARK)
        light = find_theme(words[2]) if len(words) > 2 else find_theme(DEFAULT_LIGHT)
        if not dark or not light or len(words) > 3:
            return None, "auto takes a dark theme and a light theme. Run zt list for the names"
        return f"auto {dark.id} {light.id}", None
    theme = find_theme(" ".join(words))
    if not theme:
        return None, f"unknown theme: {' '.join(words)}. Run zt list for the names"
    return theme.id, None


def pair_for(value):
    """(fixed or None, dark, light, now) for a state file's text or a pin's theme value."""
    words = value.split()
    if words and words[0] == "auto":
        dark = (find_theme(words[1]) if len(words) > 1 else None) or find_theme(DEFAULT_DARK)
        light = (find_theme(words[2]) if len(words) > 2 else None) or find_theme(DEFAULT_LIGHT)
        return None, dark, light, dark if system_is_dark() else light
    fixed = (find_theme(words[0]) if words else None) or find_theme(DEFAULT_DARK)
    dark = fixed if fixed.dark else find_theme(DEFAULT_DARK)
    light = fixed if not fixed.dark else find_theme(DEFAULT_LIGHT)
    return fixed, dark, light, fixed


def describe_pin(value):
    words = value.split()
    if value in DEFAULT_VALUES:
        return {"default": "its own theme, following the system where it can",
                "default-dark": "its own dark theme", "default-light": "its own light theme"}[value]
    if words and words[0] == "auto":
        # a hand-edited auto line may leave out the pair, which then means the Deep Contrast pair
        dark = words[1] if len(words) > 1 else DEFAULT_DARK
        light = words[2] if len(words) > 2 else DEFAULT_LIGHT
        return f"following the system: {name_of(dark)} or {name_of(light)}"
    return name_of(words[0] if words else DEFAULT_DARK)


def apply_pin(app, value):
    """Run one app with its pin rather than the zt state."""
    tool, _, default, _ = PIN_APPS[app]
    if app == "neovim":
        # Neovim reads its pin from the pins file itself (config/theme.lua), so nothing is written
        return neovim_pin_report(value)
    if value in DEFAULT_VALUES:
        return default(value)
    tool(*pair_for(value))


def run_pinned(apps_values, undone_defaults=()):
    """Apply several pins at once, printing their lines in order. undone_defaults names the apps
    whose default pin was just removed, so their own theme is replaced as well."""
    def one(item):
        _lines.buffer = []
        app, value = item
        _lines.undo_default = app in undone_defaults
        try:
            if value is None:
                PIN_APPS[app][0](*active_pair())
            else:
                apply_pin(app, value)
        except Exception as error:  # one broken config never stops the others
            report(app, f"failed: {error}", False)
        return _lines.buffer

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(apps_values))) as pool:
        for lines in pool.map(one, apps_values):
            for line in lines:
                print(line)


def pin(argv):
    """zt pin <app|terminals> <value>: keep one app (or every terminal) on its own theme."""
    if len(argv) < 2:
        print("Usage: zt pin <app> <theme|auto [dark] [light]|default|default-dark|default-light>\n"
              f"Apps: {', '.join(PIN_APPS)}. terminals pins {', '.join(TERMINALS)}", file=sys.stderr)
        return 1
    group = argv[0].lower() == "terminals"
    app = None if group else find_app(argv[0])
    if not group and not app:
        print(f"Unknown app: {argv[0]}. The apps are {', '.join(PIN_APPS)}. terminals pins every terminal.",
              file=sys.stderr)
        return 1
    if app and not on_this_system(app):
        print(f"{app} is not an app zt switches on {'macOS' if MAC else 'Linux'}, so it cannot be pinned here.",
              file=sys.stderr)
        return 1
    value, error = parse_pin_value(argv[1:])
    if error:
        print(error, file=sys.stderr)
        return 1
    apps = list(TERMINALS) if group else [app]
    pins = read_pins()
    chosen, skipped = [], []
    for name in apps:
        if name == "warp":
            # Warp's theme is only ever set by hand, so a pin would promise something zt cannot do
            skipped.append(f"{name} (set by hand in its settings)")
            continue
        if value in DEFAULT_VALUES and value not in PIN_APPS[name][3]:
            skipped.append(f"{name} (no built-in theme of that kind zt can set)")
            continue
        chosen.append(name)
    if not group and skipped:
        app_name = apps[0]
        if app_name == "warp":
            print("Warp's theme is set by hand in Settings > Appearance > Themes, so zt cannot pin it.",
                  file=sys.stderr)
        elif PIN_APPS[app_name][3]:
            print(f"{app_name} has no built-in {value.split('-')[-1]} theme zt can switch to; it supports "
                  f"{', '.join(PIN_APPS[app_name][3])}.", file=sys.stderr)
        else:
            print(f"{app_name} has no built-in theme zt can switch to, so it can be pinned to a Zacess theme "
                  "or auto only.", file=sys.stderr)
        return 1
    state = current_state() or DEFAULT_DARK
    following_same = value.startswith("auto") and state == value
    if "highlight" in chosen:
        # a fresh pin starts over: a default pin restores once again
        HIGHLIGHT_DEFAULTED.unlink(missing_ok=True)
    for name in chosen:
        if following_same:
            # an auto pin that matches zt's own auto state is the same as no pin
            pins.pop(name, None)
        else:
            pins[name] = value
    write_pins(pins)
    print(f"{BOLD}Pinned{RESET} {', '.join(chosen)} to {describe_pin(value)}" if not following_same else
          f"{BOLD}Following zt again{RESET}: {', '.join(chosen)} (zt already follows the system with that pair)")
    if skipped:
        print(f"  {SKIP}left as they were: {'; '.join(skipped)}{RESET}")
    run_pinned([(name, None if following_same else value) for name in chosen])
    return 0


def unpin(argv):
    """zt unpin <app|terminals|--all>: the app follows zt again and is switched to the zt state now."""
    if not argv:
        print("Usage: zt unpin <app|terminals|--all>", file=sys.stderr)
        return 1
    pins = read_pins()
    word = argv[0].lower()
    if word == "--all":
        apps = list(pins)
    elif word == "terminals":
        apps = [name for name in TERMINALS if name in pins]
    else:
        app = find_app(word)
        if not app:
            print(f"Unknown app: {argv[0]}. The apps are {', '.join(PIN_APPS)}.", file=sys.stderr)
            return 1
        apps = [app] if app in pins else []
    if not apps:
        print("Nothing pinned there")
        return 0
    undone_defaults = {name for name in apps if pins.get(name) in DEFAULT_VALUES}
    for name in apps:
        pins.pop(name, None)
    write_pins(pins)
    if "highlight" in apps:
        HIGHLIGHT_DEFAULTED.unlink(missing_ok=True)
    print(f"{BOLD}Following zt again{RESET}: {', '.join(apps)}")
    run_pinned([(name, None) for name in apps], undone_defaults)
    return 0


def show_pins(only=None):
    pins = read_pins()
    shown = {app: value for app, value in pins.items() if only is None or app in only}
    if shown:
        # apps sharing a value, as termtheme leaves every terminal, are named together
        groups = {}
        for app, value in sorted(shown.items()):
            groups.setdefault(value, []).append(app)
        print(f"{BOLD}Pinned{RESET}: " + "; ".join(f"{', '.join(apps)} on {describe_pin(value)}"
                                                   for value, apps in groups.items()))
    elif only is None:
        print("Pinned: nothing, every app follows zt")


def name_of(theme_id):
    theme = find_theme(theme_id.replace("zacess-", "")) if theme_id else None
    return theme.name if theme else (theme_id or "not set")


def read_epf(path):
    keys = {}
    for line in path.read_text().splitlines():
        if line.startswith("/instance/") and "=" in line:
            plugin, _, rest = line[len("/instance/"):].partition("/")
            key, _, value = rest.partition("=")
            keys[(plugin, key)] = value
    return keys


def read_prefs(settings, plugin):
    path = settings / f"{plugin}.prefs"
    if not path.exists():
        return {}
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)


# each reader returns what the tool is on now, in the same words zt prints when it sets it
def current_vscode():
    path = vscode_settings()
    if not path.exists():
        return None
    data = parse_jsonc(path.read_text())
    if data.get("window.autoDetectColorScheme"):
        return (f"following the system: {data.get('workbench.preferredDarkColorTheme')} or "
                f"{data.get('workbench.preferredLightColorTheme')}")
    return f"fixed: {data.get('workbench.colorTheme', 'default')}"


def newest_version_dir(*bases):
    for base in bases:
        if base and base.is_dir():
            found = [d for d in base.iterdir() if d.is_dir() and re.fullmatch(r"\d+\.\d+(\.\d+)?", d.name)]
            if found:
                return max(found, key=lambda d: tuple(int(n) for n in d.name.split(".")))
    return None


def current_kicad():
    config = newest_version_dir(Path(os.environ["KICAD_CONFIG_HOME"]) if os.environ.get("KICAD_CONFIG_HOME") else None,
                                HOME / "Library" / "Preferences" / "kicad", XDG_CONFIG / "kicad",
                                HOME / ".var" / "app" / "org.kicad.KiCad" / "config" / "kicad")
    if config is None or not (config / "eeschema.json").exists():
        return None
    value = json.loads((config / "eeschema.json").read_text()).get("appearance", {}).get("color_theme") or "KiCad default"
    return f"fixed: {name_of(value) if value.startswith('zacess-') else value}"


def current_processing():
    for prefs in (HOME / "Library" / "Processing" / "preferences.txt", XDG_CONFIG / "processing" / "preferences.txt"):
        if prefs.exists():
            values = dict(line.split("=", 1) for line in prefs.read_text().splitlines() if "=" in line)
            sketchbook = values.get("sketchbook.path.four") or values.get("sketchbook.path") or ""
            theme = Path(sketchbook) / "theme.txt"
            if theme.exists() and theme.read_text().startswith("# Zacess theme for Processing: "):
                return f"fixed: {theme.read_text().splitlines()[0].split(': ', 1)[1]}"
            return f"fixed: {values.get('theme', 'a built-in theme')}"
    return None


def current_nextpad():
    if not MAC or not Path("/Applications/Nextpad++.app").exists():
        return None
    name = run("defaults", "read", "org.nextpadplusplus.mac", "NPPActiveTheme").stdout.strip()
    return f"fixed: {name or 'default'}"


def current_vivado():
    if MAC:
        return None
    config = newest_version_dir(HOME / ".Xilinx" / "Vivado", HOME / ".Xilinx" / "vivado")
    if config is None or not (config / "vivado.xml").exists():
        return None
    colours = ET.parse(config / "vivado.xml").getroot().find("general_color")
    current = {node.tag: node.get("color") for node in colours} if colours is not None else {}
    for row in THEMES:
        theme = EDITORS / "vivado" / "shared" / "themes" / f"zacess-{row[0]}.json"
        if not theme.exists():
            continue
        wanted = json.loads(theme.read_text())["general_color"]
        if all(current.get(key) == value for key, value in wanted.items()):
            return f"fixed: {row[2]}"
    return "not a Zacess theme"


def current_arduino():
    path = arduino_settings()
    if path is None:
        return None
    return f"fixed: {json.loads(path.read_text() or '{}').get('workbench.colorTheme', 'default')}"


def current_thonny():
    config = thonny_config()
    if config is None or not config.exists():
        return None
    view = {}
    section = None
    for line in config.read_text().splitlines():
        if line.startswith("["):
            section = line.strip("[]")
        elif section == "view" and " = " in line:
            key, value = line.split(" = ", 1)
            view[key] = value
    return f"fixed: {view.get('syntax_theme', 'default')}, {view.get('editor_font_family', 'default font')}"


def current_matlab(pending_too=True):
    import zipfile
    roots = [HOME / "Library" / "Application Support" / "MathWorks" / "MATLAB"] if MAC else [HOME / ".matlab"]
    folders = sorted((d for root in roots if root.is_dir() for d in root.glob("R20*")), reverse=True)
    store = next((d / "matlab.mlsettings" for d in folders if (d / "matlab.mlsettings").exists()), None)
    if store is None:
        return None
    # the settings file is a zip of one JSON file per settings group, each value itself JSON
    current = {}
    with zipfile.ZipFile(store) as z:
        for member in z.namelist():
            if member.startswith("fsroot/settingstree/") and member.endswith("/settings.json"):
                group = json.loads(z.read(member))
                prefix = group["path"].replace("/settingstree/", "").replace("/", ".")
                for setting in group.get("settings", []):
                    if setting.get("hasValue"):
                        # most values are wrapped as {"mwdata": [...]}, a few are bare JSON
                        parsed = json.loads(setting["value"])
                        data = parsed.get("mwdata") if isinstance(parsed, dict) else parsed
                        if isinstance(data, list) and len(data) == 1:
                            data = data[0]
                        current[f"{prefix}.{setting['name']}"] = data
    font = f"{current.get('matlab.fonts.codefont.Name', 'default font')} {current.get('matlab.fonts.codefont.Size', '')}".strip()
    pending = MATLAB_PENDING.read_text(encoding="utf-8").strip() if pending_too and MATLAB_PENDING.exists() else ""
    saved = None
    for row in THEMES:
        theme = EDITORS / "matlab" / "shared" / "themes" / f"{row[2]}.json"
        if theme.exists():
            wanted = json.loads(theme.read_text())["settings"]
            if all(current.get(key) == value for key, value in wanted.items()):
                saved = row[2]
                break
    # a theme zt left for the next start is what MATLAB will show, so that is what is reported
    if pending and pending != saved:
        return f"fixed: {pending}, on next start"
    if saved:
        return f"fixed: {saved}, {font}"
    return f"not a Zacess theme ({current.get('matlab.appearance.MATLABTheme', 'default')} desktop), {font}"


def current_ltspice():
    if MAC:
        if not Path("/Applications/LTspice.app").exists():
            return None
        out = run("defaults", "export", "com.analog.LTspice.App", "-")
        if out.returncode:
            return "not started yet"
        current = plistlib.loads(out.stdout.encode())
        current = {"Grid": current.get("GridColor"), **current}
    else:
        ini = ltspice_ini()
        if ini is None:
            return None
        current = dict(re.findall(r"(?m)^([A-Za-z0-9]+)=(\d+)\r?$", ini.read_bytes().decode("latin-1")))
        current = {key: int(value) for key, value in current.items()}
    # the schematic, waveform and grid colours are the same names on every platform
    for row in THEMES:
        theme = EDITORS / "ltspice" / "shared" / "themes" / f"{row[2]}.ini"
        if theme.exists():
            wanted = dict(re.findall(r"(?m)^((?:WaveColor|SchematicColor)\d+|Grid)=(\d+)$", theme.read_text()))
            wanted.pop("SchematicColor13", None)
            if all(current.get(key) == int(value) for key, value in wanted.items()):
                return f"fixed: {row[2]}"
    return "not a Zacess theme"


def current_zotero():
    profile = zotero_profile()
    if profile is None:
        return None
    user_js = profile / "user.js"
    text = user_js.read_text() if user_js.exists() else ""
    prefs = {key: json.loads(value) for key, value in re.findall(r'user_pref\("([^"]+)",\s*(.+?)\);', text)}
    themes = json.loads((APPS / "zotero" / "shared" / "themes.json").read_text())
    # several Zacess themes share one Zotero mode and reader theme, so every match is named
    matches = [name for name, wanted in themes.items() if all(prefs.get(k) == v for k, v in wanted.items())]
    if not matches:
        return "not a Zacess theme"
    mode = "dark" if prefs.get("browser.theme.toolbar-theme") == 0 else "light"
    return f"fixed: {mode} mode for {' or '.join(m.replace('Zacess ', '') for m in matches)}"


def current_obsidian():
    vault, _ = obsidian_paths()
    dot = vault / ".obsidian"
    if not dot.is_dir():
        return None
    appearance = json.loads((dot / "appearance.json").read_text())
    style = dot / "plugins" / "obsidian-style-settings" / "data.json"
    contrast = json.loads(style.read_text()).get("zacess-theme@@zacess-contrast") if style.exists() else None
    if appearance.get("cssTheme") != "Zacess":
        return f"fixed: {appearance.get('cssTheme') or 'default'}"
    themes = json.loads((APPS / "obsidian" / "shared" / "themes.json").read_text())
    for name, choice in themes.items():
        if choice["base"] == appearance.get("theme") and choice["contrast"] == contrast:
            return f"fixed: {name}, {appearance.get('monospaceFontFamily', 'default font')}"
    return f"Zacess with no contrast choice ({appearance.get('theme')})"


def current_zed():
    path = XDG_CONFIG / "zed" / "settings.json"
    if not path.exists():
        return None
    value = parse_jsonc(path.read_text()).get("theme")
    if isinstance(value, dict):
        mode = value.get("mode", "system")
        if mode == "system":
            return f"following the system: {value.get('dark')} or {value.get('light')}"
        return f"fixed: {value.get(mode)}"
    return f"fixed: {value or 'default'}"


def current_jetbrains():
    out = []
    for d, has_plugin in jetbrains_dirs():
        laf = d / "options" / "laf.xml"
        scheme = d / "options" / "colors.scheme.xml"
        comp = ET.parse(laf).getroot().find("component[@name='LafManager']") if laf.exists() else None
        node = ET.parse(scheme).getroot().find(".//global_color_scheme") if scheme.exists() else None
        editor = node.get("name") if node is not None else "default"
        if comp is not None and comp.get("autodetect") == "true":
            dark = comp.find("preferred-dark-laf")
            light = comp.find("preferred-light-laf")
            text = (f"Sync with OS: {name_of(dark.get('themeId') if dark is not None else '')} or "
                    f"{name_of(light.get('themeId') if light is not None else '')}")
        else:
            laf_node = comp.find("laf") if comp is not None else None
            text = f"fixed: {name_of(laf_node.get('themeId') if laf_node is not None else '')}"
        out.append((d.name, f"{text}, editor {editor}" + ("" if has_plugin else " (no Zacess plugin)")))
    return out


def current_neovim():
    if not STATE_FILE.exists():
        return f"fixed: {Theme(THEMES[0]).name} (no state file, the default)"
    words = STATE_FILE.read_text().split()
    if words and words[0] == "auto":
        return f"following the system: {name_of(words[1] if len(words) > 1 else DEFAULT_DARK)} or " \
               f"{name_of(words[2] if len(words) > 2 else DEFAULT_LIGHT)}"
    return f"fixed: {name_of(words[0] if words else DEFAULT_DARK)}"


def current_eclipse():
    return current_eclipse_like(ECLIPSE_WORKSPACE, ECLIPSE_THEMES)


def current_stm32cubeide():
    workspace = stm32_workspace()
    return current_eclipse_like(workspace, STM32_THEMES) if workspace else None


def current_eclipse_like(workspace, themes):
    settings = workspace_settings(workspace)
    if not settings.is_dir():
        return None
    # Eclipse keeps no theme name, so the editor colours are compared with each theme's file
    best, best_score, found = None, 0.0, False
    cache = {}
    for row in THEMES:
        theme = Theme(row)
        epf = themes / f"{theme.name}.epf"
        if not epf.exists():
            continue
        found = True
        keys = read_epf(epf)
        hits = 0
        for (plugin, key), value in keys.items():
            if plugin not in cache:
                cache[plugin] = read_prefs(settings, plugin)
            hits += cache[plugin].get(key) == value
        score = hits / len(keys) if keys else 0
        if score > best_score:
            best, best_score = theme, score
    if not found:
        return "no Zacess theme files to compare with"
    if not best:
        return "not a Zacess theme"
    workbench = read_prefs(settings, "org.eclipse.e4.ui.css.swt.theme").get("themeid", "")
    look = "Dark" if workbench.endswith("e4_dark") else "Light"
    if best_score == 1:
        return f"fixed: {best.name}, {look} workbench"
    return f"not a Zacess theme (closest {best.name}, {round(best_score * 100)}% of its colours), {look} workbench"


def current_terminal_app():
    if not MAC:
        return None
    name = run("defaults", "read", "com.apple.Terminal", "Default Window Settings").stdout.strip()
    if TERMINAL_AGENT_PLIST.exists():
        args = re.findall(r"<string>([^<]*)</string>", TERMINAL_AGENT_PLIST.read_text())[2:4]
        return f"following the system: {' or '.join(args) if args else 'default pair'} (now {name})"
    return f"fixed: {name}"


def current_iterm2():
    if not MAC or not (ITERM_PROFILES / "zacess.json").exists():
        return None
    guid = run("defaults", "read", "com.googlecode.iterm2", "Default Bookmark Guid").stdout.strip()
    if guid == ITERM_AUTO_GUID:
        return "following the system: the Zacess Auto profile"
    names = {p["Guid"]: p["Name"] for p in json.loads((ITERM_PROFILES / "zacess.json").read_text())["Profiles"]}
    return f"fixed: {names.get(guid, 'a profile that is not a Zacess one')}"


def current_kitty():
    folder = Path(os.environ.get("KITTY_CONFIG_DIRECTORY") or XDG_CONFIG / "kitty")
    conf = folder / "kitty.conf"
    if not conf.exists():
        return None
    if (folder / "dark-theme.auto.conf").exists():
        return "following the system through the auto theme files"
    m = re.search(r"^include\s+zacess-([\w-]+)\.conf", conf.read_text(), flags=re.M)
    return f"fixed: {name_of(m.group(1)) if m else 'no Zacess include'}"


def current_alacritty():
    conf = XDG_CONFIG / "alacritty" / "alacritty.toml"
    if not conf.exists():
        return None
    m = re.search(r"zacess-([\w-]+)\.toml", conf.read_text())
    return f"fixed: {name_of(m.group(1)) if m else 'no Zacess import'}"


def current_ghostty():
    conf = XDG_CONFIG / "ghostty" / "config"
    if not conf.exists():
        return None
    m = re.search(r"^theme\s*=\s*(.+)$", conf.read_text(), flags=re.M)
    if not m:
        return "fixed: default"
    value = m.group(1).strip()
    if "light:" in value:
        pairs = dict(part.split(":", 1) for part in value.split(","))
        return f"following the system: {name_of(pairs.get('dark', ''))} or {name_of(pairs.get('light', ''))}"
    return f"fixed: {name_of(value)}"


def show_current(only=None):
    """Every tool's theme now (only the apps named when given, as termtheme shows the terminals)."""
    pins = read_pins()
    if only is None:
        print(current_neovim().replace("fixed:", "zt state: fixed", 1).replace("following the system", "zt state: following the system", 1))
    show_pins(only)

    def shown(tool, text):
        app = app_for_label(tool)
        if only is not None and app not in only:
            return
        if app in pins:
            text += f" (pinned to {describe_pin(pins[app])})"
        report(tool, text, False)
    if only is not None and set(only) <= set(TERMINALS):
        for tool, reader in [("Terminal.app", current_terminal_app), ("iTerm2", current_iterm2),
                             ("Kitty", current_kitty), ("Alacritty", current_alacritty),
                             ("Ghostty", current_ghostty), ("Ptyxis", current_ptyxis), ("tmux", current_tmux)]:
            try:
                value = reader()
            except Exception as error:  # a config that cannot be read is reported, never fatal
                value = f"could not read: {error}"
            if value:
                shown(tool, value)
        if MAC and (HOME / ".warp").is_dir():
            shown("Warp", "set by hand: Settings > Appearance > Themes")
        return
    shared = shared_file()
    push = read_json(shared) if shared and only is None else None
    if push:
        seen = ALL_SEEN.read_text().strip() if ALL_SEEN.exists() else ""
        what = "undo of the last push" if push.get("undo_of") else push.get("state", "")
        print(f"--all: last push {what} from {push.get('from', '?')} at {push.get('at', '?')}, "
              f"{'applied here' if push.get('id') == seen else 'not applied here yet'}")
    readers = [("VS Code", current_vscode), ("Zed", current_zed), ("Neovim", current_neovim),
               ("Eclipse", current_eclipse), ("STM32CubeIDE", current_stm32cubeide), ("KiCad", current_kicad),
               ("Processing", current_processing), ("Nextpad++", current_nextpad), ("Vivado", current_vivado),
               ("Arduino IDE", current_arduino), ("Thonny", current_thonny), ("MATLAB", current_matlab),
               ("LTspice", current_ltspice), ("Zotero", current_zotero), ("Obsidian", current_obsidian),
               ("Terminal.app", current_terminal_app), ("iTerm2", current_iterm2),
               ("Kitty", current_kitty), ("Alacritty", current_alacritty), ("Ghostty", current_ghostty),
               ("Ptyxis", current_ptyxis), ("tmux", current_tmux), ("Highlight", current_highlight)]
    for tool, reader in readers:
        try:
            value = reader()
        except Exception as error:  # a config that cannot be read is reported, never fatal
            value = f"could not read: {error}"
        if tool == "Neovim" and "neovim" in pins:
            if only is None or "neovim" in only:
                report(tool, f"pinned to {describe_pin(pins['neovim'])}", False)
            continue
        if value:
            shown(tool, value)
        if tool == "Zed":
            for ide, text in current_jetbrains():
                shown(f"  {ide}", text)


# ---------------------------------------------------------------------------------------------------
# zt doctor: every installed theme file against the repo copy for the active theme and every tool's
# own setting against the state, so a copy that stopped matching the repo or a tool switched by hand
# shows up. Exit 1 on any drift
# ---------------------------------------------------------------------------------------------------

def active_pair():
    """(fixed or None, dark, light, now) from the state file, worked out as zt itself does."""
    words = STATE_FILE.read_text().split() if STATE_FILE.exists() else []
    if words and words[0] == "auto":
        dark = (find_theme(words[1]) if len(words) > 1 else None) or find_theme(DEFAULT_DARK)
        light = (find_theme(words[2]) if len(words) > 2 else None) or find_theme(DEFAULT_LIGHT)
        return None, dark, light, dark if system_is_dark() else light
    fixed = (find_theme(words[0]) if words else None) or find_theme(DEFAULT_DARK)
    dark = fixed if fixed.dark else find_theme(DEFAULT_DARK)
    light = fixed if not fixed.dark else find_theme(DEFAULT_LIGHT)
    return fixed, dark, light, fixed


def doctor_for_pin(d, value):
    """A view of the doctor on a pin's pair, whose lines still count towards the same total."""
    view = Doctor(*pair_for(value))
    view.pins = d.pins
    view.line = d.line
    return view


class Doctor:
    def __init__(self, fixed, dark, light, now):
        self.fixed, self.dark, self.light, self.now = fixed, dark, light, now
        # the themes whose files the active mode relies on
        self.wanted = [now] if fixed else [dark, light]
        self.drift = 0
        self.pins = read_pins()

    def line(self, tool, status, text):
        colour = {"ok": OK, "drift": DRIFT}.get(status, SKIP)
        print(f"  {BOLD}{tool:<16}{RESET} {colour}{status}: {text}{RESET}")
        if status == "drift":
            self.drift += 1

    def agrees(self, text):
        """Whether a tool's own reading names the theme zt last set."""
        if self.fixed:
            return self.fixed.name in text or self.fixed.name.replace("Zacess ", "") in text
        if "following the system" in text or "Sync with OS" in text:
            mentioned = [Theme(row).name for row in THEMES if Theme(row).name in text]
            return not mentioned or (self.dark.name in text and self.light.name in text)
        # a tool that cannot follow the system was set to the theme matching the appearance then
        return self.now.name in text

    def setting(self, tool, text):
        if text is None:
            return
        app = app_for_label(tool)
        if app in self.pins:
            # a pinned app is meant to differ from the zt state
            return self.line(tool, "ok", f"pinned to {describe_pin(self.pins[app])}: {text}")
        if text.startswith("could not read") or "not a Zacess" in text:
            return self.line(tool, "drift", text)
        self.line(tool, "ok" if self.agrees(text) else "drift", text)

    def files(self, tool, pairs, what):
        """Installed files against their repo copies: pairs of (installed, repo)."""
        problems = []
        for installed, repo in pairs:
            if repo is None or not repo.exists():
                continue
            shown = str(installed).replace(str(HOME), "~")
            # the Xcode themes come from the Zacess Themes clone, outside this repo
            source = str(repo.relative_to(REPO_ROOT)) if repo.is_relative_to(REPO_ROOT) else str(repo).replace(str(HOME), "~")
            if not installed.exists():
                problems.append(f"{shown} missing")
            elif installed.read_bytes() != repo.read_bytes():
                problems.append(f"{shown} differs from {source}")
        if problems:
            return self.line(tool, "drift", "; ".join(problems))
        self.line(tool, "ok", what)


def pinned_extension(folder, prefix):
    """The version a folder's extensions.txt pins for an extension or None."""
    listing = repo_copy(folder, "extensions.txt")
    if listing is None:
        return None
    m = re.search(rf"^{re.escape(prefix)}@(\S+)", listing.read_text(), re.M)
    return m.group(1) if m else None


def installed_extension(extensions, prefix):
    """The newest installed version of an extension from its folder names or None."""
    if not extensions.is_dir():
        return None
    found = [m.group(1) for p in extensions.glob(f"{prefix}-*") if (m := re.search(r"-(\d+\.\d+\.\d+)", p.name))]
    return max(found, key=version_tuple) if found else None


def version_tuple(text):
    return tuple(int(n) for n in re.findall(r"\d+", text))


def doctor_vscode(d):
    folder = EDITORS / "vscode"
    path = vscode_settings()
    if not path.exists():
        return
    d.setting("VS Code", current_vscode())
    d.files("VS Code", [(path, repo_copy(folder, "settings.json")),
                        (path.parent / "snippets" / "global.code-snippets", repo_copy(folder, "global.code-snippets"))],
            "settings and snippets match the repo")
    pin = pinned_extension(folder, "zacess.zacess-themes")
    installed = installed_extension(HOME / ".vscode" / "extensions", "zacess.zacess-themes")
    if pin and installed:
        behind = version_tuple(installed) < version_tuple(pin)
        d.line("VS Code", "drift" if behind else "ok", f"Zacess Themes {installed} installed, {pin} pinned in extensions.txt")


def doctor_zed(d):
    path = XDG_CONFIG / "zed" / "settings.json"
    if not path.exists():
        return
    d.setting("Zed", current_zed())
    pairs = [(path, repo_copy(EDITORS / "zed", "settings.json"))]
    local = XDG_CONFIG / "zed" / "themes" / "zacess.json"
    if local.exists():
        pairs.append((local, EDITORS / "zed" / "shared" / "themes" / "zacess.json"))
    d.files("Zed", pairs, "settings" + (" and the local theme file" if local.exists() else "") + " match the repo")


def doctor_jetbrains(d):
    shared = EDITORS / "jetbrains" / "shared"
    keymap = "JetBrains Custom (VSCode-based) mac" if MAC else "JetBrains Custom (VSCode-based) windows-linux"
    for (ide, text), (folder, has_plugin) in zip(current_jetbrains(), jetbrains_dirs()):
        d.setting(ide, text)
        if not shared.is_dir():
            continue
        copies = ["codestyles/Default.xml", "fileTemplates/internal/Class.java", "options/editor-font.xml",
                  "options/terminal-font.xml", f"keymaps/{keymap}.xml"]
        pairs = [(folder / name, shared / name) for name in copies]
        pairs += [(folder / "colors" / scheme.name, scheme) for scheme in sorted((shared / "colors").glob("*.icls"))]
        d.files(ide, pairs, "the shared code style, template, keymap, fonts and colour schemes match the repo")


def doctor_neovim(d):
    repo = repo_copy(EDITORS / "neovim", "nvim")
    installed = XDG_CONFIG / "nvim"
    if repo is None or not installed.exists():
        return
    pairs = [(installed / f.relative_to(repo), f) for f in sorted(repo.rglob("*")) if f.is_file()]
    d.files("Neovim", pairs, f"{len(pairs)} config files match the repo")
    lock = repo / "lazy-lock.json"
    plugin = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local" / "share") / "nvim" / "lazy" / "zacess.nvim"
    if lock.exists() and plugin.is_dir():
        locked = json.loads(lock.read_text()).get("zacess.nvim", {}).get("commit", "")
        head = run("git", "-C", str(plugin), "rev-parse", "HEAD").stdout.strip()
        if locked and head:
            d.line("zacess.nvim", "ok" if head == locked else "drift",
                   f"installed {head[:7]}, lazy-lock.json pins {locked[:7]}")


def doctor_apps(d):
    readers = [("Eclipse", current_eclipse), ("STM32CubeIDE", current_stm32cubeide), ("KiCad", current_kicad),
               ("Processing", current_processing), ("Nextpad++", current_nextpad), ("Vivado", current_vivado),
               ("Arduino IDE", current_arduino), ("Thonny", current_thonny), ("MATLAB", current_matlab),
               ("LTspice", current_ltspice), ("Zotero", current_zotero), ("Obsidian", current_obsidian)]
    for tool, reader in readers:
        try:
            d.setting(tool, reader())
        except Exception as error:  # a config that cannot be read is drift, never fatal
            d.line(tool, "drift", f"could not read: {error}")


def archived_colour(blob):
    """The first three components of an archived NSColor, rounded to four places or nothing when it cannot be read."""
    try:
        objects = plistlib.loads(blob)["$objects"]
    except Exception:
        return None
    for obj in objects:
        if isinstance(obj, dict) and "NSRGB" in obj:
            return tuple(round(float(c), 4) for c in obj["NSRGB"].rstrip(b"\x00").split()[:3])
    return None


def archived_font(blob):
    """(name, size) of an archived NSFont or None."""
    try:
        objects = plistlib.loads(blob)["$objects"]
    except Exception:
        return None
    name = next((o for o in objects if isinstance(o, str) and o != "$null"), None)
    size = next((o["NSSize"] for o in objects if isinstance(o, dict) and "NSSize" in o), None)
    return name, size


def doctor_terminal_app(d):
    if not MAC:
        return
    out = run("defaults", "export", "com.apple.Terminal", "-")
    if out.returncode:
        return
    settings = plistlib.loads(out.stdout.encode()).get("Window Settings", {})
    d.setting("Terminal.app", current_terminal_app())
    problems = []
    for theme in d.wanted:
        with open(TERMINAL_THEMES / "mac" / "terminal-app" / f"{theme.name}.terminal", "rb") as f:
            wanted = plistlib.load(f)
        installed = settings.get(theme.name)
        if installed is None:
            problems.append(f"the {theme.name} profile is not installed")
            continue
        for key, value in wanted.items():
            if key == "Font":
                same = archived_font(installed.get(key, b"")) == archived_font(value)
            elif isinstance(value, bytes):
                # Terminal.app stores a colour's components without the alpha the repo file carries
                same = archived_colour(installed.get(key, b"")) == archived_colour(value)
            else:
                same = installed.get(key) == value
            if not same:
                problems.append(f"{theme.name}: {key}")
    if problems:
        return d.line("Terminal.app", "drift", "; ".join(problems))
    d.line("Terminal.app", "ok", f"the {' and '.join(t.name for t in d.wanted)} profile matches the repo")


def doctor_iterm2(d):
    source = TERMINAL_THEMES / "mac" / "iterm2" / "zacess.json"
    if not MAC or not (ITERM_PROFILES / "zacess.json").exists():
        return
    d.setting("iTerm2", current_iterm2())
    pinned = d.pins.get("iterm2")
    if pinned:
        # the Zacess Auto profile only matters for an auto pin, checked against that pin's pair
        if pinned in DEFAULT_VALUES or not pinned.startswith("auto"):
            return d.files("iTerm2", [(ITERM_PROFILES / "zacess.json", source)], "the dynamic profiles match the repo")
        d = doctor_for_pin(d, pinned)
    if not d.fixed:
        profiles = {p["Name"]: p for p in json.loads(source.read_text())["Profiles"]}
        wanted = json.dumps({"Profiles": [iterm_auto_profile(profiles, d.dark, d.light)]}, indent=2) + "\n"
        auto = ITERM_PROFILES / "zacess-auto.json"
        if not auto.exists() or auto.read_text() != wanted:
            d.line("iTerm2", "drift", "the Zacess Auto profile is missing or differs from the pair")
    d.files("iTerm2", [(ITERM_PROFILES / "zacess.json", source)], "the dynamic profiles match the repo")


def doctor_terminal_files(d):
    kitty_dir = Path(os.environ.get("KITTY_CONFIG_DIRECTORY") or XDG_CONFIG / "kitty")
    terminals = [("Kitty", "kitty", kitty_dir, "zacess-{id}.conf", current_kitty),
                 ("Alacritty", "alacritty", XDG_CONFIG / "alacritty", "zacess-{id}.toml", current_alacritty),
                 ("Ghostty", "ghostty", XDG_CONFIG / "ghostty" / "themes", "zacess-{id}", current_ghostty),
                 ("Warp", "warp/themes", HOME / ".warp" / "themes", "zacess-{id}.yaml", None)]
    for tool, folder, installed_dir, pattern, reader in terminals:
        if not installed_dir.is_dir() or not (TERMINAL_THEMES / OS_FOLDER / folder).is_dir():
            continue
        if reader:
            d.setting(tool, reader())
        pairs = [(installed_dir / pattern.format(id=t.id), TERMINAL_THEMES / OS_FOLDER / folder / pattern.format(id=t.id))
                 for t in d.wanted]
        d.files(tool, pairs, f"the {' and '.join(t.name for t in d.wanted)} theme files match the repo")
    # Ptyxis keeps its palette in gsettings rather than a file, so only its setting is checked
    if PTYXIS_PALETTES.is_dir():
        d.setting("Ptyxis", current_ptyxis())


def doctor_tmux(d):
    conf = HOME / ".tmux.conf"
    repo = repo_copy(REPO_ROOT / "terminal" / "tmux", "tmux.conf")
    if not conf.exists() or repo is None:
        return
    d.setting("tmux", current_tmux())
    shown = d.now
    if "tmux" in d.pins:
        value = d.pins["tmux"]
        if value in DEFAULT_VALUES:
            return d.files("tmux", [(conf, repo)], "tmux.conf matches the repo (pinned to its own colours)")
        shown = pair_for(value)[3]
    theme_file = repo_copy(REPO_ROOT / "terminal" / "tmux", "themes", f"zacess-{shown.id}.conf")
    pairs = [(conf, repo)] + ([(TMUX_LINK, theme_file)] if theme_file else [])
    d.files("tmux", pairs, "tmux.conf and the linked theme file match the repo")
    if theme_file and shutil.which("tmux") and run("tmux", "list-sessions").returncode == 0:
        wanted = re.search(r'^set -g mode-style "([^"]*)"', theme_file.read_text(), re.M)
        got = run("tmux", "show", "-gv", "mode-style").stdout.strip()
        if wanted:
            same = set(got.split(",")) == set(wanted.group(1).split(","))
            d.line("tmux server", "ok" if same else "drift",
                   f"copy mode is {got}" + ("" if same else f", the theme file says {wanted.group(1)}"))


def doctor_xcode(d):
    clone = Path(os.environ.get("ZACESS_THEMES") or HOME / "dev" / "github" / "repos" / "zacess-themes")
    user = HOME / "Library" / "Developer" / "Xcode" / "UserData" / "FontAndColorThemes"
    if not MAC or not user.is_dir():
        return
    pairs = [(user / f.name, f) for f in sorted((EDITORS / "xcode" / "mac" / "Themes").glob("*.xcworkspacecolortheme"))]
    if (clone / "editors" / "xcode").is_dir():
        pairs += [(user / f.name, f) for f in sorted((clone / "editors" / "xcode").glob("*.xccolortheme"))]
        what = "the themes match the Zacess Themes clone and the saved workspace theme matches the repo"
    else:
        what = "the saved workspace theme matches the repo (no Zacess Themes clone to compare the rest with)"
    if pairs:
        d.files("Xcode", pairs, what)


def doctor_highlight(d):
    text = current_highlight()
    if text is None:
        return
    if "highlight" in d.pins:
        value = d.pins["highlight"]
        if value in DEFAULT_VALUES:
            return d.line("Highlight", "ok", f"pinned to the system's own: {text}")
        # a theme pin is checked against that theme's selection
        d = doctor_for_pin(d, value)
    if desktop_is_kde() and not MAC:
        ok = d.dark.name in text and d.light.name in text
        return d.line("Highlight", "ok" if ok else "drift", text)
    expected = selection_colour(d.now)[0]
    ok = expected in text
    d.line("Highlight", "ok" if ok else "drift", text + ("" if ok else f", {d.now.name}'s selection is {expected}"))


def doctor():
    fixed, dark, light, now = active_pair()
    d = Doctor(fixed, dark, light, now)
    print(f"{BOLD}zt state{RESET}: " + (f"fixed {now.name}" if fixed
                                        else f"following the system: {dark.name} or {light.name} (now {now.name})"))
    for check in (doctor_vscode, doctor_zed, doctor_jetbrains, doctor_neovim, doctor_apps, doctor_terminal_app,
                  doctor_iterm2, doctor_terminal_files, doctor_tmux, doctor_xcode, doctor_highlight):
        try:
            check(d)
        except Exception as error:  # one unreadable config is drift, never a crash
            d.line(check.__name__.replace("doctor_", ""), "drift", f"could not check: {error}")
    print(f"{DRIFT}{d.drift} drift{RESET}" if d.drift else f"{OK}no drift{RESET}")
    return 1 if d.drift else 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__.strip())
        return 0
    # pin and unpin come first: --all there means every pin, not every device
    if argv[0] == "pin":
        return pin(argv[1:])
    if argv[0] == "unpin":
        return unpin(argv[1:])
    every = "--all" in argv
    argv = [word for word in argv if word != "--all"]
    if not argv:
        print("Usage: zt <theme> --all or zt undo --all", file=sys.stderr)
        return 1
    command = argv[0]
    if command == "doctor":
        return doctor()
    if command == "highlight":
        if argv[1:] == ["default"]:
            restore_highlight()
            return 0
        if argv[1:]:
            print("Usage: zt highlight [default]", file=sys.stderr)
            return 1
        highlight(*active_pair())
        return 0
    if command == "list":
        current = STATE_FILE.read_text().split() if STATE_FILE.exists() else [DEFAULT_DARK]
        for row in THEMES:
            theme = Theme(row)
            mark = " *" if theme.id in current else ""
            print(f"  {theme.short:<11} {theme.name}{mark}")
        return 0
    if command == "current":
        if argv[1:] == ["terminals"]:
            show_current(set(TERMINALS))
            return 0
        if argv[1:]:
            app = find_app(argv[1])
            if not app:
                print(f"Unknown app: {argv[1]}", file=sys.stderr)
                return 1
            show_current({app})
            return 0
        show_current()
        return 0

    if command == "undo":
        return undo(every)
    if command == "sync":
        return sync()
    if command == "auto":
        dark = find_theme(argv[1]) if len(argv) > 1 else find_theme(DEFAULT_DARK)
        light = find_theme(argv[2]) if len(argv) > 2 else find_theme(DEFAULT_LIGHT)
        if not dark or not light:
            print("Unknown theme. Run zt list for the names.", file=sys.stderr)
            return 1
        state = f"auto {dark.id} {light.id}"
    else:
        fixed = find_theme(" ".join(argv))
        if not fixed:
            print(f"Unknown theme: {' '.join(argv)}. Run zt list for the names.", file=sys.stderr)
            return 1
        state = fixed.id
    before = current_state()
    apply_state(state)
    if every:
        send(state, before)
    return 0


def apply_state(state, quiet=False):
    """Switch every tool to a state file's text: a theme id or "auto <dark id> <light id>"."""
    words = state.split()
    if words and words[0] == "auto":
        dark = find_theme(words[1]) if len(words) > 1 else find_theme(DEFAULT_DARK)
        light = find_theme(words[2]) if len(words) > 2 else find_theme(DEFAULT_LIGHT)
        fixed = None
        now = dark if system_is_dark() else light
        heading = (f"{BOLD}Following the system{RESET}: {dark.name} in dark mode, {light.name} in light mode "
                   f"(now {now.appearance})")
    else:
        fixed = find_theme(state)
        if not fixed:
            return 1
        dark = fixed if fixed.dark else find_theme(DEFAULT_DARK)
        light = fixed if not fixed.dark else find_theme(DEFAULT_LIGHT)
        now = fixed
        heading = f"{BOLD}{fixed.name}{RESET} everywhere, not following the system"
    before = current_state()
    if before and before != state:
        PREVIOUS_FILE.parent.mkdir(parents=True, exist_ok=True)
        PREVIOUS_FILE.write_text(before + "\n")

    pins = read_pins()

    def run_tool(tool):
        _lines.buffer = []
        app = TOOL_APP.get(tool)
        try:
            if app in pins and app != "neovim":
                apply_pin(app, pins[app])
            else:
                # Neovim's state file is zt's own state, so it is written either way and the pin
                # is read by Neovim itself
                tool(fixed, dark, light, now)
                if app in pins:
                    _lines.buffer = [line for line in _lines.buffer if "Neovim" not in line]
                    neovim_pin_report(pins[app])
        except Exception as error:  # one broken config never stops the other tools
            report(tool.__name__, f"failed: {error}", False)
        return _lines.buffer

    if not quiet:
        print(heading)
        if pins:
            print(f"  {SKIP}pinned, kept on their own theme: {', '.join(sorted(pins))}{RESET}")
    # every tool edits its own files, so they all run at once: a switch takes as long as the
    # slowest tool rather than the sum of them all
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(TOOLS))) as pool:
        for lines in pool.map(run_tool, TOOLS):
            if not quiet:
                for line in lines:
                    print(line)
    return 0


def send(state, before):
    shared = shared_file()
    if shared is None:
        print("No OneDrive on this device, so only this device changed")
        return
    push = {"id": str(uuid.uuid4()), "state": state, "undo_of": None, "from": platform.node(),
            "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    write_atomic(shared, json.dumps(push))
    write_atomic(ALL_SEEN, push["id"])
    write_atomic(ALL_APPLIED, json.dumps({"id": push["id"], "previous": before}))
    print("Sent to every device: each one switches when a terminal next opens there")


def undo(every):
    if not every:
        previous = PREVIOUS_FILE.read_text().strip() if PREVIOUS_FILE.exists() else ""
        if not previous:
            print("Nothing to undo")
            return 0
        return apply_state(previous)
    shared = shared_file()
    push = read_json(shared) if shared else None
    if not push or push.get("undo_of"):
        print("Nothing to undo on every device")
        return 0
    entry = {"id": str(uuid.uuid4()), "state": "", "undo_of": push["id"], "from": platform.node(),
             "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    write_atomic(shared, json.dumps(entry))
    write_atomic(ALL_SEEN, entry["id"])
    applied = read_json(ALL_APPLIED) or {}
    if applied.get("id") == push["id"] and applied.get("previous"):
        apply_state(applied["previous"])
    print("Undone on every device: each one goes back to its own previous theme when a terminal next opens there")
    return 0


def sync():
    """Apply the latest --all push from another device once. Started silently at shell start."""
    shared = shared_file()
    push = read_json(shared) if shared else None
    seen = ALL_SEEN.read_text().strip() if ALL_SEEN.exists() else ""
    if not push or push.get("id") == seen:
        return 0
    # claimed first, so two terminals opening together never apply the same push twice
    write_atomic(ALL_SEEN, push["id"])
    if push.get("undo_of"):
        applied = read_json(ALL_APPLIED) or {}
        if applied.get("id") == push["undo_of"] and applied.get("previous"):
            apply_state(applied["previous"], quiet=True)
        return 0
    write_atomic(ALL_APPLIED, json.dumps({"id": push["id"], "previous": current_state()}))
    return apply_state(push["state"], quiet=True)

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
