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

local get_results_window = function()
  local wins = child.api.nvim_list_wins()
  for _, win in ipairs(wins) do
    local winbar = child.api.nvim_win_get_option(win, "winbar")
    if vim.startswith(winbar, "Results") then
      return win
    end
  end
  return nil
end

local get_results_buffer = function()
  local win = get_results_window()
  if win then
    return child.api.nvim_win_get_buf(win)
  end
  return nil
end

local is_input_window = function(winbar)
  return winbar == "Input" or vim.startswith(winbar, "rg")
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

local get_conceal_marks = function(extmarks)
  return vim.iter(extmarks):filter(function(mark)
    return mark[4].conceal ~= nil
  end):totable()
end

local get_virt_line_marks = function(extmarks)
  return vim.iter(extmarks):filter(function(mark)
    return mark[4].virt_lines ~= nil
  end):totable()
end

local get_non_empty_lines = function(lines)
  return vim.iter(lines):filter(function(line)
    return line ~= ""
  end):totable()
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
      vim.fn.writefile({ "foo bar", "foo baz", "foo qux", }, "test_dir/multi.txt")
      vim.fn.writefile({ "line one", "foo bar", "line three", }, "test_dir/cursor_test.txt")
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

T["M.open()"]["when already open does not create duplicate windows"] = function()
  child.lua [[M.open()]]

  local wins_before = get_rg_far_windows()
  eq(#wins_before, 3)

  local first_input_win = vim.iter(wins_before):find(function(win)
    return is_input_window(win.winbar)
  end)
  local first_input_winnr = first_input_win.winnr

  child.api.nvim_set_current_win(child.api.nvim_list_wins()[1])

  child.lua [[ M.open() ]]

  local wins_after = get_rg_far_windows()
  eq(#wins_after, 3)

  local curr_win = child.api.nvim_get_current_win()
  eq(curr_win, first_input_winnr)
end

T["configuration"] = MiniTest.new_set()
T["configuration"]["respects drawer_width"] = function()
  child.lua [[vim.g.rg_far = { drawer_width = 0.5 }]]
  child.lua [[M.open()]]

  local results_win = get_results_window()
  local width = child.api.nvim_win_get_width(results_win)
  local expected_width = math.floor(child.o.columns * 0.5)

  eq(width, expected_width)
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

  local non_empty_results = get_non_empty_lines(results)
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
  local non_empty = get_non_empty_lines(lines)

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

  local non_empty_results = get_non_empty_lines(results)
  eq(#non_empty_results, 0)
end

T["searching"]["respects ripgrep flags"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "GOODBYE")
  type_in_input_buffer(2, "-i")
  type_in_input_buffer(3, "-g")
  type_in_input_buffer(4, "test_dir/**")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local results = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty = get_non_empty_lines(results)

  eq(#non_empty, 3)
end

T["stderr"] = MiniTest.new_set()
T["stderr"]["shows ripgrep errors"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "[invalid(regex")
  vim.uv.sleep(delay)

  local wins = child.api.nvim_list_wins()
  local stderr_win = vim.iter(wins):find(function(win)
    local winbar = child.api.nvim_win_get_option(win, "winbar")
    return winbar == "Stderr"
  end)

  local stderr_buf = child.api.nvim_win_get_buf(stderr_win)
  local stderr_lines = child.api.nvim_buf_get_lines(stderr_buf, 0, -1, false)
  local stderr_text = table.concat(stderr_lines, "\n")

  eq(stderr_text:find("regex parse error", 1, true) ~= nil, true)
  eq(stderr_text:find("unclosed character class", 1, true) ~= nil, true)
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
  child.cmd "edit test_dir/file1.txt"
  child.cmd "edit test_dir/file2.txt"

  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(1, "hello")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  mock_confirm(1)

  trigger_plug_map "<Plug>RgFarReplace"
  vim.uv.sleep(delay)

  local file1_bufnr = child.fn.bufnr "test_dir/file1.txt"
  local file1_lines = child.api.nvim_buf_get_lines(file1_bufnr, 0, -1, false)
  eq(file1_lines[1], "hello world")

  local file2_bufnr = child.fn.bufnr "test_dir/file2.txt"
  local file2_lines = child.api.nvim_buf_get_lines(file2_bufnr, 0, -1, false)
  eq(file2_lines[1], "hello universe")
end

T["replace"]["<Plug>RgFarReplace aborts when loading"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(1, "hello")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")

  trigger_plug_map "<Plug>RgFarReplace"

  local file1_contents = child.fn.readfile "test_dir/file1.txt"
  eq(file1_contents[1], "goodbye world")
end

T["replace"]["<Plug>RgFarReplace replaces with empty string"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()

  child.api.nvim_buf_set_lines(results_buf, 0, -1, false, {
    "test_dir/file1.txt|1| world",
    "test_dir/file2.txt|1| universe",
    "test_dir/subdir/file3.txt|1| there",
  })

  mock_confirm(1)

  trigger_plug_map "<Plug>RgFarReplace"
  vim.uv.sleep(delay)

  local file1_contents = child.fn.readfile "test_dir/file1.txt"
  eq(file1_contents[1], " world")

  local file2_contents = child.fn.readfile "test_dir/file2.txt"
  eq(file2_contents[1], " universe")

  local file3_contents = child.fn.readfile "test_dir/subdir/file3.txt"
  eq(file3_contents[1], " there")
end

T["replace"]["<Plug>RgFarReplace respects manual edits to results"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(1, "hello")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local lines = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty = get_non_empty_lines(lines)
  eq(#non_empty, 3)

  child.api.nvim_set_current_win(get_results_window())
  child.api.nvim_buf_set_lines(results_buf, 0, -1, false, {
    "test_dir/file1.txt|1|custom replacement",
    "test_dir/file2.txt|1|another custom text",
    "test_dir/subdir/file3.txt|1|manually edited",
  })

  mock_confirm(1)
  trigger_plug_map "<Plug>RgFarReplace"
  vim.uv.sleep(delay)

  local file1_contents = child.fn.readfile "test_dir/file1.txt"
  eq(file1_contents[1], "custom replacement")

  local file2_contents = child.fn.readfile "test_dir/file2.txt"
  eq(file2_contents[1], "another custom text")

  local file3_contents = child.fn.readfile "test_dir/subdir/file3.txt"
  eq(file3_contents[1], "manually edited")
end

T["replace"]["<Plug>RgFarReplace handles multiple matches per file"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "foo")
  type_in_input_buffer(1, "replaced")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/multi.txt")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local lines = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty = get_non_empty_lines(lines)
  eq(#non_empty, 3)

  mock_confirm(1)
  trigger_plug_map "<Plug>RgFarReplace"
  vim.uv.sleep(delay)

  local contents = child.fn.readfile "test_dir/multi.txt"
  eq(contents[1], "replaced bar")
  eq(contents[2], "replaced baz")
  eq(contents[3], "replaced qux")
end

T["replace"]["<Plug>RgFarReplace only replaces non-deleted results"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(1, "hello")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local lines_before = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty_before = get_non_empty_lines(lines_before)
  eq(#non_empty_before, 3)

  local file1_line_1i = vim.iter(ipairs(lines_before)):find(function(_, line)
    return line:find("test_dir/file1.txt", 1, true)
  end)
  local file1_line_0i = file1_line_1i - 1

  child.api.nvim_buf_set_lines(results_buf, file1_line_0i, file1_line_0i + 1, false, {})

  local lines_after = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty_after = get_non_empty_lines(lines_after)
  eq(#non_empty_after, 2)

  mock_confirm(1)
  trigger_plug_map "<Plug>RgFarReplace"
  vim.uv.sleep(delay)

  eq(child.fn.readfile "test_dir/file1.txt"[1], "goodbye world")
  eq(child.fn.readfile "test_dir/file2.txt"[1], "hello universe")
  eq(child.fn.readfile "test_dir/subdir/file3.txt"[1], "hello there")
end

T["window management"] = MiniTest.new_set()
T["window management"]["closes all windows when input window is closed"] = function()
  child.lua [[M.open()]]

  local rg_far_wins_before = get_rg_far_windows()
  eq(#rg_far_wins_before, 3)

  local input_win = vim.iter(rg_far_wins_before):find(function(win)
    return is_input_window(win.winbar)
  end)
  child.api.nvim_win_close(input_win.winnr, true)

  local rg_far_wins_after = get_rg_far_windows()
  eq(#rg_far_wins_after, 0)
end

T["window management"]["closes all windows when results window is closed"] = function()
  child.lua [[M.open()]]

  local rg_far_wins_before = get_rg_far_windows()
  eq(#rg_far_wins_before, 3)

  local results_win = vim.iter(rg_far_wins_before):find(function(win)
    return vim.startswith(win.winbar, "Results")
  end)
  child.api.nvim_win_close(results_win.winnr, true)

  local rg_far_wins_after = get_rg_far_windows()
  eq(#rg_far_wins_after, 0)
end

T["window management"]["closes all windows when stderr window is closed"] = function()
  child.lua [[M.open()]]

  local rg_far_wins_before = get_rg_far_windows()
  eq(#rg_far_wins_before, 3)

  local stderr_win = vim.iter(rg_far_wins_before):find(function(win)
    return win.winbar == "Stderr"
  end)
  child.api.nvim_win_close(stderr_win.winnr, true)

  local rg_far_wins_after = get_rg_far_windows()
  eq(#rg_far_wins_after, 0)
end

T["results buffer"] = MiniTest.new_set()
T["results buffer"]["re-highlights on manual edit"] = function()
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local lines_before = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty_before = get_non_empty_lines(lines_before)
  eq(#non_empty_before, 3)

  local ns = child.lua_get [[vim.api.nvim_create_namespace 'rg-far']]
  local extmarks_before = child.api.nvim_buf_get_extmarks(results_buf, ns, 0, -1, { details = true, })

  eq(#get_conceal_marks(extmarks_before), 3)
  eq(#get_virt_line_marks(extmarks_before), 3)

  child.api.nvim_set_current_win(get_results_window())
  child.cmd "normal! dd"

  local lines_after = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty_after = get_non_empty_lines(lines_after)
  eq(#non_empty_after, 2)

  local extmarks_after = child.api.nvim_buf_get_extmarks(results_buf, ns, 0, -1, { details = true, })

  eq(#get_conceal_marks(extmarks_after), 2)
  eq(#get_virt_line_marks(extmarks_after), 2)
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

  local actual = vim.iter(qf_list):map(function(entry)
    return { lnum = entry.lnum, text = entry.text, }
  end):totable()

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
  local original_wins = child.api.nvim_list_wins()
  eq(#original_wins, 1)
  local original_win = original_wins[1]

  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  child.api.nvim_set_current_win(get_results_window())

  trigger_plug_map "<Plug>RgFarOpenResult"

  local original_buf = child.api.nvim_win_get_buf(original_win)
  local bufname = child.api.nvim_buf_get_name(original_buf)

  local expected_files = {
    child.lua_get [[vim.fs.abspath "test_dir/file1.txt"]],
    child.lua_get [[vim.fs.abspath "test_dir/file2.txt"]],
    child.lua_get [[vim.fs.abspath "test_dir/subdir/file3.txt"]],
  }

  eq(vim.tbl_contains(expected_files, bufname), true)

  local cursor = child.api.nvim_win_get_cursor(original_win)
  eq(cursor[1], 1)
end

T["navigation"]["<Plug>RgFarOpenResult places cursor at correct line"] = function()
  local original_wins = child.api.nvim_list_wins()
  local original_win = original_wins[1]

  child.lua [[M.open()]]

  type_in_input_buffer(0, "foo")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/cursor_test.txt")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local lines = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty = get_non_empty_lines(lines)
  eq(#non_empty, 1)
  eq(non_empty[1]:find("test_dir/cursor_test.txt|2|", 1, true) ~= nil, true)

  child.api.nvim_set_current_win(get_results_window())
  trigger_plug_map "<Plug>RgFarOpenResult"

  local cursor = child.api.nvim_win_get_cursor(original_win)
  eq(cursor[1], 2)
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
  child.lua [[M.open()]]

  type_in_input_buffer(0, "goodbye")
  type_in_input_buffer(2, "-g")
  type_in_input_buffer(3, "test_dir/**")
  vim.uv.sleep(delay)

  local results_buf = get_results_buffer()
  local results_before = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty_before = get_non_empty_lines(results_before)
  eq(#non_empty_before, 3)

  child.fn.writefile({ "goodbye friend", "foo bar", }, "test_dir/file1.txt")

  trigger_plug_map "<Plug>RgFarRefreshResults"
  vim.uv.sleep(delay)

  local results_after = child.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  local non_empty_after = get_non_empty_lines(results_after)

  eq(#non_empty_after, 3)

  eq(vim.iter(non_empty_after):any(function(line)
    return line:find("goodbye friend", 1, true)
  end), true)
end

return T
