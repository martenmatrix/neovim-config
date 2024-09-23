-- use tree-style view in Netrw file explorer
vim.cmd("let g:netrw_liststyle = 3")

local opt = vim.opt

-- display line numbers
opt.number = true
-- display line numbers below and above current line relative
opt.relativenumber = true

-- use spaces instead of tabs
vim.opt.expandtab = true
-- number of spaces when pressing tab
opt.softtabstop = 2
-- number of spaces for auto-indent
opt.shiftwidth = 2
-- copy indent from current line when pressing enter
opt.autoindent = true
-- do not wrap text, if it exceeds window with
opt.wrap = false


-- searching is not case-sensitive
opt.ignorecase = true
-- when using mixed case while searching, SEARCHING IS CASE-SENSITIVE
opt.smartcase = true
