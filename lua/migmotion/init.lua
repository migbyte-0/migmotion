-- migmotion.lua — Tiny superscript navigator (size & colour toggles)
-- Author: migbyte — MIT | Neovim ≥ 0.9

-----------------------------------------------------------------------
-- CONFIG -------------------------------------------------------------
-----------------------------------------------------------------------
local M = {}

M.config = {
  max        = 0,            -- 0 ⇒ until EOL
  before     = true,
  after      = true,
  colors     = { Red = "DiagnosticError", Yellow = "WarningMsg" }, -- link groups
  size_modes = { "superscript", "normal" }, -- increase / decrease cycles
  hl_prefix  = "Migmotion",
}

M.ns          = vim.api.nvim_create_namespace("migmotion")
M.enabled     = false
M._color_key  = "Red"        -- active colour key
M._size_idx   = 1            -- 1=superscript, 2=normal

-----------------------------------------------------------------------
-- HIGHLIGHT SETUP -----------------------------------------------------
-----------------------------------------------------------------------
local function ensure_hl()
  for key, link in pairs(M.config.colors) do
    local g = M.config.hl_prefix .. key
    if vim.fn.hlID(g)==0 then vim.api.nvim_set_hl(0, g, { link = link }) end
  end
end

-----------------------------------------------------------------------
-- GLYPH ENCODING ------------------------------------------------------
-----------------------------------------------------------------------
local sup = { ["0"]="⁰",["1"]="¹",["2"]="²",["3"]="³",["4"]="⁴",["5"]="⁵",
              ["6"]="⁶",["7"]="⁷",["8"]="⁸",["9"]="⁹" }
local function glyph(dist)
  if M._size_idx==2 then return tostring(dist) end   -- normal digits
  -- superscript mode (show only leading digit beyond 9)
  local s=tostring(dist)
  return sup[s:sub(1,1)]
end

-----------------------------------------------------------------------
-- WORD PARSER ---------------------------------------------------------
-----------------------------------------------------------------------
local function words(line)
  local t,idx={},1; while true do local s,e=line:find("%S+",idx); if not s then break end t[#t+1]={start=s-1,len=e-s+1}; idx=e+1 end; return t end

-----------------------------------------------------------------------
-- DRAW ---------------------------------------------------------------
-----------------------------------------------------------------------
local function place(buf,row,col,text,hl)
  vim.api.nvim_buf_set_extmark(buf,M.ns,row,0,{virt_text={{text,hl}},virt_text_pos="overlay",virt_text_win_col=col,priority=200,hl_mode="combine"})
end

function M.draw()
  if not M.enabled then return end; ensure_hl()
  local buf=vim.api.nvim_get_current_buf(); local win=vim.api.nvim_get_current_win()
  local r,c=unpack(vim.api.nvim_win_get_cursor(win)); r=r-1
  vim.api.nvim_buf_clear_namespace(buf,M.ns,0,-1)
  local line=vim.api.nvim_buf_get_lines(buf,r,r+1,false)[1] or ""; if line=="" then return end
  local wl=words(line); if #wl==0 then return end
  local ci=1; for i,w in ipairs(wl) do if c>=w.start and c<w.start+w.len then ci=i break end end
  local before=(M.config.before and (M.config.max>0 and math.min(M.config.max,ci-1) or ci-1) or 0)
  local after=(M.config.after and (M.config.max>0 and M.config.max or #wl-ci) or 0)
  local hl=M.config.hl_prefix..M._color_key
  local function mark(i)
    local w=wl[i]; local d=math.abs(i-ci); local g=glyph(d); local col_before=w.start-1
    if col_before<0 then col_before=0 end
    place(buf,r,col_before,g,hl)
  end
  for i=ci-before,ci-1 do if i>=1 then mark(i) end end
  for i=ci+1,ci+after do if i<=#wl then mark(i) end end
end

-----------------------------------------------------------------------
-- TOGGLES -------------------------------------------------------------
-----------------------------------------------------------------------
local function attach()
  if M._au then return end
  M._au=vim.api.nvim_create_augroup("Migmotion",{})
  vim.api.nvim_create_autocmd({"CursorMoved","CursorMovedI"},{group=M._au,callback=M.draw})
end
function M.enable()  M.enabled=true; attach(); M.draw() end
function M.disable() M.enabled=false; if M._au then vim.api.nvim_del_augroup_by_id(M._au);M._au=nil end; vim.api.nvim_buf_clear_namespace(0,M.ns,0,-1) end
function M.toggle() (M.enabled and M.disable or M.enable)() end
function M.set_color(key) if M.config.colors[key] then M._color_key=key; M.draw() end end
function M.increase_size() M._size_idx=math.min(#M.config.size_modes,M._size_idx+1); M.draw() end
function M.decrease_size() M._size_idx=math.max(1,M._size_idx-1); M.draw() end

-----------------------------------------------------------------------
-- KEYMAPS -------------------------------------------------------------
-----------------------------------------------------------------------
local function maps()
  local map,o=vim.keymap.set,{noremap=true,silent=true}
  map("n","<leader>mn",M.toggle,o)
  map("n","<leader>mm",M.increase_size,o)
  map("n","<leader>ml",M.decrease_size,o)
  map("n","<leader>mcr",function() M.set_color("Red") end,o)
  map("n","<leader>mcy",function() M.set_color("Yellow") end,o)
  for n=1,9 do
    map("n","<leader>"..n,function() vim.cmd(n.."w") end,o)
    map("n","<leader><S-"..n..">",function() vim.cmd(n.."b") end,o)
  end
end

-----------------------------------------------------------------------
-- SETUP ---------------------------------------------------------------
-----------------------------------------------------------------------
function M.setup(opts)
  if M._setup then return end; M._setup=true
  M.config=vim.tbl_deep_extend("force",M.config,opts or {})
  maps(); M.enable()
end

return M
