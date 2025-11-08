local M = {}

local ns_id = vim.api.nvim_create_namespace "rg-far"
local global_batch_id = 0
local system_obj


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

--- @class NrOpts
--- @field stderr_bufnr number
--- @field stderr_winnr number
--- @field input_bufnr number
--- @field results_bufnr number
--- @field results_winnr number

--- @param nrs NrOpts
local replace = function(nrs)
  local lines = vim.api.nvim_buf_get_lines(nrs.results_bufnr, 0, -1, false)
  local option = vim.fn.confirm(("[rg-far] Apply %d replacements?"):format(#lines), "&Yes\n&No", 2)
  if option ~= 1 then
    vim.notify("[rg-far] Aborting replace", vim.log.levels.INFO)
    return
  end

  run_batch {
    fn = function()
      vim.bo[nrs.stderr_bufnr].modifiable = false
      vim.bo[nrs.input_bufnr].modifiable = false
      vim.bo[nrs.results_bufnr].modifiable = false

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
      vim.bo[nrs.stderr_bufnr].modifiable = true
      vim.bo[nrs.input_bufnr].modifiable = true
      vim.bo[nrs.results_bufnr].modifiable = true
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
  vim.wo[stderr_winnr].winbar = "Rg command and stderr"
  vim.wo[stderr_winnr].statusline = " "

  local input_bufnr = vim.api.nvim_create_buf(false, true)
  local input_winnr = vim.api.nvim_open_win(input_bufnr, true, {
    split = "below",
    win = stderr_winnr,
  })
  vim.wo[input_winnr].winbar = "Input"
  vim.wo[input_winnr].statusline = " "
  vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, false, { "", "", "", })

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

  vim.bo[stderr_bufnr].filetype = "rg-far"
  vim.bo[input_bufnr].filetype = "rg-far"
  vim.bo[results_bufnr].filetype = "rg-far"

  vim.api.nvim_buf_call(results_bufnr, function()
    vim.cmd [[syntax on]]
    vim.cmd [[syntax match ConcealPipe /^[^|]*|[^|]*|/ conceal]]
  end)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(stderr_winnr), tostring(input_winnr), tostring(results_winnr), },
    callback = function()
      if system_obj then system_obj:kill "sigterm" end
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
    results_bufnr = results_bufnr,
    results_winnr = results_winnr,
  }
end

--- @param nrs NrOpts
local highlight_input_buf = function(nrs)
  vim.api.nvim_buf_clear_namespace(nrs.input_bufnr, ns_id, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 0, -1, false)

  --- @class SetInputBufExtmarkOpts
  --- @field idx_1i number
  --- @field label string
  --- @param opts SetInputBufExtmarkOpts
  local set_input_buf_extmark = function(opts)
    local idx_0i = opts.idx_1i - 1
    vim.api.nvim_buf_set_extmark(nrs.input_bufnr, ns_id, idx_0i, 0, {
      virt_lines = {
        { { opts.label, "ModeMsg", }, },
      },
    })
  end

  if #lines >= 1 then set_input_buf_extmark { idx_1i = 1, label = "Find", } end
  if #lines >= 2 then set_input_buf_extmark { idx_1i = 2, label = "Replace", } end
  if #lines >= 3 then set_input_buf_extmark { idx_1i = #lines, label = "Flags (one per line)", } end
end

--- @param nrs NrOpts
local clear_results_buf = function(nrs)
  vim.api.nvim_buf_set_lines(nrs.results_bufnr, 0, -1, false, {})
  vim.api.nvim_buf_clear_namespace(nrs.results_bufnr, ns_id, 0, -1)
  vim.wo[nrs.results_winnr].winbar = "Results"
end

--- @param nrs NrOpts
local highlight_results_buf = function(nrs)
  run_batch {
    fn = function()
      vim.api.nvim_buf_clear_namespace(nrs.results_bufnr, ns_id, 0, -1)

      local next_filename = nil
      local curr_filename = nil
      local lines = vim.api.nvim_buf_get_lines(nrs.results_bufnr, 0, -1, false)
      lines = vim.tbl_filter(function(line) return line ~= "" end, lines)

      for idx_1i, line in ipairs(lines) do
        local idx_0i = idx_1i - 1
        curr_filename = unpack(vim.split(line, "|"))

        next_filename = (function()
          if lines[idx_1i + 1] == nil then return nil end
          return unpack(vim.split(lines[idx_1i + 1], "|"))
        end)()

        if curr_filename ~= next_filename then
          vim.api.nvim_buf_set_extmark(nrs.results_bufnr, ns_id, idx_0i, 0, {
            virt_lines = {
              { { curr_filename, "ModeMsg", }, },
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
end

local timer_id = nil
--- @param nrs NrOpts
local populate_and_highlight_results = function(nrs)
  if timer_id then
    vim.fn.timer_stop(timer_id)
  end

  timer_id = vim.fn.timer_start(250, function()
    global_batch_id = global_batch_id + 1
    local curr_batch_id = global_batch_id

    local find = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 0, 1, false)[1]
    if find == "" then
      return clear_results_buf(nrs)
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

    -- TODO: shell escape
    local rg_cmd = table.concat(args, " ")

    system_obj = vim.system(args, {}, function(out)
      vim.schedule(function() clear_results_buf(nrs) end)

      if out.code ~= 0 then
        vim.schedule(function()
          local stderr = vim.iter { rg_cmd, vim.split(out.stderr or "", "\n"), }:flatten():totable()
          vim.api.nvim_win_set_height(nrs.stderr_winnr, #stderr + 1)

          vim.bo[nrs.stderr_bufnr].modifiable = true
          vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, stderr)
          vim.bo[nrs.stderr_bufnr].modifiable = false
        end)
        return
      end

      if not out.stdout then return end

      vim.schedule(function()
        vim.bo[nrs.stderr_bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, { rg_cmd, })
        vim.bo[nrs.stderr_bufnr].modifiable = false
      end)

      local lines = vim.split(out.stdout, "\n")
      lines = vim.tbl_filter(function(line) return line ~= "" end, lines)

      vim.schedule(function()
        run_batch {
          fn = function()
            for idx_1i, line in ipairs(lines) do
              if curr_batch_id ~= global_batch_id then
                system_obj:kill "sigterm"
                return
              end

              local idx_0i = idx_1i - 1
              vim.api.nvim_buf_set_lines(nrs.results_bufnr, idx_0i, idx_0i, false, { line, })

              if idx_1i % 50 == 0 then
                coroutine.yield()
              end
            end
          end,
          on_complete = function()
            vim.schedule(function()
              if not vim.api.nvim_win_is_valid(nrs.results_winnr) then return end
              vim.wo[nrs.results_winnr].winbar = ("Results (%d)"):format(vim.api.nvim_buf_line_count(nrs.results_bufnr))
              highlight_results_buf(nrs)
            end)
          end,
        }
      end)
    end)
  end)
end

M.open = function()
  local nrs = init_windows_buffers()
  highlight_input_buf(nrs)

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", }, {
    buffer = nrs.input_bufnr,
    callback = function()
      highlight_input_buf(nrs)
      populate_and_highlight_results(nrs)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", }, {
    buffer = nrs.results_bufnr,
    callback = function() highlight_results_buf(nrs) end,
  })
end

return M
