return {
  'folke/tokyonight.nvim',
  lazy = false,
  priority = 1000,
  opts = {},
  config = function()
    require('tokyonight').setup {
      on_highlights = function(hl)
        hl.LineNrAbove = {
          fg = '#6ab8ff',
        }
        hl.LineNrBelow = {
          fg = '#ff6188',
        }
      end,
    }
    vim.cmd [[colorscheme tokyonight]]
  end,
}
