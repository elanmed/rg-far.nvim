local M = {}

local ns_id = vim.api.nvim_create_namespace "rg-far"

local init_windows_buffers = function()
  local stderr_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(stderr_bufnr, 0, -1, false, { "[No error]", })
  local stderr_winnr = vim.api.nvim_open_win(stderr_bufnr, true, {
    split = "right",
    win = 0,
  })
  vim.api.nvim_set_option_value("winbar", "Rg stderr", { win = stderr_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = stderr_winnr, })

  local pattern_bufnr = vim.api.nvim_create_buf(false, true)
  local pattern_winnr = vim.api.nvim_open_win(pattern_bufnr, true, {
    split = "below",
    win = stderr_winnr,
  })
  vim.api.nvim_set_option_value("winbar", "Pattern", { win = pattern_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = pattern_winnr, })

  local flags_bufnr = vim.api.nvim_create_buf(false, true)
  local flags_winnr = vim.api.nvim_open_win(flags_bufnr, true, {
    split = "below",
    win = pattern_winnr,
  })
  vim.api.nvim_set_option_value("winbar", "Flags (one per line)", { win = flags_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = flags_winnr, })

  local results_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", }, {
    buffer = results_bufnr,
    callback = function()
      vim.cmd [[syntax match ConcealPipe /^[^|]*|[^|]*|/ conceal]]
    end,
  })
  local results_winnr = vim.api.nvim_open_win(results_bufnr, true, {
    split = "below",
    win = flags_winnr,
  })
  vim.api.nvim_set_option_value("winbar", "Results", { win = results_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = results_winnr, })
  vim.api.nvim_set_option_value("conceallevel", 2, { win = results_winnr, })
  vim.api.nvim_set_option_value("concealcursor", "nvic", { win = results_winnr, })

  vim.api.nvim_win_set_height(stderr_winnr, 1)
  vim.api.nvim_win_set_height(pattern_winnr, 1)
  vim.api.nvim_win_set_height(flags_winnr, 5)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(stderr_winnr), tostring(pattern_winnr), tostring(flags_winnr), tostring(results_winnr), },
    callback = function()
      if vim.api.nvim_win_is_valid(pattern_winnr) then vim.api.nvim_win_close(pattern_winnr, true) end
      if vim.api.nvim_win_is_valid(flags_winnr) then vim.api.nvim_win_close(flags_winnr, true) end
      if vim.api.nvim_win_is_valid(results_winnr) then vim.api.nvim_win_close(results_winnr, true) end
      if vim.api.nvim_win_is_valid(stderr_winnr) then vim.api.nvim_win_close(stderr_winnr, true) end
    end
    ,
  })

  vim.api.nvim_set_current_win(pattern_winnr)

  return {
    stderr_bufnr = stderr_bufnr,
    stderr_winnr = stderr_winnr,
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

  local timer_id = nil
  local populate_results = function()
    if timer_id then
      vim.fn.timer_stop(timer_id)
    end

    timer_id = vim.fn.timer_start(250, function()
      local pattern = vim.api.nvim_win_call(nrs.pattern_winnr, vim.api.nvim_get_current_line)
      local flags = vim.api.nvim_buf_get_lines(nrs.flags_bufnr, 0, -1, false)
      if #flags == 1 and flags[1] == "" then
        flags = {}
      end

      local args = vim.iter {
            "rg",
            "--with-filename",
            "--no-heading",
            "--line-number",
            "--field-match-separator",
            "|",
            flags,
            "--",
            pattern,
          }
          :flatten()
          :totable()

      vim.system(args, {},
        function(out)
          if out.code ~= 0 then
            vim.schedule(function()
              local stderr = out.stderr or ""
              vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, vim.split(stderr, "\n"))
            end)
            return
          end
          if not out.stdout then return end
          vim.schedule(function()
            vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, { "[No error]", })
          end)

          local lines = vim.split(out.stdout, "\n")
          vim.schedule(function()
            table.insert(lines, 1, "")
            vim.api.nvim_buf_set_lines(nrs.results_bufnr, 0, -1, false, lines)
          end)
          vim.schedule(function()
            local prev_filename = nil
            for idx_1i, line in ipairs(lines) do
              local filename = unpack(vim.split(line, "|"))
              if filename ~= prev_filename then
                prev_filename = filename
                local idx_0i = idx_1i - 1
                vim.api.nvim_buf_set_extmark(nrs.results_bufnr, ns_id, idx_0i, 0, {
                  virt_lines = {
                    { { "", "", }, },
                    { { filename, "Search", }, },
                  },
                  virt_lines_above = true,
                })
              end
            end
          end)
        end)
    end)
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", }, {
    buffer = nrs.pattern_bufnr,
    callback = populate_results,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", }, {
    buffer = nrs.flags_bufnr,
    callback = populate_results,
  })
end
M.open()

return M
