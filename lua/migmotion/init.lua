-- migmotion.lua
-- Numbered & coloured virtual‑text word navigator for Neovim
-- Author: migbyte
-- License: MIT

local M = {}

------------------------------------------------------------------------
-- Default configuration ------------------------------------------------
------------------------------------------------------------------------
M.config = {
  max = 12,               -- how many words to show before / after cursor word
  before = true,          -- draw before the cursor word
  after  = true,          -- draw after the cursor word
  virt   = "number",      -- "number" | "dot"
  position = "overlay",   -- "overlay" | "above" | "below"
  colors = {
    "Green", "Blue", "Yellow", "Purple", "Magenta", "Cyan", "Red", "Orange",
    "Indigo", "White", "Grey", "Brown",
  },
  hl_prefix = "Migmotion", -- prefix for the generated highlight groups
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
    if vim.fn.hlID(group) == 0 then     -- honour user‑defined groups
      vim.api.nvim_set_hl(0, group, { fg = color })
    end
  end
end

------------------------------------------------------------------------
-- Split current line into words ----------------------------------------
------------------------------------------------------------------------
local function parse_line(line)
  local words, byteidx = {}, 1
  while true do
    local s, e = line:find("%S+", byteidx)
    if not s then break end
    words[#words + 1] = { start = s - 1, stop = e, len = e - s + 1 }
    byteidx = e + 1
  end
  return words
end

------------------------------------------------------------------------
-- Safe extmark placement helper ----------------------------------------
------------------------------------------------------------------------
local function set_mark(bufnr, ns, row, col, opts)
  -- clip col so it never exceeds line length (Neovim throws otherwise)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  if col > #line then col = #line end
  return vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, opts)
end

------------------------------------------------------------------------
-- Core: draw the halos --------------------------------------------------
------------------------------------------------------------------------
function M.draw()
  if not M.enabled then return end

  local bufnr  = vim.api.nvim_get_current_buf()
  local winid  = vim.api.nvim_get_current_win()
  local row0, col = unpack(vim.api.nvim_win_get_cursor(winid))
  row0 = row0 - 1   -- convert to 0‑based

  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

  local line = vim.api.nvim_buf_get_lines(bufnr, row0, row0 + 1, false)[1]
  if not line or line == "" then return end

  local words = parse_line(line)
  if #words == 0 then return end

  -- locate the word under (or nearest left of) the cursor
  local cur_idx = 1
  for i, w in ipairs(words) do
    if col >= w.start and col < w.stop then
      cur_idx = i; break
    elseif col < w.start then
      cur_idx = math.max(1, i - 1); break
    end
  end

  local max_before = M.config.before and M.config.max or 0
  local max_after  = M.config.after  and M.config.max or 0

  -- target row + virt_text_pos depend on chosen layout
  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  local target_row     = row0
  local virt_pos       = "overlay"
  if M.config.position == "above" then
    target_row = math.max(0, row0 - 1)
  elseif M.config.position == "below" then
    target_row = math.min(buf_line_count - 1, row0 + 1)
  end

  local function symbol(dist)
    return (M.config.virt == "number") and tostring(math.abs(dist)) or "•"
  end
  local function hl(dist)
    local idx = (math.abs(dist) - 1) % #M.config.colors + 1
    return M.config.hl_prefix .. idx
  end
  local function place(i)
    local w     = words[i]
    local dist  = i - cur_idx
    set_mark(bufnr, M.ns, target_row, w.start, {
      virt_text     = { { symbol(dist), hl(dist) } },
      virt_text_pos = virt_pos,
      hl_mode       = "combine",
    })
  end

  for i = math.max(1, cur_idx - max_before), cur_idx - 1 do place(i) end
  for i = cur_idx + 1, math.min(#words, cur_idx + max_after) do place(i) end
end

------------------------------------------------------------------------
-- Enable / Disable ------------------------------------------------------
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
-- Toggles ---------------------------------------------------------------
------------------------------------------------------------------------
function M.toggle_virt()
  M.config.virt = (M.config.virt == "number") and "dot" or "number"
  M.draw()
end
function M.toggle_position()
  local cycle = { overlay = "above", above = "below", below = "overlay" }
  M.config.position = cycle[M.config.position]
  M.draw()
end

------------------------------------------------------------------------
-- Keymaps ---------------------------------------------------------------
------------------------------------------------------------------------
function M._set_keymaps()
  local map, opts = vim.keymap.set, { noremap = true, silent = true }
  map("n", "<leader>mn", M.toggle,          opts)
  map("n", "<leader>mv", M.toggle_virt,     opts)
  map("n", "<leader>mc", M.toggle_position, opts)
end

------------------------------------------------------------------------
-- Public setup ----------------------------------------------------------
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
