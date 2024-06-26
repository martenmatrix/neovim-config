vim.g.mapleader = ' '

local keymap = vim.keymap

-- window management
keymap.set('n', '<leader>sv', '<C-w>v', { desc = 'Split window vertically' }) -- split window vertically
keymap.set('n', '<leader>sh', '<C-w>s', { desc = 'Split window horizontally' }) -- split window horizontally
keymap.set('n', '<leader>se', '<C-w>=', { desc = 'Make splits equal size' }) -- make split windows equal width & height
keymap.set('n', '<leader>sx', '<cmd>close<CR>', { desc = 'Close current split' }) -- close current split window

-- could also multiply current window size with a factor https://vim.fandom.com/wiki/Resize_splits_more_quicklyj
keymap.set('n', '<leader>s+v', '<cmd>vertical resize +10<CR>', { desc = 'Vertically increase size of current split' })
keymap.set('n', '<leader>s-v', '<cmd>vertical resize -10<CR>', { desc = 'Vertically decrease size of current split' })
keymap.set('n', '<leader>s+h', '<cmd>resize +10<CR>', { desc = 'Horizontally increase size of current split' })
keymap.set('n', '<leader>s-h', '<cmd>resize -10<CR>', { desc = 'Horizontally decrease size of current split' })

keymap.set('n', '<leader>to', '<cmd>tabnew<CR>', { desc = 'Open new tab' }) -- open new tab
keymap.set('n', '<leader>tx', '<cmd>tabclose<CR>', { desc = 'Close current tab' }) -- close current tab
keymap.set('n', '<leader>tn', '<cmd>tabn<CR>', { desc = 'Go to next tab' }) --  go to next tab
keymap.set('n', '<leader>tN', '<cmd>tabp<CR>', { desc = 'Go to previous tab' }) --  go to previous tab
keymap.set('n', '<leader>tf', '<cmd>tabnew %<CR>', { desc = 'Open current buffer in new tab' }) --  move current buffer to new tab

keymap.set('n', 'U', '<cmd>redo<CR>', { desc = 'Redo last change' }) -- Redo changes like an undo with U

-- Map Alt + 1-9 to switch to tab 1-9
for i = 1, 9 do
  vim.keymap.set(
    'n',
    '<leader>' .. i .. '',
    ':tabn ' .. i .. '<CR>',
    { silent = true, desc = 'Move to tab ' .. i .. '' }
  )
end
