require "mini.test".setup()

local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local delay = 300

local mock_confirm = function(user_choice)
  local lua_cmd = string.format(
    [[vim.fn.confirm = function(...)
        _G.confirm_args = { ... }
        return %d
      end]],
    user_choice
  )
  child.lua(lua_cmd)
end

local validate_confirm_args = function(ref_msg_pattern)
  local args = child.lua_get "_G.confirm_args"
  eq(args[1], ref_msg_pattern)
  if args[2] ~= nil then eq(args[2], "&Yes\n&No") end
  if args[3] ~= nil then eq(args[3], 2) end
end

local get_rg_far_windows = function()
  local wins = child.api.nvim_list_wins()
  local rg_far_wins = {}
  for _, win in ipairs(wins) do
    local buf = child.api.nvim_win_get_buf(win)
    local ft = child.api.nvim_get_option_value("filetype", { buf = buf, })
    if ft == "rg-far" then
      local winbar = child.api.nvim_win_get_option(win, "winbar")
      table.insert(rg_far_wins, { winnr = win, bufnr = buf, winbar = winbar, })
    end
  end
  return rg_far_wins
end

local get_results_buffer = function()
  local wins = child.api.nvim_list_wins()
  for _, win in ipairs(wins) do
    local winbar = child.api.nvim_win_get_option(win, "winbar")
    if winbar:match "^Results" then
      return child.api.nvim_win_get_buf(win)
    end
  end
  return nil
end

local is_input_window = function(winbar)
  return winbar == "Input" or winbar:match "^rg"
end

local type_in_input_buffer = function(line_index, text)
  local wins = child.api.nvim_list_wins()
  for _, win in ipairs(wins) do
    local winbar = child.api.nvim_win_get_option(win, "winbar")
    if is_input_window(winbar) then
      local buf = child.api.nvim_win_get_buf(win)
      child.api.nvim_buf_set_lines(buf, line_index, line_index + 1, false, { text, })
      return
    end
  end
end

local trigger_plug_map = function(map_name)
  local keys = child.api.nvim_replace_termcodes(map_name, true, false, true)
  child.api.nvim_feedkeys(keys, "x", false)
end

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "scripts/minimal_init.lua", }
      child.bo.readonly = false
      child.lua [[M = require('rg-far')]]
      child.lua [[M.setup()]]
      child.o.lines = 30
      child.o.columns = 80

      vim.fn.mkdir("test_dir", "p")
      vim.fn.writefile({ "goodbye world", "foo bar", }, "test_dir/file1.txt")
      vim.fn.writefile({ "goodbye universe", "baz qux", }, "test_dir/file2.txt")
      vim.fn.mkdir("test_dir/subdir", "p")
      vim.fn.writefile({ "goodbye there", "nested content", }, "test_dir/subdir/file3.txt")
    end,
    post_case = function()
      vim.fn.delete("test_dir", "rf")
    end,
    post_once = child.stop,
  },
}


