-- migmotion.lua — Minimal superscript navigator (red/yellow)
-- Author: migbyte — MIT | Neovim ≥ 0.9

local M = {}

-- Config ----------------------------------------------------------------
M.config = {
  max       = 0,            -- 0 ⇒ until EOL
  before    = true,
  after     = true,
  colors    = { "Red", "Yellow" }, -- cycles red → yellow → red …
  hl_prefix = "Migmotion",
}

M.ns      = vim.api.nvim_create_namespace("migmotion")
M.enabled = false

-- Superscript map -------------------------------------------------------
local sup = { ["0"]="⁰",["1"]="¹",["2"]="²",["3"]="³",["4"]="⁴",["5"]="⁵",
              ["6"]="⁶",["7"]="⁷",["8"]="⁸",["9"]="⁹" }

-- Ensure highlight groups ----------------------------------------------
local function ensure_hl()
  for i,col in ipairs(M.config.colors) do
    local group = M.config.hl_prefix..i
    if vim.fn.hlID(group)==0 then
      vim.api.nvim_set_hl(0, group, { link = col })
    end
  end
end

-- Word parser -----------------------------------------------------------
local function words(line)
  local t, idx = {}, 1
  while true do
    local s,e = line:find("%S+", idx); if not s then break end
    t[#t+1] = { start=s-1, stop=e, len=e-s+1 }
    idx = e+1
  end
  return t
end

-- Drawing ---------------------------------------------------------------
local function place_mark(buf, row, col, text, hl)
  vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
    virt_text = { { text, hl } },
    virt_text_pos = "overlay",
    virt_text_win_col = col,
    hl_mode = "combine", priority = 200,
  })
end

function M.draw()
  if not M.enabled then return end; ensure_hl()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win)); row=row-1
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)

  local line = vim.api.nvim_buf_get_lines(buf,row,row+1,false)[1] or ""
  if line=="" then return end
  local wl = words(line); if #wl==0 then return end

  local ci = 1; for i,w in ipairs(wl) do if col>=w.start and col<w.stop then ci=i break end end
  local limit=#wl; local before=(M.config.before and (M.config.max>0 and M.config.max or limit) or 0)
  local after=(M.config.after  and (M.config.max>0 and M.config.max or limit) or 0)

  local function place(i)
    local w = wl[i]; local dist = math.abs(i-ci)
    local digits = tostring(dist)
    local hl = M.config.hl_prefix..(((dist-1)%#M.config.colors)+1)
    local col_target = math.max(0, w.start-1)  -- before word

    if #digits==1 then
      place_mark(buf,row,col_target,sup[digits],hl)
    else
      -- stack two digits
      local top = sup[digits:sub(1,1)]
      local base = sup[digits:sub(2,2)]
      if row>0 then place_mark(buf,row-1,col_target,top,hl) end
      place_mark(buf,row,col_target,base,hl)
    end
  end

  for i=math.max(1,ci-before), ci-1             do place(i) end
  for i=ci+1,           math.min(#wl,ci+after) do place(i) end
end

-- State -----------------------------------------------------------------
local function attach()
  if M._au then return end
  M._au = vim.api.nvim_create_augroup("Migmotion", {})
  vim.api.nvim_create_autocmd({"CursorMoved","CursorMovedI"}, {group=M._au, callback=M.draw})
end
function M.enable()  M.enabled=true; attach(); M.draw() end
function M.disable() M.enabled=false; if M._au then vim.api.nvim_del_augroup_by_id(M._au);M._au=nil end; vim.api.nvim_buf_clear_namespace(0,M.ns,0,-1) end
function M.toggle() (M.enabled and M.disable or M.enable)() end

-- Keymaps ---------------------------------------------------------------
local function maps()
  local map,o=vim.keymap.set,{noremap=true,silent=true}
  map("n","<leader>mn",M.toggle,o)
  for n=1,9 do
    map("n","<leader>"..n,function() vim.cmd(n.."w") end,o)
    map("n","<leader><S-"..n..">",function() vim.cmd(n.."b") end,o)
  end
end

-- Setup -----------------------------------------------------------------
function M.setup(opts)
  if M._setup then return end; M._setup=true
  M.config = vim.tbl_deep_extend("force",M.config,opts or {})
  maps(); M.enable()
end

return M
