-- migmotion.lua
-- Numbered & coloured virtual‑text word navigator for Neovim
-- Author: migbyte
-- License: MIT

local M = {}

------------------------------------------------------------------------
-- Default configuration ------------------------------------------------
------------------------------------------------------------------------
M.config = {
  max      = 12,           -- how many words to show before / after cursor word
  before   = true,         -- draw halos before the cursor word
  after    = true,         -- draw halos after  the cursor word
  virt     = "number",      -- "number" | "dot"
  position = "above",       -- "overlay" | "above" | "below"
  colors   = {
    "Green", "Blue", "Yellow", "Purple", "Magenta", "Cyan", "Red", "Orange",
    "Indigo", "White", "Grey", "Brown",
  },
  hl_prefix = "Migmotion",  -- prefix for highlight groups
}

------------------------------------------------------------------------
-- Internal state -------------------------------------------------------
------------------------------------------------------------------------
M.ns      = vim.api.nvim_create_namespace("migmotion")
M.enabled = false

------------------------------------------------------------------------
-- Highlight groups -----------------------------------------------------
------------------------------------------------------------------------
function M._create_hl_groups()
  for i, color in ipairs(M.config.colors) do
    local group = M.config.hl_prefix .. i
    if vim.fn.hlID(group) == 0 then          -- honour user overrides
      vim.api.nvim_set_hl(0, group, { fg = color })
    end
  end
end

------------------------------------------------------------------------
-- Word parser ----------------------------------------------------------
------------------------------------------------------------------------
local function parse_line(line)
  local words, idx = {}, 1
  while true do
    local s, e = line:find("%S+", idx)
    if not s then break end
    words[#words + 1] = { start = s - 1, stop = e, len = e - s + 1 }
    idx = e + 1
  end
  return words
end

------------------------------------------------------------------------
-- Safe extmark setter --------------------------------------------------
------------------------------------------------------------------------
local function set_mark(bufnr, ns, row, col, opts)
  local txt = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  col = math.max(0, math.min(col, #txt))
  return vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, opts)
end

------------------------------------------------------------------------
-- Draw halos -----------------------------------------------------------
------------------------------------------------------------------------
function M.draw()
  if not M.enabled then return end

  local bufnr  = vim.api.nvim_get_current_buf()
  local winid  = vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(winid))
  row = row - 1   -- 0‑based

  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line or line == "" then return end

  local words = parse_line(line)
  if #words == 0 then return end

  -- current word index (or nearest on the left)
  local cur = 1
  for i, w in ipairs(words) do
    if col >= w.start and col < w.stop then
      cur = i; break
    elseif col < w.start then
      cur = math.max(1, i - 1); break
    end
  end

  local before = M.config.before and M.config.max or 0
  local after  = M.config.after  and M.config.max or 0

  -- choose target row & virt_text_pos
  local pos_map = {
    overlay = { row = row,                vtp = "overlay" },
    above   = { row = math.max(0, row-1), vtp = "inline"  },
    below   = { row = row+1,              vtp = "inline"  },
  }
  local target   = pos_map[M.config.position] or pos_map.overlay
  local trow     = target.row
  local vtp      = target.vtp

  local function glyph(dist)
    return (M.config.virt == "number") and tostring(math.abs(dist)) or "•"
  end
  local function hlg(dist)
    local idx = (math.abs(dist) - 1) % #M.config.colors + 1
    return M.config.hl_prefix .. idx
  end

  local function place(i)
    local w    = words[i]
    local dist = i - cur
    local sym  = glyph(dist)
    local mid  = w.start + math.floor((w.len - #sym) / 2)  -- centre horizontally
    set_mark(bufnr, M.ns, trow, mid, {
      virt_text     = { { sym, hlg(dist) } },
      virt_text_pos = vtp,
      hl_mode       = "combine",
    })
  end

  for i = math.max(1, cur-before), cur-1           do place(i) end
  for i = cur+1,           math.min(#words, cur+after) do place(i) end
end

------------------------------------------------------------------------
-- Enable / disable -----------------------------------------------------
------------------------------------------------------------------------
local function attach_autocmd()
  if M._augroup then return end
  M._augroup = vim.api.nvim_create_augroup("MigmotionGroup", {})
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = M._augroup,
    callback = M.draw,
  })
end

function M.enable()
  M.enabled = true
  attach_autocmd()
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
  (M.enabled and M.disable or M.enable)()
end

------------------------------------------------------------------------
-- Toggles --------------------------------------------------------------
------------------------------------------------------------------------
function M.toggle_virt()
  M.config.virt = (M.config.virt == "number") and "dot" or "number"
  M.draw()
end
function M.toggle_position()
  M.config.position = (M.config.position == "overlay" and "above")
                      or (M.config.position == "above"   and "below")
                      or "overlay"
  M.draw()
end

------------------------------------------------------------------------
-- Keymaps --------------------------------------------------------------
------------------------------------------------------------------------
function M._set_keymaps()
  local map, o = vim.keymap.set, { noremap = true, silent = true }
  map("n", "<leader>mn", M.toggle,          o) -- toggle plugin
  map("n", "<leader>mv", M.toggle_virt,     o) -- number ↔ dot
  map("n", "<leader>mc", M.toggle_position, o) -- overlay ↔ above ↔ below
end

------------------------------------------------------------------------
-- Setup ----------------------------------------------------------------
------------------------------------------------------------------------
function M.setup(opts)
  if M._setup_called then return end
  M._setup_called = true
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M._create_hl_groups()
  M._set_keymaps()
  M.enable()
end

return M
