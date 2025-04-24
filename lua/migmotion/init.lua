-- migmotion.lua ─ Numbered & coloured virtual-text word navigator for Neovim
-- Author: migbyte — MIT

-- ──────────────────────────────────────────────────────────────────────
-- Changelog (2025-04-25-b)
-- • Fix: removed unsupported `virt_text_above` key (now use
--   `virt_text_pos = "above"`).
-- • "Below" halos use extmark on *next* row with `virt_text_pos="above"`.
-- • Added superscript digits → tiny numbers when virt = "number".
-- • Unlimited range (`max = 0`) + fade-out timer (configurable).
-- • Jump hotkeys <leader>1-9 → `{count}w` forward / `{count}b` backward.
-- • Mapping cycle kept on <leader>mc.
-- ──────────────────────────────────────────────────────────────────────

local M, uv = {}, vim.loop

------------------------------------------------------------------------
-- Default configuration ------------------------------------------------
------------------------------------------------------------------------
M.config = {
  max        = 0,             -- 0 ⇒ unlimited to EOL
  before     = true,
  after      = true,
  virt       = "number",       -- "number" | "dot"
  position   = "above",        -- "overlay" | "above" | "below"
  fade_ms    = 150,           -- halos disappear after inactivity (0 = never)
  colors     = {
    "#98c379", "#61afef", "#e5c07b", "#c678dd", "#ff6ac1", "#56b6c2",
    "#e06c75", "#d19a66", "#4aa5f0", "#abb2bf", "#5c6370", "#be5046",
  },
  hl_prefix  = "Migmotion",
}

------------------------------------------------------------------------
-- Internal state -------------------------------------------------------
------------------------------------------------------------------------
M.ns          = vim.api.nvim_create_namespace("migmotion")
M.enabled     = false
M._fade_timer = nil  -- uv timer handle

------------------------------------------------------------------------
-- Highlight groups -----------------------------------------------------
------------------------------------------------------------------------
local function is_hex(c) return c:match("^#%x%x%x%x%x%x$") end
function M._create_hl_groups()
  for i, color in ipairs(M.config.colors) do
    local group = M.config.hl_prefix .. i
    if vim.fn.hlID(group) == 0 then
      if is_hex(color) then
        vim.api.nvim_set_hl(0, group, { fg = color })
      else
        vim.api.nvim_set_hl(0, group, { link = "Identifier" })
      end
    end
  end
end

------------------------------------------------------------------------
-- Word parser ----------------------------------------------------------
------------------------------------------------------------------------
local function parse_line(line)
  local tbl, idx = {}, 1
  while true do
    local s, e = line:find("%S+", idx)
    if not s then break end
    tbl[#tbl + 1] = { start = s - 1, stop = e, len = e - s + 1 }
    idx = e + 1
  end
  return tbl
end

------------------------------------------------------------------------
-- Superscript digits ---------------------------------------------------
------------------------------------------------------------------------
local supers = { ["0"]="⁰",["1"]="¹",["2"]="²",["3"]="³",["4"]="⁴",["5"]="⁵",
                 ["6"]="⁶",["7"]="⁷",["8"]="⁸",["9"]="⁹" }
local function to_sup(n)
  return tostring(n):gsub("%d", supers)
end

------------------------------------------------------------------------
-- Draw halos -----------------------------------------------------------
------------------------------------------------------------------------
function M.draw()
  if not M.enabled then return end

  local bufnr, winid = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local row, col     = unpack(vim.api.nvim_win_get_cursor(winid)); row = row - 1
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if line == "" or not line then return end
  local words = parse_line(line); if #words == 0 then return end

  -- locate current word
  local cur = 1
  for i, w in ipairs(words) do
    if col >= w.start and col < w.stop then cur = i break
    elseif col < w.start then cur = math.max(1, i - 1) break end
  end

  local limit = (#words) -- until EOL by default
  local before = M.config.before and (M.config.max>0 and M.config.max or limit) or 0
  local after  = M.config.after  and (M.config.max>0 and M.config.max or limit) or 0

  local function glyph(d)
    return (M.config.virt == "number") and to_sup(math.abs(d)) or "•"
  end
  local function hlg(d)
    local idx = (math.abs(d) - 1) % #M.config.colors + 1
    return M.config.hl_prefix .. idx
  end

  -- fade-out timer reset
  if M.config.fade_ms > 0 then
    if M._fade_timer then M._fade_timer:stop(); M._fade_timer:close() end
    M._fade_timer = uv.new_timer()
    M._fade_timer:start(M.config.fade_ms, 0, function()
      vim.schedule(function()
        if M.enabled then vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1) end
      end)
    end)
  end

  local function place(i)
    local w, dist = words[i], i - cur
    local sym     = glyph(dist)
    local col_mid = w.start + math.floor((w.len - #sym) / 2)

    local target_row, vtp
    if M.config.position == "overlay" then
      target_row, vtp = row, "overlay"
    elseif M.config.position == "above" then
      target_row, vtp = row, "above"
    else -- below
      target_row, vtp = math.min(row + 1, vim.api.nvim_buf_line_count(bufnr)-1), "above"
    end

    vim.api.nvim_buf_set_extmark(bufnr, M.ns, target_row, 0, {
      virt_text = { { sym, hlg(dist) } },
      virt_text_pos = vtp,
      virt_text_win_col = col_mid,
      hl_mode = "combine",
      priority = 200,
    })
  end

  for i = math.max(1, cur - before), cur - 1            do place(i) end
  for i = cur + 1,           math.min(#words, cur + after) do place(i) end
end

------------------------------------------------------------------------
-- Enable/disable & autocmd ---------------------------------------------
------------------------------------------------------------------------
local function attach()
  if M._augroup then return end
  M._augroup = vim.api.nvim_create_augroup("Migmotion", {})
  vim.api.nvim_create_autocmd({"CursorMoved","CursorMovedI"}, {
    group = M._augroup,
    callback = M.draw,
  })
end

function M.enable()  M.enabled=true; attach(); M.draw() end
function M.disable() M.enabled=false
  if M._augroup then vim.api.nvim_del_augroup_by_id(M._augroup); M._augroup=nil end
  vim.api.nvim_buf_clear_namespace(0, M.ns, 0, -1)
end
function M.toggle() (M.enabled and M.disable or M.enable)() end

------------------------------------------------------------------------
-- Toggles --------------------------------------------------------------
------------------------------------------------------------------------
function M.toggle_virt()    M.config.virt    = (M.config.virt=="number" and "dot" or "number"); M.draw() end
function M.toggle_position() M.config.position = (M.config.position=="overlay" and "above") or (M.config.position=="above" and "below") or "overlay"; M.draw() end

------------------------------------------------------------------------
-- Keymaps --------------------------------------------------------------
------------------------------------------------------------------------
local function set_keymaps()
  local map, o = vim.keymap.set, { noremap=true, silent=true }
  map("n", "<leader>mn", M.toggle,          o)
  map("n", "<leader>mv", M.toggle_virt,     o)
  map("n", "<leader>mc", M.toggle_position, o)
  -- jump hot-keys
  for n=1,9 do
    map("n", string.format("<leader>%d", n), function()
      vim.cmd(string.format("normal! %dw", n))
    end, o)
    map("n", string.format("<leader><S-%d>", n), function()
      vim.cmd(string.format("normal! %db", n))
    end, o)
  end
end

------------------------------------------------------------------------
-- Public setup ---------------------------------------------------------
------------------------------------------------------------------------
function M.setup(opts)
  if M._setup_called then return end
  M._setup_called=true
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M._create_hl_groups()
  set_keymaps()
  M.enable()
end

return M
