-- migmotion.lua ─ Word‑navigation halos & gradient highlighter
-- Author: migbyte — MIT | Neovim ≥ 0.9

-- 2025‑04‑26‑c
-- • Fix highlight‑mode crash (nvim_buf_add_highlight param order).
-- • Coloured digits/dots assured (if termguicolors off, links fall back).
-- • Halos rendered with virt_text_pos = "inline" so they **precede** the
--   word without overwriting characters.
-- • Superscript for 1‑9; 10‑99 rendered as two stacked superscripts: the
--   first digit inline before word, the second digit one row **above**.
--   Keeps word spacing intact even for double‑digit offsets.
-- • New toggle <leader>mh (halo ↔ highlight).

local M = {}

------------------------------------------------------------------------
-- Config ---------------------------------------------------------------
------------------------------------------------------------------------
M.config = {
  max       = 0,            -- 0 ⇒ to end of line
  before    = true,
  after     = true,
  virt      = "number",      -- "number" | "dot"
  position  = "inline",     -- inline halos (push text) vs overlay unused
  mode      = "halo",       -- halo | highlight
  colors    = {
    "#98c379", "#61afef", "#e5c07b", "#c678dd", "#ff6ac1", "#56b6c2",
    "#e06c75", "#d19a66", "#4aa5f0", "#abb2bf", "#5c6370", "#be5046",
  },
  hl_prefix = "Migmotion",
}

M.ns = vim.api.nvim_create_namespace("migmotion")
M.enabled = false

------------------------------------------------------------------------
-- Highlight groups -----------------------------------------------------
------------------------------------------------------------------------
local function ensure_hls()
  for i, col in ipairs(M.config.colors) do
    local group = M.config.hl_prefix .. i
    if vim.fn.hlID(group) == 0 then
      if vim.o.termguicolors and col:match("^#%x%x%x%x%x%x$") then
        vim.api.nvim_set_hl(0, group, { fg = col })
      else
        vim.api.nvim_set_hl(0, group, { link = "Identifier" })
      end
    end
  end
end

------------------------------------------------------------------------
-- Utils ----------------------------------------------------------------
------------------------------------------------------------------------
local supers = { ["0"]="⁰",["1"]="¹",["2"]="²",["3"]="³",["4"]="⁴",["5"]="⁵",
                 ["6"]="⁶",["7"]="⁷",["8"]="⁸",["9"]="⁹" }
local function sup(d) return supers[d] end
local function to_sup(n)
  local s = tostring(n)
  if #s == 1 then return sup(s) end
  -- two digits: we draw first digit inline, second digit above via extra mark
  return { top = sup(s:sub(2,2)), base = sup(s:sub(1,1)) }
end

local function words(line)
  local t, i = {}, 1
  while true do
    local s,e = line:find("%S+", i); if not s then break end
    t[#t+1] = { start=s-1, stop=e, len=e-s+1 }; i = e+1
  end
  return t
end

------------------------------------------------------------------------
-- Draw -----------------------------------------------------------------
------------------------------------------------------------------------
function M.draw()
  if not M.enabled then return end
  ensure_hls()

  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win)); row=row-1
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)

  local line = vim.api.nvim_buf_get_lines(buf, row, row+1, false)[1] or ""
  if line=="" then return end
  local wl = words(line); if #wl==0 then return end

  local ci = 1; for i,w in ipairs(wl) do if col>=w.start and col<w.stop then ci=i break end end
  local limit=#wl; local before=(M.config.before and (M.config.max>0 and M.config.max or limit) or 0)
  local after=(M.config.after  and (M.config.max>0 and M.config.max or limit) or 0)

  ----------------------------------------------------------------------
  -- highlight mode -----------------------------------------------------
  ----------------------------------------------------------------------
  if M.config.mode=="highlight" then
    for i=math.max(1,ci-before), math.min(#wl,ci+after) do
      if i~=ci then
        local hl = M.config.hl_prefix..(((math.abs(i-ci)-1)%#M.config.colors)+1)
        vim.api.nvim_buf_add_highlight(buf, M.ns, hl, row, wl[i].start, wl[i].stop)
      end
    end
    return
  end

  ----------------------------------------------------------------------
  -- halo mode ----------------------------------------------------------
  ----------------------------------------------------------------------
  local function place(i)
    local w = wl[i]
    local dist = i-ci
    local hl = M.config.hl_prefix..(((math.abs(dist)-1)%#M.config.colors)+1)
    local glyph = (M.config.virt=="number" and to_sup(math.abs(dist)) or "•")
    local col_target = w.start  -- inline will insert before word

    if type(glyph)=="table" then
      -- two-digit: draw top digit above
      vim.api.nvim_buf_set_extmark(buf, M.ns, row-1 >=0 and row-1 or row, 0, {
        virt_text = { { glyph.top, hl } },
        virt_text_pos = "inline",
        virt_text_win_col = col_target,
        hl_mode="combine", priority=200,
      })
      glyph = glyph.base
    end

    vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
      virt_text = { { glyph, hl } },
      virt_text_pos = "inline",
      virt_text_win_col = col_target,
      hl_mode = "combine", priority = 200,
    })
  end

  for i = math.max(1,ci-before), ci-1           do place(i) end
  for i = ci+1,           math.min(#wl, ci+after) do place(i) end
end

------------------------------------------------------------------------
-- State & autocmd ------------------------------------------------------
------------------------------------------------------------------------
local function attach()
  if M._au then return end
  M._au = vim.api.nvim_create_augroup("Migmotion", {})
  vim.api.nvim_create_autocmd({"CursorMoved","CursorMovedI"}, {group=M._au, callback=M.draw})
end
function M.enable()  M.enabled=true; attach(); M.draw() end
function M.disable() M.enabled=false; if M._au then vim.api.nvim_del_augroup_by_id(M._au); M._au=nil end; vim.api.nvim_buf_clear_namespace(0,M.ns,0,-1) end
function M.toggle() (M.enabled and M.disable or M.enable)() end

------------------------------------------------------------------------
-- Toggles --------------------------------------------------------------
------------------------------------------------------------------------
function M.toggle_virt()  M.config.virt = (M.config.virt=="number" and "dot" or "number"); M.draw() end
function M.toggle_mode()  M.config.mode  = (M.config.mode =="halo" and "highlight" or "halo"); M.draw() end
function M.toggle_pos()   M.config.position = (M.config.position=="inline" and "overlay" or "inline"); M.draw() end

------------------------------------------------------------------------
-- Keymaps --------------------------------------------------------------
------------------------------------------------------------------------
local function maps()
  local map, o = vim.keymap.set, {noremap=true,silent=true}
  map("n","<leader>mn",M.toggle,o)
  map("n","<leader>mv",M.toggle_virt,o)
  map("n","<leader>mc",M.toggle_pos,o)
  map("n","<leader>mh",M.toggle_mode,o)
  for n=1,9 do
    map("n","<leader>"..n,function() vim.cmd((n).."w") end,o)
    map("n","<leader><S-"..n..">",function() vim.cmd((n).."b") end,o)
  end
end

------------------------------------------------------------------------
-- Setup ----------------------------------------------------------------
------------------------------------------------------------------------
function M.setup(opts)
  if M._setup then return end
  M._setup = true
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  ensure_hls(); maps(); M.enable()
end

return M
