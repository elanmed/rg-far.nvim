local M = {}

vim.g.rg_far_input_winnr = -1
vim.g.rg_far_input_bufnr = -1
vim.g.rg_far_stderr_bufnr = -1
vim.g.rg_far_results_bufnr = -1
vim.g.rg_far_curr_winnr = -1

--- @generic T
--- @param val T | nil
--- @param default_val T
--- @return T
local default = function(val, default_val)
  if val == nil then
    return default_val
  end
  return val
end

--- @param tbl table
--- @param ... any
local tbl_get = function(tbl, ...)
  if tbl == nil then return nil end
  return vim.tbl_get(tbl, ...)
end

--- @class RgFarOpts
--- @field drawer_width? number
--- @field debounce? number
--- @field batch_size? number

local get_gopts = function()
  --- @type RgFarOpts
  local opts = {}
  opts.drawer_width = default(tbl_get(vim.g.rg_far, "drawer_width"), 0.66)
  opts.debounce = default(tbl_get(vim.g.rg_far, "debounce"), 250)
  opts.batch_size = default(tbl_get(vim.g.rg_far, "batch_size"), 50)
  return opts
end

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
--- @field input_winnr number
--- @field results_bufnr number
--- @field results_winnr number

--- @param nrs NrOpts
local results_to_qf_list = function(nrs)
  local lines = vim.api.nvim_buf_get_lines(nrs.results_bufnr, 0, -1, false)
  lines = vim.tbl_filter(function(line) return line ~= "" end, lines)

  local qf_list = {}
  for _, line in ipairs(lines) do
    local filename, row_1i, text = unpack(vim.split(line, "|"))
    table.insert(qf_list, {
      bufnr = 0,
      text = text,
      lnum = row_1i,
      filename = filename,
    })
  end

  vim.fn.setqflist(qf_list)
  vim.cmd.copen()
end

--- @param nrs NrOpts
local clear_results_buf = function(nrs)
  vim.api.nvim_buf_set_lines(nrs.results_bufnr, 0, -1, false, {})
  vim.api.nvim_buf_clear_namespace(nrs.results_bufnr, ns_id, 0, -1)
  vim.wo[nrs.results_winnr].winbar = "Results"
end

--- @param nrs NrOpts
local replace = function(nrs)
  local gopts = get_gopts()
  local lines = vim.api.nvim_buf_get_lines(nrs.results_bufnr, 0, -1, false)
  lines = vim.tbl_filter(function(line) return line ~= "" end, lines)

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

      for idx_1i, line in ipairs(lines) do
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
          vim.api.nvim_buf_call(bufnr, function() vim.cmd "silent! write" end)
        end

        if idx_1i % gopts.batch_size == 0 then
          coroutine.yield()
        end
      end
    end,

    on_complete = function()
      vim.notify("[rg-far] Replace complete", vim.log.levels.INFO)

      vim.bo[nrs.stderr_bufnr].modifiable = true
      vim.bo[nrs.input_bufnr].modifiable = true
      vim.bo[nrs.results_bufnr].modifiable = true

      clear_results_buf(nrs)
    end,
  }
end

local init_windows_buffers = function()
  local gopts = get_gopts()

  local stderr_bufnr = (function()
    if vim.api.nvim_buf_is_valid(vim.g.rg_far_stderr_bufnr) then
      return vim.g.rg_far_stderr_bufnr
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.g.rg_far_stderr_bufnr = bufnr
    return bufnr
  end)()
  local stderr_winnr = vim.api.nvim_open_win(stderr_bufnr, true, {
    split = "right",
    win = 0,
  })
  vim.bo[stderr_bufnr].modifiable = false
  vim.wo[stderr_winnr].winbar = "Stderr"
  vim.wo[stderr_winnr].statusline = " "

  local input_bufnr = (function()
    if vim.api.nvim_buf_is_valid(vim.g.rg_far_input_bufnr) then
      return vim.g.rg_far_input_bufnr
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "", "", })
    vim.g.rg_far_input_bufnr = bufnr

    return bufnr
  end)()
  local input_winnr = vim.api.nvim_open_win(input_bufnr, true, {
    split = "below",
    win = stderr_winnr,
  })
  vim.g.rg_far_input_winnr = input_winnr
  vim.wo[input_winnr].winbar = "Input"
  vim.wo[input_winnr].statusline = " "

  local results_bufnr = (function()
    if vim.api.nvim_buf_is_valid(vim.g.rg_far_results_bufnr) then
      return vim.g.rg_far_results_bufnr
    end
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.g.rg_far_results_bufnr = bufnr
    return bufnr
  end)()
  local results_winnr = vim.api.nvim_open_win(results_bufnr, true, {
    split = "below",
    win = input_winnr,
  })
  vim.wo[results_winnr].winbar = "Results"
  vim.wo[results_winnr].statusline = " "
  vim.wo[results_winnr].conceallevel = 2
  vim.wo[results_winnr].concealcursor = "nvic"

  vim.api.nvim_win_set_height(stderr_winnr, 1)
  vim.api.nvim_win_set_height(input_winnr, 3 + 1)
  vim.api.nvim_win_set_width(results_winnr, math.floor(vim.o.columns * gopts.drawer_width))

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
      if vim.api.nvim_win_is_valid(input_winnr) then vim.api.nvim_win_close(input_winnr, false) end
      if vim.api.nvim_win_is_valid(results_winnr) then vim.api.nvim_win_close(results_winnr, false) end
      if vim.api.nvim_win_is_valid(stderr_winnr) then vim.api.nvim_win_close(stderr_winnr, false) end
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

