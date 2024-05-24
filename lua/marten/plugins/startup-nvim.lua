return {
  'startup-nvim/startup.nvim',
  config = function()
    require('startup').setup {
      header = {
        type = 'text',
        align = 'center',
        fold_section = false,
        title = 'Header',
        margin = 0,
        content = require('startup.headers').hydra_header,
        highlight = 'Statement',
        default_color = '',
        oldfiles_amount = 0,
      },
      quote = {
        type = 'text',
        oldfiles_directory = false,
        align = 'center',
        fold_section = false,
        title = 'Quote',
        margin = 5,
        content = require('startup.functions').quote(),
        highlight = 'Constant',
        default_color = '',
        oldfiles_amount = 0,
      },
      time = {
        type = 'text',
        content = function()
          local clock = ' ' .. os.date '%H:%M'
          local date = ' ' .. os.date '%d-%m-%y'
          return { clock, date }
        end,
        oldfiles_directory = false,
        align = 'center',
        fold_section = false,
        title = '',
        margin = 0,
        highlight = 'TSString',
        default_color = '#FFFFFF',
        oldfiles_amount = 10,
      },
      parts = {
        'time',
        'header',
        'quote',
      },
    }
  end,
}
