-- use tree-style view in Netrw file explorer
vim.cmd 'let g:netrw_liststyle = 3'

-- disable unused remote-plugin providers to keep :checkhealth clean
-- (no plugin in this config uses perl or ruby remote plugins)
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

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

-- higlight current cursor line
opt.cursorline = true

-- enable 24-bit RGB colors so colorschemes render with true color
opt.termguicolors = true

-- use system clipboard as default register
opt.clipboard:append 'unnamedplus'

-- split vertical window to the right
opt.splitright = true
-- split horizontal window to the bottom
opt.splitbelow = true

vim.g.markdown_fenced_languages = {
  'ts=typescript',
}