T["M.open()"] = MiniTest.new_set()
T["M.open()"]["opens the interface with three windows"] = function()
  child.lua [[M.open()]]

  local wins = child.api.nvim_list_wins()
  eq(#wins, 4)

  local rg_far_wins = get_rg_far_windows()
  eq(#rg_far_wins, 3)

  local winbars = {}
  for _, win in ipairs(rg_far_wins) do
    table.insert(winbars, win.winbar)
  end
  table.sort(winbars)

  local has_stderr = vim.tbl_contains(winbars, "Stderr")
  local has_input = vim.tbl_contains(winbars, "Input")
  local has_results = vim.tbl_contains(winbars, "Results")

  eq(has_stderr, true)
  eq(has_results, true)
  eq(has_input, true)
end

T["M.open()"]["focuses input window"] = function()
  child.lua [[M.open()]]

  local curr_win = child.api.nvim_get_current_win()
  local winbar = child.api.nvim_win_get_option(curr_win, "winbar")

  eq(is_input_window(winbar), true)
end

T["searching"] = MiniTest.new_set()
T["searching"]["finds text in files"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local results = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)

  local non_empty_results = vim.tbl_filter(function(line) return line ~= "" end, results)
  eq(#non_empty_results, 3)
end

T["searching"]["shows results with filename and line number"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local lines = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty = vim.tbl_filter(function(line) return line ~= "" end, lines)

  local expected = {
    "test_dir/file1.txt|1|goodbye world",
    "test_dir/file2.txt|1|goodbye universe",
    "test_dir/subdir/file3.txt|1|goodbye there",
  }

  table.sort(non_empty)
  table.sort(expected)

  eq(non_empty, expected)
end

T["searching"]["handles empty search"] = function()
  child.lua [[M.open()]]

  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local results = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)

  local non_empty_results = vim.tbl_filter(function(line) return line ~= "" end, results)
  eq(#non_empty_results, 0)
end

T["searching"]["respects ripgrep flags"] = function()

end

T["searching"]["debounces input changes"] = function()

end

T["replace"] = MiniTest.new_set()
T["replace"]["<Plug>RgFarReplace confirms before replacing"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(1, "hello")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local file1_before = child.fn.readfile "test_dir/file1.txt"
  eq(file1_before[1], "goodbye world")

  local file2_before = child.fn.readfile "test_dir/file2.txt"
  eq(file2_before[1], "goodbye universe")

  mock_confirm(2)

  trigger_plug_map "<Plug>RgFarReplace"

  validate_confirm_args "[rg-far] Apply 3 replacements?"

  local file1_after = child.fn.readfile "test_dir/file1.txt"
  eq(file1_after[1], "goodbye world")

  local file2_after = child.fn.readfile "test_dir/file2.txt"
  eq(file2_after[1], "goodbye universe")
end

T["replace"]["<Plug>RgFarReplace replaces text in files"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(1, "hello")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local file1_before = child.fn.readfile "test_dir/file1.txt"
  eq(file1_before[1], "goodbye world")

  local file2_before = child.fn.readfile "test_dir/file2.txt"
  eq(file2_before[1], "goodbye universe")

  mock_confirm(1)

  trigger_plug_map "<Plug>RgFarReplace"
  vim.uv.sleep(delay)

  validate_confirm_args "[rg-far] Apply 3 replacements?"

  local file1_after = child.fn.readfile "test_dir/file1.txt"
  eq(file1_after[1], "hello world")

  local file2_after = child.fn.readfile "test_dir/file2.txt"
  eq(file2_after[1], "hello universe")
end

T["replace"]["<Plug>RgFarReplace replaces text in open buffers"] = function()

end

T["replace"]["<Plug>RgFarReplace aborts when loading"] = function()

end

T["quickfix"] = MiniTest.new_set()
T["quickfix"]["<Plug>RgFarResultsToQfList sends results to quickfix"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  trigger_plug_map "<Plug>RgFarResultsToQfList"

  local qf_list = child.fn.getqflist()

  eq(#qf_list, 3)

  local actual = {}
  for _, entry in ipairs(qf_list) do
    table.insert(actual, {
      lnum = entry.lnum,
      text = entry.text,
    })
  end

  local expected = {
    { lnum = 1, text = "goodbye world", },
    { lnum = 1, text = "goodbye universe", },
    { lnum = 1, text = "goodbye there", },
  }

  table.sort(actual, function(a, b) return a.text < b.text end)
  table.sort(expected, function(a, b) return a.text < b.text end)

  eq(actual, expected)
end

T["navigation"] = MiniTest.new_set()
T["navigation"]["<Plug>RgFarOpenResult opens result in original window"] = function()

end

T["close"] = MiniTest.new_set()
T["close"]["<Plug>RgFarClose closes all windows"] = function()
  child.lua [[M.open()]]

  local rg_far_wins_before = get_rg_far_windows()
  eq(#rg_far_wins_before, 3)

  trigger_plug_map "<Plug>RgFarClose"

  local rg_far_wins_after = get_rg_far_windows()
  eq(#rg_far_wins_after, 0)
end

T["refresh"] = MiniTest.new_set()
T["refresh"]["<Plug>RgFarRefreshResults refreshes results"] = function()

end

return T
