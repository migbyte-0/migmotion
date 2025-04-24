-- migmotion.lua
-- Numbered & colored virtual‑text word navigator for Neovim
-- Author: migbyte
-- License: MIT

local M = {}

------------------------------------------------------------------------
-- Default configuration ------------------------------------------------
------------------------------------------------------------------------
M.config = {
  max = 12,               -- how many words to show before / after cursor word
  before = true,          -- draw before the cursor word
  after = true,           -- draw after the cursor word
  virt = "number",        -- "number" | "dot"
  position = "overlay",   -- "overlay" | "above" | "below"
  colors = {
    "Green", "Blue", "Yellow", "Purple", "Magenta", "Cyan", "Red", "Orange",
    "Indigo", "White", "Grey", "Brown",
  },
  hl_prefix = "Migmotion", -- highlight‑group prefix (one group per color)
}

------------------------------------------------------------------------
-- Internal state -------------------------------------------------------
------------------------------------------------------------------------
M.ns = vim.api.nvim_create_namespace("migmotion")
M.enabled = false

------------------------------------------------------------------------
-- Helper: create/update highlight groups --------------------------------
------------------------------------------------------------------------
function M._create_hl_groups()
  for i, color in ipairs(M.config.colors) do
    local group = M.config.hl_prefix .. i
    -- if the user already defined the group we leave it alone
    if vim.fn.hlID(group) == 0 then
      vim.api.nvim_set_hl(0, group, { fg = color })
    end
  end
end

------------------------------------------------------------------------
-- Helper: split the line into words and store their start columns -------
------------------------------------------------------------------------
local function parse_line(line)
  local words = {}
  local pos = 1
  local byteidx = 1
  while true do
    local s, e = line:find("%S+", byteidx)
    if not s then
      break
    end
    table.insert(words, { start = s - 1, stop = e, text = line:sub(s, e) })
    byteidx = e + 1
  end
  return words
end

------------------------------------------------------------------------
-- Draw virtual text -----------------------------------------------------
------------------------------------------------------------------------
function M.draw()
  if not M.enabled then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()

  -- clear previous extmarks in the current buffer (namespace‑local)
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

  local cursor = vim.api.nvim_win_get_cursor(winid) -- {row (1‑based), col (0‑based)}
  local row0 = cursor[1] - 1           -- 0‑based row index
  local col = cursor[2]

  local line = vim.api.nvim_buf_get_lines(bufnr, row0, row0 + 1, false)[1]
  if not line or line == "" then
    return
  end

  local words = parse_line(line)
  if #words == 0 then
    return
  end

  -- find index of the word under cursor (fallback to nearest word on the left)
  local cur_idx = 1
  for i, w in ipairs(words) do
    if col >= w.start and col < w.stop then
      cur_idx = i
      break
    elseif col < w.start then
      cur_idx = math.max(1, i - 1)
      break
    end
  end

  local max_before = M.config.before and M.config.max or 0
  local max_after  = M.config.after  and M.config.max or 0

  local function symbol_for(dist)
    return M.config.virt == "number" and tostring(math.abs(dist)) or "•"
  end

  local function hl_for(dist)
    local idx = (math.abs(dist) - 1) % #M.config.colors + 1
    return M.config.hl_prefix .. idx
  end

  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  local target_row = row0 -- by default keep the same row
  local virt_pos = "overlay"
  if M.config.position == "above" then
    target_row = math.max(0, row0 - 1)
  elseif M.config.position == "below" then
    target_row = math.min(buf_line_count - 1, row0 + 1)
  end

  local function place(word_idx)
    local w = words[word_idx]
    local dist = word_idx - cur_idx
    local group = hl_for(dist)
    local symbol = symbol_for(dist)
    vim.api.nvim_buf_set_extmark(bufnr, M.ns, target_row, w.start, {
      virt_text = { { symbol, group } },
      virt_text_pos = virt_pos,
      hl_mode = "combine",
    })
  end

  -- draw before words
  for i = math.max(1, cur_idx - max_before), cur_idx - 1 do
    place(i)
  end
  -- draw after words
  for i = cur_idx + 1, math.min(#words, cur_idx + max_after) do
    place(i)
  end
end

------------------------------------------------------------------------
-- Enable / disable / toggle --------------------------------------------
------------------------------------------------------------------------
local function _attach_autocmd()
  if M._augroup then
    return
  end
  M._augroup = vim.api.nvim_create_augroup("MigmotionGroup", {})
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = M._augroup,
    callback = function()
      M.draw()
    end,
  })
end

function M.enable()
  M.enabled = true
  _attach_autocmd()
  M.draw()
end

function M.disable()
  M.enabled = false
  if M._augroup then
    vim.api.nvim_del_augroup_by_id(M._augroup)
    M._augroup = nil
  end
  vim.api.nvim_buf_clear_namespace(0, M.ns, 0, -1)
end

function M.toggle()
  if M.enabled then
    M.disable()
  else
    M.enable()
  end
end

------------------------------------------------------------------------
-- Toggle helpers --------------------------------------------------------
------------------------------------------------------------------------
function M.toggle_virt()
  M.config.virt = (M.config.virt == "number") and "dot" or "number"
  M.draw()
end

function M.toggle_position()
  if M.config.position == "overlay" then
    M.config.position = "above"
  elseif M.config.position == "above" then
    M.config.position = "below"
  else
    M.config.position = "overlay"
  end
  M.draw()
end

------------------------------------------------------------------------
-- Keymaps ---------------------------------------------------------------
------------------------------------------------------------------------
function M._set_keymaps()
  local wk = vim.keymap.set
  local opts = { noremap = true, silent = true }
  wk("n", "<leader>mn", M.toggle, opts)          -- Toggle plugin
  wk("n", "<leader>mv", M.toggle_virt, opts)     -- Toggle number/dot view
  wk("n", "<leader>mp", M.toggle_position, opts) -- Cycle overlay/above/below
end

------------------------------------------------------------------------
-- Public setup ----------------------------------------------------------
------------------------------------------------------------------------
function M.setup(opts)
  if M._setup_called then
    return -- guard against being run twice
  end
  M._setup_called = true
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M._create_hl_groups()
  M._set_keymaps()
  M.enable() -- start enabled by default; comment this if you prefer disabled
end

return M
