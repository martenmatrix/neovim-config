return {
  'neanias/everforest-nvim',
  version = false,
  lazy = false,
  priority = 1000,
  config = function()
    require('everforest').setup {
      on_highlights = function(highlights, palette)
        local dark = vim.o.background == 'dark'
        local added = dark and '#56b4e9' or '#006b9f'
        local removed = dark and '#e69f00' or '#8f5900'

        highlights.DiffAdd = { bg = dark and '#193b50' or '#d4edfc' }
        highlights.DiffDelete = { bg = dark and '#584215' or '#ffedbf', underline = true }
        highlights.DiffChange = { bg = palette.bg_purple }
        highlights.DiffText = { fg = '#1e2326', bg = '#56b4e9', bold = true }
        highlights.DiffTextDelete = { fg = '#1e2326', bg = '#e69f00', bold = true, underline = true }
        highlights.Added = { fg = added }
        highlights.Removed = { fg = removed, underline = true }
        highlights.Changed = { fg = palette.purple }

        for group, target in pairs {
          DiffTextAdd = 'DiffText',
          CodeCompanionDiffAdd = 'DiffAdd',
          CodeCompanionDiffDelete = 'DiffDelete',
          CodeCompanionDiffText = 'DiffText',
          CodeCompanionDiffTextDelete = 'DiffTextDelete',
          CodeCompanionCodeReviewAdded = 'Added',
          CodeCompanionCodeReviewRemoved = 'Removed',
          GitSignsAdd = 'Added',
          GitSignsAddNr = 'Added',
          GitSignsUntracked = 'Added',
          GitSignsDelete = 'Removed',
          GitSignsDeleteNr = 'Removed',
          GitSignsChange = 'Changed',
          GitSignsChangeNr = 'Changed',
          GitSignsChangedelete = 'Changed',
          GitSignsAddInline = 'DiffText',
          GitSignsDeleteInline = 'DiffTextDelete',
          GitSignsChangeInline = 'DiffText',
        } do
          highlights[group] = { link = target }
        end
      end,
    }

    vim.cmd [[colorscheme everforest]]
  end,
}