--- @param nrs NrOpts
local init_plug_remaps = function(nrs)
  for _, buffer in ipairs { nrs.stderr_bufnr, nrs.input_bufnr, nrs.results_bufnr, } do
    vim.keymap.set("n", "<Plug>RgFarReplace", function() replace(nrs) end, { buffer = buffer, })
    vim.keymap.set("n", "<Plug>RgFarResultsToQfList", function() results_to_qf_list(nrs) end, { buffer = buffer, })
  end

  vim.keymap.set("n", "<Plug>RgFarOpenResult", function()
    local line = vim.api.nvim_get_current_line()
    local filename, row_1i = unpack(vim.split(line, "|"))
    vim.api.nvim_win_call(vim.g.rg_far_curr_winnr, function()
      vim.cmd.edit(filename)
    end)
    vim.api.nvim_win_set_cursor(vim.g.rg_far_curr_winnr, { tonumber(row_1i), 0, })
  end, { buffer = nrs.results_bufnr, })

  vim.keymap.set("n", "<Plug>RgFarClose", function()
    if vim.api.nvim_win_is_valid(vim.g.rg_far_input_winnr) then
      vim.api.nvim_win_close(vim.g.rg_far_input_winnr, true)
    end
  end)
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
        { { opts.label, "RgFarLabel", }, },
      },
    })
  end

  if #lines >= 1 then set_input_buf_extmark { idx_1i = 1, label = "Find", } end
  if #lines >= 2 then set_input_buf_extmark { idx_1i = 2, label = "Replace", } end
  if #lines >= 3 then set_input_buf_extmark { idx_1i = #lines, label = "Flags (one per line)", } end

  vim.api.nvim_win_set_height(nrs.input_winnr, #lines + 3 + 1)
end

--- @param nrs NrOpts
local highlight_results_buf = function(nrs)
  local gopts = get_gopts()
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

        if idx_1i % gopts.batch_size == 0 then
          coroutine.yield()
        end
      end
    end,
  }
end

local timer_id = nil
--- @param nrs NrOpts
local populate_and_highlight_results = function(nrs)
  if timer_id then vim.fn.timer_stop(timer_id) end
  if system_obj then system_obj:kill "sigterm" end
  local gopts = get_gopts()

  timer_id = vim.fn.timer_start(gopts.debounce, function()
    global_batch_id = global_batch_id + 1
    local curr_batch_id = global_batch_id

    local find = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 0, 1, false)[1]
    if find == "" then return clear_results_buf(nrs) end

    local replace_flag = (function()
      local replace_lines = vim.api.nvim_buf_get_lines(nrs.input_bufnr, 1, 2, false)
      if #replace_lines == 0 then return {} end
      if #replace_lines == 1 and replace_lines[1] == "" then return {} end
      return { "--replace", replace_lines[1], }
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

    local escaped_flags = vim.tbl_map(function(flag) return vim.fn.shellescape(flag) end,
      vim.iter(flags):flatten():totable())
    local pretty_rg_cmd = ("rg ... %s -- %s"):format(table.concat(escaped_flags, ""), vim.fn.shellescape(find))

    vim.wo[nrs.results_winnr].winbar = "Results (loading ...)"
    system_obj = vim.system(args, {}, function(out)
      if curr_batch_id ~= global_batch_id then return end

      --- @param results string[]
      local set_results = function(results)
        vim.wo[nrs.input_winnr].winbar = pretty_rg_cmd
        local stderr = vim.split(out.stderr or "", "\n")
        vim.api.nvim_win_set_height(nrs.stderr_winnr, #stderr + 1)

        vim.bo[nrs.stderr_bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, stderr)
        vim.bo[nrs.stderr_bufnr].modifiable = false

        vim.api.nvim_buf_set_lines(nrs.results_bufnr, 0, -1, false, results)
        vim.wo[nrs.results_winnr].winbar = ("Results (%d lines)"):format(#results)
        highlight_results_buf(nrs)
        highlight_input_buf(nrs)
      end

      if out.code ~= 0 then
        vim.schedule(function() set_results {} end)
        return
      end

      if not out.stdout then
        vim.schedule(function() set_results {} end)
        return
      end

      vim.schedule(function()
        vim.bo[nrs.stderr_bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(nrs.stderr_bufnr, 0, -1, false, { rg_cmd, })
        vim.bo[nrs.stderr_bufnr].modifiable = false
      end)

      local lines = vim.split(out.stdout, "\n")
      lines = vim.tbl_filter(function(line) return line ~= "" end, lines)

      vim.schedule(function() set_results(lines) end)
    end)
  end)
end

M.open = function()
  vim.g.rg_far_curr_winnr = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(vim.g.rg_far_input_winnr) then
    vim.api.nvim_set_current_win(vim.g.rg_far_input_winnr)
    return vim.notify "[rg-far] Already open"
  end

  local nrs = init_windows_buffers()
  init_plug_remaps(nrs)
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

vim.g.rg_far_setup_called = false
M.setup = function()
  if vim.g.rg_far_setup_called then return end
  vim.g.rg_far_setup_called = true
  vim.api.nvim_set_hl(0, "RgFarLabel", { default = true, link = "ModeMsg", })
end

return M
