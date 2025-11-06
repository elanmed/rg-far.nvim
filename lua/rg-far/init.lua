local M = {}


M.open = function()
  local pattern_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = pattern_bufnr, })
  -- vim.api.nvim_buf_set_name(pattern_bufnr, "Pattern")
  local pattern_winnr = vim.api.nvim_open_win(pattern_bufnr, true, {
    split = "right",
    win = 0,
  })

  local flags_bufnr = vim.api.nvim_create_buf(false, true)
  -- vim.api.nvim_buf_set_name(flags_bufnr, "Flags")
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = flags_bufnr, })
  local flags_winnr = vim.api.nvim_open_win(flags_bufnr, true, {
    split = "below",
    win = pattern_winnr,
  })

  local results_bufnr = vim.api.nvim_create_buf(false, true)
  -- vim.api.nvim_buf_set_name(results_bufnr, "Results")
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = results_bufnr, })
  local results_winnr = vim.api.nvim_open_win(results_bufnr, true, {
    split = "below",
    win = flags_winnr,
  })

  vim.api.nvim_win_set_height(pattern_winnr, 1)
  vim.api.nvim_win_set_height(flags_winnr, 5)

  local close_all_wins = function()
    if vim.api.nvim_win_is_valid(pattern_winnr) then vim.api.nvim_win_close(pattern_winnr, true) end
    if vim.api.nvim_win_is_valid(flags_winnr) then vim.api.nvim_win_close(flags_winnr, true) end
    if vim.api.nvim_win_is_valid(results_winnr) then vim.api.nvim_win_close(results_winnr, true) end
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(pattern_winnr), tostring(flags_winnr), tostring(results_winnr), },
    callback = close_all_wins,
  })

  vim.api.nvim_set_current_win(pattern_winnr)
end
-- M.open()

return M
