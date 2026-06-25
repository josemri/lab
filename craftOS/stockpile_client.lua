--[[
  Stockpile GUI Client v1.0
  Cliente grafico para Stockpile (CC:Tweaked).
 
  Botones:
    DUMP      - Escanea y mueve items del cofre dump al storage
    RETRIEVE  - Trae el item seleccionado del storage al dump
    PUSH      - Mueve TODO del storage al dump
    SEARCH    - Escribe en el campo de busqueda y presiona Enter
    REFRESH   - Recarga la lista de items
    USAGE     - Muestra uso del almacenamiento
    Q         - Salir
 
  Navegacion:
    Click     - Selecciona item / activa campo busqueda / pulsa boton
    Enter     - En busqueda: ejecuta busqueda. En lista: retrieve
    Flechas   - Navegar lista
    Scroll    - Desplazar lista
    Tab/Escape- Salir del campo de busqueda
]]

local GUI = {}

-- Colores
local C = {
  header  = colors.blue,
  body    = colors.black,
  bar     = colors.gray,
  inputBg = colors.gray,
  btn     = colors.cyan,
  btnHov  = colors.lightBlue,
  selBg   = colors.blue,
  title   = colors.white,
  white   = colors.white,
  yellow  = colors.yellow,
  green   = colors.green,
  red     = colors.red,
  gray    = colors.lightGray,
}

-- Layout dinámico
local L = {}
local function layout()
  L.w, L.h = term.getSize()
  L.inputY = 3
  L.listTop = 5
  L.listBot = L.h - 1
  L.statusY = L.h
end

-- Estado
local state = {
  server   = nil,
  items    = {},
  keys     = {},
  scroll   = 0,
  sel      = nil,
  status   = "Iniciando...",
  query    = "",
  input    = false, -- true si el foco esta en el campo de busqueda
}

-- Botones (label, x, accion)
local btnList = {}

local function btn(label, action)
  table.insert(btnList, { label = label, action = action })
end

-- Renderizado
local function rClear(y)
  term.setCursorPos(1, y)
  term.clearLine()
end

local function rHeader()
  term.setBackgroundColor(C.header)
  rClear(1)
  -- Titulo a la izquierda
  term.setTextColor(C.title)
  term.write(" Stockpile ")
  local titleEnd = term.getCursorPos()
  -- Botones alineados a la derecha
  local bx = L.w + 1
  for i = #btnList, 1, -1 do
    local b = btnList[i]
    local bw = #b.label + 3
    bx = bx - bw
    b.x = bx
    b.y = 1
    b.w = bw
  end
  -- Relleno entre titulo y botones
  local firstBtn = btnList[1]
  if firstBtn then
    local gap = firstBtn.x - titleEnd
    if gap > 0 then
      term.setTextColor(C.gray)
      term.write(string.rep(" ", gap))
    end
  end
  for _, b in ipairs(btnList) do
    term.setBackgroundColor(C.btn)
    term.setTextColor(colors.black)
    term.setCursorPos(b.x, b.y)
    term.write(" " .. b.label .. " ")
  end
end

