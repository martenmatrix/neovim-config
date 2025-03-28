return {
  'kylechui/nvim-surround',
  version = '*', -- Use for stability; omit to use `main` branch for the latest features
  event = 'VeryLazy',
  config = function()
    require('nvim-surround').setup {
      keymaps = {
        insert = '<C-g>s',
        insert_line = '<C-g>S',
        normal = '<leader>sys',
        normal_cur = '<leader>syss',
        normal_line = '<leader>syS',
        normal_cur_line = '<leader>sySS',
        visual = '<leader>sS',
        visual_line = '<leader>sgS',
        delete = '<leader>sds',
        change = '<leader>scs',
        change_line = '<leader>scS',
      },
    }
  end,
}
