# `rg-far.nvim`

A minimal find-and-replace interface powered by ripgrep

![demo](https://elanmed.dev/nvim-plugins/rg-far.png)

### Overview

- ~300 LOC, 1 source file, 1 test file (TODO)
- Simple principle: the results buffer is the source of truth
  - `rg-far` uses the `--with-filename`, `--line-number`, and `replace` ripgrep flags so that each line in the results buffer is
    formatted as: `[filename]|[row]|[result with the searched text replaced]`. This means that when calling `<PlugRgFarReplace`,
    `rg-far` can simply read each line of the results buffer and, for a given `[filename]`, replace the line at `[row]` with the
    `[result with the searched text replaced]` - what you see is what you get.
  - In the results buffer, the filename and column are hidden with conceal to avoid cluttering the results. Instead of displaying
    the filename for each search result, the filename is rendered once per group of search results using extmarks.
    - Manually deleting a search result from the results buffer triggers the extrmarks to rerender.

### Performance

`rg-far` prioritizes performance in a few ways:

- Extmarks are set in batches with coroutines to keep the ui responsive
- When typing in the input buffer, `rg` calls are debounced by `vim.g.rg_far.debounce` ms
- If the input buffer is updated while there's an ongoing `rg` process, the existing process is killed

### API

```lua
M.open = function() end
```

### Configuration

```lua
-- default:
vim.g.rg_far = {
  drawer_width = 0.66 -- a number between 0 and 1
  debounce = 250, -- debounce when calling `rg` when the input buffer changes
  batch_size = 50, -- loop iterations processed before calling `coroutine.yield`
}

-- default:
vim.api.nvim_set_hl(0, "RgFarLabel", { link = "ModeMsg", })

-- example, not default:
vim.api.nvim_create_autocmd("FileType", {
  pattern = "rg-far",
  callback = function()
    vim.keymap.set("n", "<leader>r", "<Plug>RgFarReplace", { buffer = true })
    vim.keymap.set("n", "<leader>f", "<Plug>RgFarResultsToQfList", { buffer = true, })
  end,
})
```

### Plug remaps

#### `<Plug>RgFarReplace`

- Writes the text in the results buffer to the corresponding file
- Confirms before replacing


#### `<Plug>RgFarResultsToQfList`
- Sends the results currently present in the results buffer to the quickfix list
- Opens the quickfix list
