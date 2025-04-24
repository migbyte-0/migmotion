-- migmotion.lua ─ Word‑navigation halos & colour‑gradient highlighter for Neovim
-- Author: migbyte — MIT
-- Compatible with Neovim ≥ 0.9.0 (no unstable API)

-- ╭─────────────────────────────────────────────────────────────╮
-- │ 2025‑04‑26 – overhaul                                       │
-- │ •   Removed fade‑out; halos persist.                         │
-- │ •   Added *highlight mode* (gradient word highlights).       │
-- │     Toggle with <leader>mh.                                  │
-- │ •   Tiny superscript numbers/dots now shown *before* word.   │
-- │ •   Fixed colouring: uses #hex or links to Identifier.       │
-- │ •   Replaced invalid virt_text_pos="above" (not in 0.9).    │
-- ╰─────────────────────────────────────────────────────────────╯

local M, uv = {}, vim.loop

------------------------------------------------------------------------
-- Configuration --------------------------------------------------------
------------------------------------------------------------------------
M.config = {
  max        = 0,            -- 0 ⇒ until EOL
  before     = true,
  after      = true,
  virt       = "number",      -- "number" | "dot"
  position   = "overlay",    -- "overlay" | "inline"
  mode       = "halo",       -- "halo" | "highlight" (toggle with <leader>mh)
  colors     = {
    "#98c379", "#61afef", "#e5c07b", "#c678dd", "#ff6ac1", "#56b6c2",
    "#e06c75", "#d19a66", "#4aa5f0", "#abb2bf", "#5c6370", "#be5046",
  },
  hl_prefix  = "Migmotion",
}

M.ns      = vim.api.nvim_create_namespace("migmotion")
M.enabled = false

------------------------------------------------------------------------
-- Highlight groups -----------------------------------------------------
------------------------------------------------------------------------
local function is_hex(c) return c:match("^#%x%x%x%x%x%x$") end
local function ensure_hl()
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
-- Helpers --------------------------------------------------------------
------------------------------------------------------------------------
local supers = { ["0"]="⁰",["1"]="¹",["2"]="²",["3"]="³",["4"]="⁴",["5"]="⁵",
                 ["6"]="⁶",["7"]="⁷",["8"]="⁸",["9"]="⁹" }
local function sup_num(n)
  return tostring(n):gsub("%d", supers)
end

local function words_in(line)
  local t, idx = {}, 1
  while true do
    local s, e = line:find("%S+", idx)
    if not s then break end
    t[#t+1] = { start=s-1, stop=e, len=e-s+1 }
    idx = e+1
  end
  return t
end

------------------------------------------------------------------------
-- Core draw ------------------------------------------------------------
------------------------------------------------------------------------
function M.draw()
  if not M.enabled then return end
  ensure_hl()

  local bufnr, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local row, col   = unpack(vim.api.nvim_win_get_cursor(win)); row = row-1

  -- Clear previous
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row+1, false)[1]
  if not line or line=="" then return end
  local wl = words_in(line); if #wl==0 then return end

  -- find current word index
  local cur=1; for i,w in ipairs(wl) do if col>=w.start and col<w.stop then cur=i break end end

  local limit=#wl; local before=(M.config.before and (M.config.max>0 and M.config.max or limit) or 0)
  local after=(M.config.after and (M.config.max>0 and M.config.max or limit) or 0)

  if M.config.mode=="highlight" then
    -- gradient background fg across words
    for i = math.max(1,cur-before), math.min(#wl,cur+after) do
      if i~=cur then
        local hl=M.config.hl_prefix..(((math.abs(i-cur)-1)%#M.config.colors)+1)
        vim.api.nvim_buf_add_highlight(bufnr,M.ns,row,wl[i].start,wl[i].stop,hl)
      end
    end
    return
  end

  -- halo mode ----------------------------------------------------------
  local function place(i)
    local w=wl[i]; local dist=i-cur; local hl=M.config.hl_prefix..(((math.abs(dist)-1)%#M.config.colors)+1)
    local sym=(M.config.virt=="number") and sup_num(math.abs(dist)) or "•"
    -- we want tiny symbol **before** word; we use inline after previous column
    local col_before=math.max(0,w.start-1)
    vim.api.nvim_buf_set_extmark(bufnr,M.ns,row,0,{
      virt_text={{sym,hl}},
      virt_text_pos="inline",
      virt_text_win_col=col_before,
      hl_mode="combine",
      priority=200,
    })
  end
  for i=math.max(1,cur-before),cur-1              do place(i) end
  for i=cur+1,            math.min(#wl,cur+after) do place(i) end
end

------------------------------------------------------------------------
-- Autocmd & state ------------------------------------------------------
------------------------------------------------------------------------
local function attach()
  if M._au then return end
  M._au=vim.api.nvim_create_augroup("Migmotion",{})
  vim.api.nvim_create_autocmd({"CursorMoved","CursorMovedI"},{group=M._au,callback=M.draw})
end
function M.enable() M.enabled=true; attach(); M.draw() end
function M.disable() M.enabled=false; if M._au then vim.api.nvim_del_augroup_by_id(M._au);M._au=nil end; vim.api.nvim_buf_clear_namespace(0,M.ns,0,-1) end
function M.toggle() (M.enabled and M.disable or M.enable)() end

------------------------------------------------------------------------
-- Toggles --------------------------------------------------------------
------------------------------------------------------------------------
function M.toggle_virt()    M.config.virt=(M.config.virt=="number" and "dot" or "number"); M.draw() end
function M.toggle_position() M.config.position=(M.config.position=="overlay" and "inline" or "overlay"); M.draw() end
function M.toggle_mode()   M.config.mode=(M.config.mode=="halo" and "highlight" or "halo"); M.draw() end

------------------------------------------------------------------------
-- Keymaps --------------------------------------------------------------
------------------------------------------------------------------------
local function maps()
  local map,o=vim.keymap.set,{noremap=true,silent=true}
  map("n","<leader>mn",M.toggle,o)
  map("n","<leader>mv",M.toggle_virt,o)
  map("n","<leader>mc",M.toggle_position,o)
  map("n","<leader>mh",M.toggle_mode,o)
  for n=1,9 do
    map("n",string.format("<leader>%d",n),function() vim.cmd(string.format("normal! %dw",n)) end,o)
    map("n",string.format("<leader><S-%d>",n),function() vim.cmd(string.format("normal! %db",n)) end,o)
  end
end

------------------------------------------------------------------------
-- Setup ----------------------------------------------------------------
------------------------------------------------------------------------
function M.setup(opts)
  if M._setup then return end
  M._setup=true
  M.config = vim.tbl_deep_extend("force",M.config,opts or {})
  ensure_hl(); maps(); M.enable()
end

return M