local function rInput()
  term.setBackgroundColor(C.inputBg)
  term.setTextColor(C.gray)
  rClear(L.inputY)
  term.write(" > ")
  local iw = L.w - 3
  local txt = state.query
  if #txt > iw then txt = string.sub(txt, #txt - iw + 1) end
  term.setTextColor(C.white)
  term.write(txt)
  if #txt < iw then
    term.write(string.rep(" ", iw - #txt))
  end
  if state.input then
    term.setCursorPos(3 + #txt, L.inputY)
    term.setCursorBlink(true)
  else
    term.setCursorBlink(false)
  end
end

local function rList()
  local vis = L.listBot - L.listTop + 1
  if vis < 1 then return end

  local n = #state.keys
  if state.scroll > n - vis then state.scroll = math.max(0, n - vis) end
  if state.scroll < 0 then state.scroll = 0 end

  for i = 1, vis do
    local y = L.listTop + i - 1
    if y > L.h then break end
    rClear(y)
    local idx = state.scroll + i
    if idx <= n then
      local id = state.keys[idx]
      local amt = state.items[id]
      local name = id:gsub("^minecraft:", "")
      local sel = (state.sel == idx)

      term.setBackgroundColor(sel and C.selBg or C.body)
      term.setTextColor(C.white)
      term.write(" " .. name)

      -- Barra visual de cantidad
      local barW = 8
      local fill = math.min(barW, math.ceil(amt / 64 * barW))
      local x0 = L.w - barW - 6
      if x0 > term.getCursorPos() then
        term.setCursorPos(x0, y)
        term.setTextColor(C.gray)
        term.write("[" .. string.rep("#", fill) .. string.rep(" ", barW - fill) .. "]")
      end

      -- Cantidad a la derecha
      local amtS = tostring(amt)
      term.setTextColor(C.green)
      term.setCursorPos(L.w - #amtS, y)
      term.write(amtS)
    end
  end
end

local function rStatus()
  term.setBackgroundColor(C.bar)
  term.setTextColor(C.white)
  rClear(L.statusY)
  local s = " " .. state.status
  term.write(s)
  if #state.keys > 0 then
    local info = " Items: " .. #state.keys .. "  "
    term.setCursorPos(L.w - #info + 1, L.statusY)
    term.write(info)
  end
end

function GUI.render()
  term.setBackgroundColor(C.body)
  term.clear()
  layout()
  rHeader()
  rInput()
  rList()
  rStatus()
end

-- Rednet
local function cmd(cmdStr)
  if not state.server then
    state.status = "Error: Sin servidor"
    return nil
  end
  local uuid = math.random(1, 2 ^ 32)
  rednet.send(state.server, { cmdStr, uuid }, "stockpile")
  local id, msg = rednet.receive("stockpile", 5)
  if id == state.server and type(msg) == "table" and msg[2] == uuid then
    return msg[1]
  end
  return nil
end

local function findServer()
  state.status = "Buscando servidor..."
  local id = rednet.lookup("stockpile")
  if id then
    state.server = id
    state.status = "Servidor #" .. id
    return true
  end
  state.server = nil
  state.status = "No se encontro servidor"
  return false
end

-- Acciones
local function actDump()
  if not state.server and not findServer() then return end
  state.status = "Escaneando dump..."
  GUI.render()
  local r = cmd("scan(units.dump)")
  if r then
    state.status = "Moviendo al storage..."
    GUI.render()
    r = cmd("move_item(units.dump, units.storage)")
  end
  state.status = r and tostring(r) or "Error: timeout dump"
  actSearch(state.query)
end

local function actRetrieve()
  if not state.server and not findServer() then return end
  if not state.sel then
    state.status = "Selecciona un item primero"
    return
  end
  local id = state.keys[state.sel]
  if not id then return end
  state.status = "Trayendo " .. id:gsub("^minecraft:", "") .. " al dump..."
  GUI.render()
  local r = cmd('move_item(units.storage, units.dump, "' .. id:gsub('"', '\\"') .. '")')
  state.status = r and tostring(r) or "Error: timeout retrieve"
  actSearch(state.query)
end

local function actPush()
  if not state.server and not findServer() then return end
  state.status = "Push al dump..."
  GUI.render()
  local r = cmd("move_item(units.storage, units.dump)")
  state.status = r and tostring(r) or "Error: timeout"
  actSearch(state.query)
end

local function actRefresh()
  actSearch(state.query)
end

local function actUsage()
  if not state.server and not findServer() then return end
  local r = cmd("usage()")
  if type(r) == "table" then
    state.status = string.format("Uso: %d/%d slots (%d%%)",
      r.used_slots or 0, r.total_slots or 0,
      r.total_slots and r.total_slots > 0 and math.floor((r.used_slots or 0) / r.total_slots * 100) or 0)
  else
    state.status = r and tostring(r) or "Error: timeout"
  end
end

function actSearch(q)
  if not state.server and not findServer() then return end
  state.status = "Buscando..."
  GUI.render()
  local filter = (q and q ~= "") and q or "."
  local r = cmd('search("' .. filter:gsub('"', '\\"') .. '")')
  if type(r) == "table" then
    state.items = r
    state.keys = {}
    for k, _ in pairs(r) do table.insert(state.keys, k) end
    table.sort(state.keys)
    state.scroll = 0
    state.sel = nil
    state.status = #state.keys .. " items encontrados"
  elseif r then
    state.status = "Error: " .. tostring(r)
  else
    state.status = "Error: timeout busqueda"
  end
end

-- Input
local function handleClick(x, y)
  -- Botones
  for _, b in ipairs(btnList) do
    if b.x and y == b.y and x >= b.x and x < b.x + b.w then
      b.action()
      return true
    end
  end
  -- Lista
  if y >= L.listTop and y <= L.listBot then
    local idx = state.scroll + (y - L.listTop) + 1
    if idx <= #state.keys then
      state.sel = (state.sel == idx) and nil or idx
    end
    return true
  end
  -- Input
  if y == L.inputY then
    state.input = true
    return true
  end
  state.input = false
  return false
end

local function handleKey(code)
  if state.input then
    if code == keys.enter then
      state.input = false
      actSearch(state.query)
    elseif code == keys.tab or code == keys.escape then
      state.input = false
    elseif code == keys.backspace then
      state.query = string.sub(state.query, 1, -2)
    elseif code == keys.up then
      if #state.keys > 0 then
        state.sel = state.sel and math.max(1, state.sel - 1) or 1
        if state.sel <= state.scroll then state.scroll = math.max(0, state.sel - 1) end
      end
    elseif code == keys.down then
      if #state.keys > 0 then
        state.sel = state.sel and math.min(#state.keys, state.sel + 1) or 1
        local vis = L.listBot - L.listTop + 1
        if state.sel > state.scroll + vis then state.scroll = state.sel - vis end
      end
    elseif code == keys.pageUp then
      local vis = L.listBot - L.listTop + 1
      state.scroll = math.max(0, state.scroll - vis)
    elseif code == keys.pageDown then
      local vis = L.listBot - L.listTop + 1
      state.scroll = state.scroll + vis
    end
  else
    if code == keys.up then
      if #state.keys > 0 then
        state.sel = state.sel and math.max(1, state.sel - 1) or 1
        if state.sel <= state.scroll then state.scroll = math.max(0, state.sel - 1) end
      end
    elseif code == keys.down then
      if #state.keys > 0 then
        state.sel = state.sel and math.min(#state.keys, state.sel + 1) or 1
        local vis = L.listBot - L.listTop + 1
        if state.sel > state.scroll + vis then state.scroll = state.sel - vis end
      end
    elseif code == keys.pageUp then
      local vis = L.listBot - L.listTop + 1
      state.scroll = math.max(0, state.scroll - vis)
    elseif code == keys.pageDown then
      local vis = L.listBot - L.listTop + 1
      state.scroll = state.scroll + vis
    elseif code == keys.enter and state.sel then
      actRetrieve()
    elseif code == keys.tab then
      state.input = true
    end
  end
end

local function handleChar(ch)
  if state.input then
    state.query = state.query .. ch
  end
end

-- Inicializar
function GUI.start()
  layout()

  -- Registrar botones (orden inverso para dibujo)
  btn("Q", function() error("quit") end)
  btn("Usage", actUsage)
  btn("Push", actPush)
  btn("Refresh", actRefresh)
  btn("Retrieve", actRetrieve)
  btn("Dump", actDump)

  -- Conectar
  findServer()
  actSearch("")

  GUI.render()

  -- Loop principal
  local ok, err = pcall(function()
    while true do
      local ev = { os.pullEventRaw() }
      local t = ev[1]

      if t == "mouse_click" then
        handleClick(ev[3], ev[4])
        GUI.render()
      elseif t == "mouse_scroll" then
        if ev[2] > 0 then
          state.scroll = state.scroll + 1
        else
          state.scroll = math.max(0, state.scroll - 1)
        end
        GUI.render()
      elseif t == "key" then
        handleKey(ev[2])
        GUI.render()
      elseif t == "char" then
        handleChar(ev[2])
        GUI.render()
      elseif t == "term_resize" then
        GUI.render()
      end
    end
  end)

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  if err and err ~= "quit" then
    print("Error: " .. tostring(err))
  else
    print("Cliente cerrado.")
  end
end

-- Arranque
local modemOpen = false
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.hasType(side, "modem") then
    rednet.open(side)
    modemOpen = true
    break
  end
end

if not modemOpen then
  local ok2, err2 = pcall(function() rednet.open("right") end)
  if not ok2 then
    term.clear()
    term.setCursorPos(1, 1)
    print("Error: No se encontro modem")
    return
  end
end

GUI.start()
