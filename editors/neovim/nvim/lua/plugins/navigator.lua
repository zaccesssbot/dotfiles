-- Ctrl+H/J/K/L move between Neovim splits and tmux panes as one set. On macOS and Linux the tmux
-- half is the same plugin loaded in tmux.conf; outside tmux the keys simply move between splits.
--
-- Windows runs psmux, which needs two differences, so this one file serves every system:
-- * psmux cannot load the plugin through TPM, so terminal\tmux\windows\tmux.conf writes its half
--   out. The plugin's Neovim half reaches tmux through the socket path in $TMUX (tmux -S
--   /tmp/...), which psmux does not take. At the edge of Neovim's splits these keys ask psmux to
--   move with a plain select-pane instead, which acts on Neovim's own session. The plugin stays
--   listed so every machine keeps the same plugin set and lock file.
-- * psmux names a pane's command after its newest child process, so once a language server
--   starts the pane reads as node rather than nvim and tmux.conf could not tell Neovim has the
--   pane. Neovim marks its own pane with @is-nvim instead, cleared when it quits or is suspended.
local windows = vim.fn.has("win32") == 1

local function mark(on)
	if vim.env.TMUX then
		vim.system({ "tmux", "set", on and "-p" or "-pu", "@is-nvim", on and "1" or nil }):wait()
	end
end

local pane = { h = "-L", j = "-D", k = "-U", l = "-R" }

local function go(key)
	local before = vim.api.nvim_get_current_win()
	vim.cmd("wincmd " .. key)
	if vim.api.nvim_get_current_win() == before and vim.env.TMUX then
		vim.system({ "tmux", "select-pane", pane[key] }):wait()
	end
end

local keys
if windows then
	keys = {
		{ "<C-h>", function() go("h") end, desc = "Go to the split or pane on the left" },
		{ "<C-j>", function() go("j") end, desc = "Go to the split or pane below" },
		{ "<C-k>", function() go("k") end, desc = "Go to the split or pane above" },
		{ "<C-l>", function() go("l") end, desc = "Go to the split or pane on the right" },
	}
else
	keys = {
		{ "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Go to the split or pane on the left" },
		{ "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Go to the split or pane below" },
		{ "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Go to the split or pane above" },
		{ "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to the split or pane on the right" },
	}
end

return {
	"christoomey/vim-tmux-navigator",
	init = function()
		if not windows then
			return
		end
		vim.g.tmux_navigator_no_mappings = 1
		local group = vim.api.nvim_create_augroup("PaneMark", { clear = true })
		vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, { group = group, callback = function() mark(true) end })
		vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, { group = group, callback = function() mark(false) end })
	end,
	cmd = { "TmuxNavigateLeft", "TmuxNavigateDown", "TmuxNavigateUp", "TmuxNavigateRight" },
	keys = keys,
}
