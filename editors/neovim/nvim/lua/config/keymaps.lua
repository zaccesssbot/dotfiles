local map = vim.keymap.set

map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window" })

-- Ctrl+H/J/K/L move between splits and tmux panes through vim-tmux-navigator, set up in
-- plugins/navigator.lua.

-- Keep the cursor centred while jumping half a page, easier to track on a low-vision setup.
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

-- Move a visual selection up or down instead of retyping it.
map("v", "J", ":m '>+1<cr>gv=gv")
map("v", "K", ":m '<-2<cr>gv=gv")

-- Space x e: the whole error on this line in a float, for a message too long to read at the end
-- of the line. Beside Trouble's Space x x and Space x b.
map("n", "<leader>xe", function()
	vim.diagnostic.open_float({ scope = "line" })
end, { desc = "Show this line's error" })

-- Space c r: run the current file in the shell pane below, saved first. In tmux (psmux on Windows)
-- the command is typed into the pane under Neovim, so its output stays beside the code and the pane
-- stays a shell afterwards; with no pane below, one is split off at 30 percent. Outside tmux it
-- runs in a terminal split at the bottom. psmux has no {down-of} target and numbers pane ids per
-- session, so the pane below is reached by moving to it and back rather than by naming it.
local windows = vim.fn.has("win32") == 1

-- every path is quoted for the shell in the pane: PowerShell on Windows, a POSIX shell elsewhere
local function quote(path)
	if windows then
		return "'" .. path:gsub("'", "''") .. "'"
	end
	return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- PowerShell runs a quoted path only through its call operator
local function exec(path)
	return (windows and "& " or "") .. quote(path)
end

local function compiled(compiler)
	return function(file, stem)
		return ("%s %s -o %s && %s"):format(compiler, quote(file), quote(stem), exec(stem))
	end
end

local runners = {
	python = function(file)
		return (windows and "python " or "python3 ") .. quote(file)
	end,
	c = compiled("gcc"),
	cpp = compiled("g++"),
	java = function(file)
		return "java " .. quote(file)
	end,
	javascript = function(file)
		return "node " .. quote(file)
	end,
	typescript = function(file)
		return "npx tsx " .. quote(file)
	end,
	lua = function(file)
		return "lua " .. quote(file)
	end,
	sh = function(file)
		return "bash " .. quote(file)
	end,
	bash = function(file)
		return "bash " .. quote(file)
	end,
	zsh = function(file)
		return "zsh " .. quote(file)
	end,
	ps1 = function(file)
		return "pwsh -File " .. quote(file)
	end,
	rust = function(file)
		local manifest = vim.fs.find("Cargo.toml", { upward = true, path = vim.fs.dirname(file) })[1]
		return manifest and ("cargo run --manifest-path " .. quote(manifest)) or nil
	end,
	go = function(file)
		return "go run " .. quote(file)
	end,
	php = function(file)
		return "php " .. quote(file)
	end,
}

local function tmux(...)
	local result = vim.system({ "tmux", ... }, { text = true }):wait()
	return result.code == 0 and vim.trim(result.stdout or "") or nil
end

local function run_in_pane(command, folder)
	local here = tmux("display-message", "-p", "#{pane_id}")
	tmux("select-pane", "-D")
	-- tmux wraps to the same pane when nothing is below it, so a new pane is split off instead
	if tmux("display-message", "-p", "#{pane_id}") == here then
		tmux("split-window", "-v", "-l", "30%", "-c", folder)
	end
	tmux("send-keys", command, "Enter")
	tmux("last-pane")
end

map("n", "<leader>cr", function()
	local file = vim.api.nvim_buf_get_name(0)
	local runner = runners[vim.bo.filetype]
	local command = runner and file ~= "" and runner(file, vim.fn.fnamemodify(file, ":r"))
	if not command then
		vim.notify("no runner for " .. (vim.bo.filetype ~= "" and vim.bo.filetype or "this file"), vim.log.levels.WARN)
		return
	end
	if vim.bo.modified and vim.bo.buftype == "" then
		vim.cmd("silent write")
	end
	local folder = vim.fs.dirname(file)
	if vim.env.TMUX then
		run_in_pane(command, folder)
	else
		vim.cmd("botright 12new")
		local shell = windows and { "pwsh", "-NoLogo", "-NoExit", "-Command", command } or { vim.o.shell, "-c", command }
		vim.fn.jobstart(shell, { term = true, cwd = folder })
		vim.cmd("startinsert")
	end
end, { desc = "Run this file in the pane below" })
