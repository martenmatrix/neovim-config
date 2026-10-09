return {
  j = { rhs = 'h', desc = 'Left' },
  k = {
    rhs = function()
      return vim.v.count == 0 and 'gj' or 'j'
    end,
    expr = true,
    desc = 'Down',
  },
  l = {
    rhs = function()
      return vim.v.count == 0 and 'gk' or 'k'
    end,
    expr = true,
    desc = 'Up',
  },
  [';'] = { rhs = 'l', desc = 'Right' },
  h = { rhs = ';', desc = 'Repeat last f/t/F/T' },
}
