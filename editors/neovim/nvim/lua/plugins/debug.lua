-- A debugger: breakpoints, stepping and a panel of variables, the call stack and watches, the same
-- in every language. mason-nvim-dap installs a language's debug adapter through Mason (already set
-- up for the language servers) and sets it up, so :DapInstall python (or codelldb, js and so on)
-- is the only step per language. The panel opens when a session starts and closes when it ends.
return {
	"mfussenegger/nvim-dap",
	dependencies = {
		{ "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
		{ "jay-babu/mason-nvim-dap.nvim", dependencies = { "williamboman/mason.nvim" } },
	},
	keys = {
		{ "<leader>d", nil, desc = "Debug" },
		{ "<F5>", function() require("dap").continue() end, desc = "Start or continue debugging" },
		{ "<F10>", function() require("dap").step_over() end, desc = "Step over" },
		{ "<F11>", function() require("dap").step_into() end, desc = "Step into" },
		{ "<F12>", function() require("dap").step_out() end, desc = "Step out" },
		{ "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Breakpoint on this line" },
		{ "<leader>dc", function() require("dap").set_breakpoint(vim.fn.input("Stop when: ")) end, desc = "Breakpoint with a condition" },
		{ "<leader>du", function() require("dapui").toggle() end, desc = "Show or hide the debug panel" },
		{ "<leader>dr", function() require("dap").repl.toggle() end, desc = "Debug console" },
		{ "<leader>dt", function() require("dap").terminate() end, desc = "Stop debugging" },
	},
	config = function()
		local dap, dapui = require("dap"), require("dapui")
		dapui.setup()
		require("mason-nvim-dap").setup({ handlers = {} })
		dap.listeners.after.event_initialized["dapui"] = function() dapui.open() end
		dap.listeners.before.event_terminated["dapui"] = function() dapui.close() end
		dap.listeners.before.event_exited["dapui"] = function() dapui.close() end
	end,
}
