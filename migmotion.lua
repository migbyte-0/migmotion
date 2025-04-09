return {
  "migbyte-0/migmotion.nvim",
  config = function()
    -- word_nav.nvim: Numbered and Colored Virtual Text for Neovim
    -- Author: YourName
    -- License: MIT

    local M = {}

    -- Default config
    M.config = {
      max = 12,
      before = true,
      after = true,
      virt = 'number', -- 'number' or 'dot'
      position = 'overlay', -- 'overlay' or 'above' or 'below'
      colors = { 'Green', 'Blue', 'Yellow', 'Purple', 'Indigo', 'Cyan', 'Red', 'Orange', 'Magenta', 'White', 'Grey', 'Brown' },
      namespace = nil,
      hl_prefix = 'WordNav',
    }

    -- Setup function
    function M.setup(opts)
      M.config = vim.tbl_deep_extend('force', M.config, opts or {})
      M.config.namespace = vim.api.nvim_create_namespace('word_nav')
      M.create_hl_groups()
      M.enable()
      M.set_keymaps()
    end

    -- Create highlight groups
    function M.create_hl_groups()
      for i, color in ipairs(M.config.colors) do
        local group = M.config.hl_prefix .. i
        vim.cmd(string.format('highlight %s guifg=%s', group, color))
      end
    end

    -- Clear extmarks
    function M.clear(bufnr)
      vim.api.nvim_buf_clear_namespace(bufnr, M.config.namespace, 0, -1)
    end

    -- Draw extmarks around cursor
    function M.draw()
      local bufnr = vim.api.nvim_get_current_buf()
      M.clear(bufnr)
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_buf_get_lines(bufnr, row-1, row, false)[1]
      if not line then return end
      local words = {}
      for w in line:gmatch('%S+') do table.insert(words, w) end
      local positions = {}
      local idx = 1
      for i, w in ipairs(words) do
        local s, e = line:find(w, idx, true)
        table.insert(positions, {start=s-1, word=w})
        idx = e + 1
      end

      local cur_idx = 1
      for i, pos in ipairs(positions) do
        if pos.start <= col and col < pos.start + #pos.word then cur_idx = i end
      end

      local function draw_range(start_i, end_i)
        for i = start_i, end_i do
          local pos = positions[i]
          local symbol = M.config.virt == 'number' and tostring(math.abs(i - cur_idx)) or '•'
          local group = M.config.hl_prefix .. (((i - cur_idx - 1) % #M.config.colors) + 1)
          vim.api.nvim_buf_set_extmark(bufnr, M.config.namespace, row-1, pos.start, {
            virt_text = {{symbol, group}},
            virt_text_pos = M.config.position,
            hl_mode = 'combine',
          })
        end
      end

      if M.config.before then
        draw_range(math.max(1, cur_idx - M.config.max), cur_idx - 1)
      end
      if M.config.after then
        draw_range(cur_idx + 1, math.min(#positions, cur_idx + M.config.max))
      end
    end

    -- Enable autocmd
    function M.enable()
      vim.cmd([[
        augroup WordNav
          autocmd!
          autocmd CursorMoved,CursorMovedI * lua require'word_nav'.draw()
        augroup END
      ]])
    end

    -- Disable plugin
    function M.disable()
      vim.cmd('augroup WordNav|autocmd!|augroup END')
      M.clear(vim.api.nvim_get_current_buf())
    end

    -- Toggle plugin
    function M.toggle()
      if M.enabled then
        M.disable(); M.enabled = false
      else
        M.enable(); M.enabled = true
      end
    end

    -- Switch virt symbol
    function M.toggle_virt()
      M.config.virt = M.config.virt == 'number' and 'dot' or 'number'
      M.draw()
    end

    -- Switch position
    function M.toggle_position()
      if M.config.position == 'overlay' then
        M.config.position = 'above'
      elseif M.config.position == 'above' then
        M.config.position = 'below'
      else
        M.config.position = 'overlay'
      end
      M.draw()
    end

    -- Setup keymaps
    function M.set_keymaps()
      local wk = vim.api.nvim_set_keymap
      local opts = { noremap=true, silent=true }
      wk('n', '<leader>wn', ":lua require'word_nav'.toggle()<CR>", opts)        -- Toggle plugin
      wk('n', '<leader>wv', ":lua require'word_nav'.toggle_virt()<CR>", opts)     -- Toggle number/dot
      wk('n', '<leader>wp', ":lua require'word_nav'.toggle_position()<CR>", opts) -- Cycle overlay/above/below
    end

    return M
  end,
}
