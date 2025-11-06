local M = {}

local ns_id = vim.api.nvim_create_namespace "rg-far"

local init_windows_buffers = function()
  local stderr_bufnr = vim.api.nvim_create_buf(false, true)
  local stderr_winnr = vim.api.nvim_open_win(stderr_bufnr, true, {
    split = "right",
    win = 0,
  })
  vim.api.nvim_set_option_value("winbar", "Rg stderr", { win = stderr_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = stderr_winnr, })

  local input_bufnr = vim.api.nvim_create_buf(false, true)
  local input_winnr = vim.api.nvim_open_win(input_bufnr, true, {
    split = "below",
    win = stderr_winnr,
  })
  vim.api.nvim_set_option_value("winbar", "Input", { win = input_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = input_winnr, })

  local results_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", }, {
    buffer = results_bufnr,
    callback = function()
      vim.cmd [[syntax match ConcealPipe /^[^|]*|[^|]*|/ conceal]]
    end,
  })
  local results_winnr = vim.api.nvim_open_win(results_bufnr, true, {
    split = "below",
    win = input_winnr,
  })
  vim.api.nvim_set_option_value("winbar", "Results", { win = results_winnr, })
  vim.api.nvim_set_option_value("statusline", " ", { win = results_winnr, })
  vim.api.nvim_set_option_value("conceallevel", 2, { win = results_winnr, })
  vim.api.nvim_set_option_value("concealcursor", "nvic", { win = results_winnr, })

  vim.api.nvim_win_set_height(stderr_winnr, 3)
  vim.api.nvim_win_set_height(input_winnr, 8)
  vim.api.nvim_win_set_width(results_winnr, math.floor(vim.o.columns * 2 / 3))

  vim.api.nvim_set_option_value("filetype", "rg-far", { buf = stderr_bufnr, })
  vim.api.nvim_set_option_value("filetype", "rg-far", { buf = input_bufnr, })
  vim.api.nvim_set_option_value("filetype", "rg-far", { buf = results_bufnr, })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(stderr_winnr), tostring(input_winnr), tostring(results_winnr), },
    callback = function()
      if vim.api.nvim_win_is_valid(input_winnr) then vim.api.nvim_win_close(input_winnr, true) end
      if vim.api.nvim_win_is_valid(results_winnr) then vim.api.nvim_win_close(results_winnr, true) end
      if vim.api.nvim_win_is_valid(stderr_winnr) then vim.api.nvim_win_close(stderr_winnr, true) end
    end,
  })

  vim.api.nvim_set_current_win(input_winnr)

  return {
    stderr_bufnr = stderr_bufnr,
    stderr_winnr = stderr_winnr,
    input_bufnr = input_bufnr,
    input_winnr = input_winnr,
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
      local find = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 0, 1, false)[1]
      local replace_flag = (function()
        local replace = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 1, 2, false)
        if #replace == 0 then return {} end
        if #replace == 1 and replace[1] == "" then return {} end
        return { "--replace", replace[1], }
      end)()
      vim.print(replace_flag)

      local flags = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 2, -1, false)
      flags = vim.tbl_filter(function(flag) return flag ~= "" end, flags)
      if #flags == 0 then flags = {} end

      local args = vim.iter {
            "rg",
            "--with-filename",
            "--no-heading",
            "--line-number",
            replace_flag,
            "--field-match-separator",
            "|",
            flags,
            "--",
            find,
          }
          :flatten()
          :totable()

      local rg_cmd = table.concat(args, " ")

      vim.system(args, {},
        function(out)
          if out.code ~= 0 then
            vim.schedule(function()
              local stderr = vim.iter { rg_cmd, vim.split(out.stderr or "", "\n"), }:flatten():totable()
              vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, stderr)
            end)
            return
          end
          if not out.stdout then return end
          vim.schedule(function()
            vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, { rg_cmd, })
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
    buffer = nrs.input_bufnr,
    callback = populate_results,
  })
end
M.open()

return M
