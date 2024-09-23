return {
	"sbdchd/neoformat",

	config = function()
		-- use stylua for lua formatting
		vim.g.neoformat_enabled_lua = { "stylua" }

		vim.g.neoformat_lua_stylua = {
			exe = "stylua",
			-- read from stdin
			args = { "-s" },
			stdin = true,
		}
		-- auto-format lua on save
		-- create group, which clears itself after config-reload to prevent autocmd duplicates
		local format_group = vim.api.nvim_create_augroup("FormatGroup", { clear = true })
		vim.api.nvim_create_autocmd("BufWritePre", {
			group = format_group,
			pattern = "*.lua",
			callback = function()
				vim.cmd("Neoformat")
			end,
		})
	end,
}
