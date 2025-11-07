local M = {}

local ns_id = vim.api.nvim_create_namespace "rg-far"
local global_batch_id = 0

--- @class RunBatchOpts
--- @field fn function
--- @field on_complete? function

--- @param opts RunBatchOpts
local run_batch = function(opts)
  local co = coroutine.create(opts.fn)

  local function step()
    coroutine.resume(co)
    if coroutine.status(co) == "suspended" then
      vim.schedule(step)
    elseif opts.on_complete then
      opts.on_complete()
    end
  end

  step()
end

--- @class ReplaceOpts
--- @field stderr_bufnr number
--- @field input_bufnr number
--- @field results_bufnr number
--- @param opts ReplaceOpts
local replace = function(opts)
  local lines = vim.api.nvim_buf_get_lines(opts.results_bufnr, 0, -1, false)
  local option = vim.fn.confirm(("[rg-far] Apply %d replacements?"):format(#lines), "&Yes\n&No", 2)
  if option ~= 1 then
    vim.notify("[rg-far] Aborting replace", vim.log.levels.INFO)
    return
  end

  run_batch {
    fn = function()
      vim.bo[opts.stderr_bufnr].modifiable = false
      vim.bo[opts.input_bufnr].modifiable = false
      vim.bo[opts.results_bufnr].modifiable = false

      for idx, line in ipairs(lines) do
        if line == "" then goto continue end

        local filename, row_1i, text = unpack(vim.split(line, "|"))
        row_1i = tonumber(row_1i)
        local row_0i = row_1i - 1

        local bufnr = vim.fn.bufnr(filename)
        if bufnr == -1 then
          local file_lines = vim.fn.readfile(filename)
          file_lines[row_1i] = text
          vim.fn.writefile(file_lines, filename)
        else
          vim.api.nvim_buf_set_lines(bufnr, row_0i, row_0i + 1, false, { text, })
          vim.api.nvim_buf_call(bufnr, vim.cmd.write)
        end

        if idx % 50 == 0 then
          coroutine.yield()
        end

        ::continue::
      end
    end,

    on_complete = function()
      vim.notify("[rg-far] Replace complete", vim.log.levels.INFO)
      vim.bo[opts.stderr_bufnr].modifiable = true
      vim.bo[opts.input_bufnr].modifiable = true
      vim.bo[opts.results_bufnr].modifiable = true
    end,
  }
end

local init_windows_buffers = function()
  local stderr_bufnr = vim.api.nvim_create_buf(false, true)
  local stderr_winnr = vim.api.nvim_open_win(stderr_bufnr, true, {
    split = "right",
    win = 0,
  })
  vim.bo[stderr_bufnr].modifiable = false
  vim.wo[stderr_winnr].winbar = "Rg stderr"
  vim.wo[stderr_winnr].statusline = " "

  local input_bufnr = vim.api.nvim_create_buf(false, true)
  local input_winnr = vim.api.nvim_open_win(input_bufnr, true, {
    split = "below",
    win = stderr_winnr,
  })
  vim.wo[input_winnr].winbar = "Input"
  vim.wo[input_winnr].statusline = " "
  vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, false, { "", "", "", })

  vim.api.nvim_buf_set_extmark(input_bufnr, ns_id, 0, 0, {
    virt_lines = {
      { { "Find", "ModeMsg", }, },
    },
  })
  vim.api.nvim_buf_set_extmark(input_bufnr, ns_id, 1, 0, {
    virt_lines = {
      { { "Replace", "ModeMsg", }, },
    },
  })
  vim.api.nvim_buf_set_extmark(input_bufnr, ns_id, 2, 0, {
    virt_lines = {
      { { "Flags (one per line)", "ModeMsg", }, },
    },
  })

  local results_bufnr = vim.api.nvim_create_buf(false, true)
  local results_winnr = vim.api.nvim_open_win(results_bufnr, true, {
    split = "below",
    win = input_winnr,
  })
  vim.wo[results_winnr].winbar = "Results"
  vim.wo[results_winnr].statusline = " "
  vim.wo[results_winnr].conceallevel = 2
  vim.wo[results_winnr].concealcursor = "nvic"

  vim.api.nvim_win_set_height(stderr_winnr, 1)
  vim.api.nvim_win_set_height(input_winnr, 8)
  -- TODO: configuration opt
  vim.api.nvim_win_set_width(results_winnr, math.floor(vim.o.columns * 2 / 3))

  vim.api.nvim_set_option_value("filetype", "rg-far", { buf = stderr_bufnr, })
  vim.api.nvim_set_option_value("filetype", "rg-far", { buf = input_bufnr, })
  vim.api.nvim_set_option_value("filetype", "rg-far", { buf = results_bufnr, })

  vim.api.nvim_buf_call(results_bufnr, function()
    vim.cmd [[syntax on]]
    vim.cmd [[syntax match ConcealPipe /^[^|]*|[^|]*|/ conceal]]
  end)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(stderr_winnr), tostring(input_winnr), tostring(results_winnr), },
    callback = function()
      if vim.api.nvim_win_is_valid(input_winnr) then vim.api.nvim_win_close(input_winnr, true) end
      if vim.api.nvim_win_is_valid(results_winnr) then vim.api.nvim_win_close(results_winnr, true) end
      if vim.api.nvim_win_is_valid(stderr_winnr) then vim.api.nvim_win_close(stderr_winnr, true) end
    end,
  })

  vim.api.nvim_set_current_win(input_winnr)

  for _, buffer in ipairs { stderr_bufnr, input_bufnr, results_bufnr, } do
    vim.keymap.set("n", "<Plug>RgFarReplace", function()
      replace {
        stderr_bufnr = stderr_bufnr,
        input_bufnr = input_bufnr,
        results_bufnr = results_bufnr,
      }
    end, { buffer = buffer, })
  end

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

    local clear_results_buf = function()
      vim.api.nvim_buf_set_lines(nrs.results_bufnr, 0, -1, false, {})
      vim.api.nvim_buf_clear_namespace(nrs.results_bufnr, ns_id, 0, -1)
      return
    end

    timer_id = vim.fn.timer_start(250, function()
      global_batch_id = global_batch_id + 1
      local curr_batch_id = global_batch_id

      local find = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 0, 1, false)[1]
      if find == "" then
        return clear_results_buf()
      end

      local replace_flag = (function()
        local replace = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 1, 2, false)
        if #replace == 0 then return {} end
        if #replace == 1 and replace[1] == "" then return {} end
        return { "--replace", replace[1], }
      end)()

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

      vim.system(args, {}, function(out)
        if out.code ~= 0 then
          vim.schedule(function()
            local stderr = vim.iter { rg_cmd, vim.split(out.stderr or "", "\n"), }:flatten():totable()
            vim.api.nvim_win_set_height(nrs.stderr_winnr, #stderr + 1)

            vim.bo[nrs.stderr_bufnr].modifiable = true
            vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, stderr)
            vim.bo[nrs.stderr_bufnr].modifiable = false

            clear_results_buf()
          end)
          return
        end

        if not out.stdout then
          return vim.schedule(clear_results_buf)
        end

        vim.schedule(function()
          vim.bo[nrs.stderr_bufnr].modifiable = true
          vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, { rg_cmd, })
          vim.bo[nrs.stderr_bufnr].modifiable = false
        end)

        local lines = vim.split(out.stdout, "\n")

        vim.schedule(function()
          run_batch {
            fn = function()
              clear_results_buf()

              local prev_filename = nil
              for idx_1i, line in ipairs(lines) do
                if curr_batch_id ~= global_batch_id then return end

                local idx_0i = idx_1i - 1
                vim.api.nvim_buf_set_lines(nrs.results_bufnr, idx_0i, idx_0i, false, { line, })

                local filename = unpack(vim.split(line, "|"))
                if filename ~= prev_filename then
                  prev_filename = filename
                  vim.api.nvim_buf_set_extmark(nrs.results_bufnr, ns_id, idx_0i, 0, {
                    virt_lines = {
                      { { filename, "ModeMsg", }, },
                      { { "", "", }, },
                    },
                  })
                end

                if idx_1i % 50 == 0 then
                  coroutine.yield()
                end
              end
            end,
          }
        end)
      end)
    end)
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", }, {
    buffer = nrs.input_bufnr,
    callback = populate_results,
  })
end

return M
