-- A side-by-side view of what changed: every changed file with its diff, a file's history and
-- merge conflicts in three panes. Lazygit stays the place to stage and commit; this is for reading
-- a change inside Neovim.
return {
	"sindrets/diffview.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
	keys = {
		{ "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Changes since the last commit" },
		{ "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "History of this file" },
		{ "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "History of the project" },
		{ "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Close the diff view" },
	},
	opts = {},
}
