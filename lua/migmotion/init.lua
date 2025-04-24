-- migmotion.lua
-- Numbered & coloured virtual-text word navigator for Neovim
-- Author: migbyte — MIT

-- 𝐂𝐡𝐚𝐧𝐠𝐞𝐥𝐨𝐠 (2025-04-25)
-- • Switched to extmark `virt_text_above` so *above* halos float in their own
--   virtual row — never clobber the real line above.
-- • Added `virt_text_below` helper for symmetrical *below* halos (uses a dummy
--   extmark on the next line with `virt_text_above = true`).
-- • Horizontal centring kept via `virt_text_win_col` (Neovim ≥0.9).
-- • Unlimited distance by default (`max = 0` ⇒ until EOL).
-- • Colours now guaranteed: highlight groups are linked to built-ins if the
--   requested name isn’t a valid hex or X11 colour.
-- • Mapping kept: `<leader>mn` (toggle plugin), `<leader>mv` (numbers ↔ dots),
--   `<leader>mc` (overlay ↔ above ↔ below).

local M = {}

------------------------------------------------------------------------
-- Default configuration ------------------------------------------------
------------------------------------------------------------------------
M.config = {
  max      = 0,            -- 0 ⇒ unlimited to EOL
  before   = true,         -- draw halos before the cursor word
  after    = true,         -- draw halos after  the cursor word
  virt     = "number",      -- "number" | "dot"
  position = "above",       -- "overlay" | "above" | "below"
  colors   = {
    "#98c379", "#61afef", "#e5c07b", "#c678dd", "#ff6ac1", "#56b6c2",
    "#e06c75", "#d19a66", "#4aa5f0", "#abb2bf", "#5c6370", "#be5046",
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
local function is_hex(c) return c:match("^#%x%x%x%x%x%x$") end
function M._create_hl_groups()
  for i, color in ipairs(M.config.colors) do
    local group = M.config.hl_prefix .. i
    if vim.fn.hlID(group) == 0 then
      if is_hex(color) or vim.go.termguicolors and color:match("%a") then
        vim.api.nvim_set_hl(0, group, { fg = color })
      else  -- fallback, link to built-ins
        vim.api.nvim_set_hl(0, group, { link = "Identifier" })
      end
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
local function set_mark(opts)
  local bufnr = opts.bufnr
  local txt   = vim.api.nvim_buf_get_lines(bufnr, opts.row, opts.row + 1, false)[1] or ""
  local col   = math.max(0, math.min(opts.col, #txt))
  opts.opts.virt_text_win_col = col  -- absolute column for NEOVIM ≥0.9
  return vim.api.nvim_buf_set_extmark(bufnr, M.ns, opts.row, 0, opts.opts)
end

------------------------------------------------------------------------
-- Draw halos -----------------------------------------------------------
------------------------------------------------------------------------
function M.draw()
  if not M.enabled then return end

  local bufnr  = vim.api.nvim_get_current_buf()
  local winid  = vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(winid))
  row = row - 1   -- 0-based

  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line or line == "" then return end
  local words = parse_line(line)
  if #words == 0 then return end

  -- find current word index
  local cur = 1
  for i, w in ipairs(words) do
    if col >= w.start and col < w.stop then cur = i break
    elseif col < w.start then cur = math.max(1, i - 1) break end
  end

  local before = M.config.before and (M.config.max > 0 and M.config.max or #words) or 0
  local after  = M.config.after  and (M.config.max > 0 and M.config.max or #words) or 0

  local function glyph(dist)
    return (M.config.virt == "number") and tostring(math.abs(dist)) or "•"
  end
  local function hlg(dist)
    local idx = (math.abs(dist) - 1) % #M.config.colors + 1
    return M.config.hl_prefix .. idx
  end

  ----------------------------------------------------------------------
  -- Placement helpers --------------------------------------------------
  ----------------------------------------------------------------------
  local function above_opts(text, hl)
    return {
      virt_text = { { text, hl } },
      virt_text_pos = "overlay",
      virt_text_above = true,          -- Float above without touching real line
      hl_mode   = "combine",
      priority  = 200,
    }
  end

  local function below_opts(text, hl)
    -- place an extmark on row+1 but draw *above* it ⇒ visually below cursor line
    return {
      virt_text = { { text, hl } },
      virt_text_pos = "overlay",
      virt_text_above = true,
      hl_mode   = "combine",
      priority  = 200,
    }
  end

  local function overlay_opts(text, hl)
    return {
      virt_text = { { text, hl } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
      priority = 200,
    }
  end

  local function place(i)
    local w    = words[i]
    local dist = i - cur
    local sym  = glyph(dist)
    local mid  = w.start + math.floor((w.len - #sym) / 2)

    local opts_factory = (M.config.position == "overlay" and overlay_opts)
                      or (M.config.position == "below"   and below_opts)
                      or above_opts

    local row_for_mark = row
    if M.config.position == "below" then
      row_for_mark = math.min(row + 1, vim.api.nvim_buf_line_count(bufnr))
    end

    set_mark({
      bufnr = bufnr,
      row   = row_for_mark,
      col   = mid,
      opts  = opts_factory(sym, hlg(dist)),
    })
  end

  for i = math.max(1, cur - before), cur - 1 do place(i) end
  for i = cur + 1, math.min(#words, cur + after) do place(i) end
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

function M.enable()  M.enabled = true  attach_autocmd()  M.draw() end
function M.disable() M.enabled = false
  if M._augroup then vim.api.nvim_del_augroup_by_id(M._augroup) M._augroup=nil end
  vim.api.nvim_buf_clear_namespace(0, M.ns, 0, -1)
end
function M.toggle() (M.enabled and M.disable or M.enable)() end

------------------------------------------------------------------------
-- Toggles --------------------------------------------------------------
------------------------------------------------------------------------
function M.toggle_virt()
  M.config.virt = (M.config.virt == "number") and "dot" or "number"; M.draw()
end
function M.toggle_position()
  M.config.position = (M.config.position == "overlay" and "above")
                   or (M.config.position == "above"   and "below")
                   or "overlay"; M.draw()
end

------------------------------------------------------------------------
-- Keymaps --------------------------------------------------------------
------------------------------------------------------------------------
local function set_keymaps()
  local map, o = vim.keymap.set, { noremap=true, silent=true }
  map("n", "<leader>mn", M.toggle,          o)
  map("n", "<leader>mv", M.toggle_virt,     o)
  map("n", "<leader>mc", M.toggle_position, o)
end

------------------------------------------------------------------------
-- Setup ----------------------------------------------------------------
------------------------------------------------------------------------
function M.setup(opts)
  if M._setup_called then return end
  M._setup_called = true
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M._create_hl_groups()
  set_keymaps()
  M.enable()
end

return M
