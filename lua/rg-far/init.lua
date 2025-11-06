local M = {}

local init_windows_buffers = function()
  local pattern_bufnr = vim.api.nvim_create_buf(false, true)
  local pattern_winnr = vim.api.nvim_open_win(pattern_bufnr, true, {
    split = "right",
    win = 0,
  })
  vim.api.nvim_set_option_value("winbar", "Pattern", { win = pattern_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = pattern_winnr, })

  local flags_bufnr = vim.api.nvim_create_buf(false, true)
  local flags_winnr = vim.api.nvim_open_win(flags_bufnr, true, {
    split = "below",
    win = pattern_winnr,
  })
  vim.api.nvim_set_option_value("winbar", "Flags", { win = flags_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = flags_winnr, })

  local results_bufnr = vim.api.nvim_create_buf(false, true)
  local results_winnr = vim.api.nvim_open_win(results_bufnr, true, {
    split = "below",
    win = flags_winnr,
  })
  vim.api.nvim_set_option_value("winbar", "Results", { win = results_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = results_winnr, })

  vim.api.nvim_win_set_height(pattern_winnr, 1)
  vim.api.nvim_win_set_height(flags_winnr, 5)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(pattern_winnr), tostring(flags_winnr), tostring(results_winnr), },
    callback = function()
      if vim.api.nvim_win_is_valid(pattern_winnr) then vim.api.nvim_win_close(pattern_winnr, true) end
      if vim.api.nvim_win_is_valid(flags_winnr) then vim.api.nvim_win_close(flags_winnr, true) end
      if vim.api.nvim_win_is_valid(results_winnr) then vim.api.nvim_win_close(results_winnr, true) end
    end
    ,
  })

  vim.api.nvim_set_current_win(pattern_winnr)

  return {
    pattern_bufnr = pattern_bufnr,
    pattern_winnr = pattern_winnr,
    flags_bufnr = flags_bufnr,
    flags_winnr = flags_winnr,
    results_bufnr = results_bufnr,
    results_winnr = results_winnr,
  }
end

M.open = function()
  local nrs = init_windows_buffers()
end
M.open()

return M
