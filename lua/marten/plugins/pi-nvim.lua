return {
  "carderne/pi-nvim",
  opts = {
    set_default_keymaps = false,
  },
  keys = {
    { "<leader>ap",  "<cmd>Pi<cr>",              desc = "Ask pi" },
    { "<leader>aps", "<cmd>PiSendSelection<cr>", mode = "v", desc = "Send selection to pi" },
    { "<leader>apb", "<cmd>PiSendBuffer<cr>",    desc = "Send buffer to pi" },
    { "<leader>apf", "<cmd>PiSendFile<cr>",      desc = "Send file to pi" },
    { "<leader>apl", "<cmd>PiSessions<cr>",      desc = "Pi sessions" },
    { "<leader>app", "<cmd>PiPing<cr>",          desc = "Ping pi" },
    { "<leader>apt", "<cmd>PiToggle<cr>",        desc = "Toggle pi terminal" },
  },
  config = function(_, opts)
    require("pi-nvim").setup(opts)

    local pi_buf = nil
    local pi_win = nil

    local function start_pi()
      vim.cmd("botright split")
      pi_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_height(pi_win, 20)
      vim.fn.jobstart("pi", {
        term = true,
        on_exit = function()
          pi_buf = nil
          pi_win = nil
        end,
      })
      pi_buf = vim.api.nvim_get_current_buf()
      vim.cmd("startinsert")

      -- auto-hide once the socket appears (pi session ready)
      local timer = vim.uv.new_timer()
      timer:start(1000, 1000, vim.schedule_wrap(function()
        local files = vim.fn.glob("/tmp/pi-nvim-sockets/*.info", false, true)
        if #files > 0 then
          timer:close()
          if pi_win and vim.api.nvim_win_is_valid(pi_win) then
            vim.api.nvim_win_close(pi_win, false)
            pi_win = nil
          end
        end
      end))
    end

    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = function()
        vim.schedule(start_pi)
      end,
    })

    vim.api.nvim_create_user_command("PiToggle", function()
      if pi_win and vim.api.nvim_win_is_valid(pi_win) then
        vim.api.nvim_win_close(pi_win, false)
        pi_win = nil
        return
      end

      if not (pi_buf and vim.api.nvim_buf_is_valid(pi_buf)) then
        start_pi()
        return
      end

      vim.cmd("botright split")
      pi_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_height(pi_win, 20)
      vim.api.nvim_win_set_buf(pi_win, pi_buf)
      vim.cmd("startinsert")
    end, {})
  end,
}
