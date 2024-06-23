return {
  'lukas-reineke/indent-blankline.nvim',
  main = 'ibl',
  config = function()
    local hooks = require 'ibl.hooks'
    hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
      vim.api.nvim_set_hl(0, 'Indent', { fg = '#7F7F7F' })
      vim.api.nvim_set_hl(0, 'CurrentScope', { fg = '#fc5ef3' })
    end)

    require('ibl').setup {
      indent = { highlight = { 'Indent' } },
      scope = { highlight = { 'CurrentScope' } },
    }
  end,
}
