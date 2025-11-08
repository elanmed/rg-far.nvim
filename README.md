# `rg-far.nvim`

### Overview

- ~300 LOC, 1 source file, 1 test file (TODO)
- Simple principle: the results buffer is the source of truth
  - `rg-far` uses the `--with-filename`, `--line-number`, and `replace` flags so that each line in the results buffer is
    formatted like: `[filename]|[column]|[result with the searched text replaced]`. This means that every line in the results
    buffer has everything it needs to replace a line in the source file with the desired text in the results buffer. When
    `<Plug>RgFarReplace` is called, it simply reads the results buffer and applies the changes specified on each line.
  - The inline filename and column are hidden with conceal. Filenames are rendered with extmarks instead - and only once per filename.
    This approach ensures that the text of the results buffer is unchanged.
    - Manually deleting a search result from the results buffer triggers the extrmarks to rerender.

### Performance

- The extmarks are rendered in batches with coroutines to keep the ui responsive
- `rg` calls are debounced
- Subsequent calls to `rg` cancel ongoing processes

### API

```lua
M.open = function() end
```

### Plug remaps

#### `<Plug>RgFarReplace`

- Writes the text in the results buffer to the corresponding file
- Confirms before replacing
