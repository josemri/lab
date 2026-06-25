--[[
  Stockpile GUI Client v1.1
  Cliente grafico para Stockpile (CC:Tweaked).
  Genera /stockpile_client.log con informacion de depuracion.
]]

-- Logger
local logFile = "stockpile_client.log"
local fh = fs.open(logFile, "w")
local function log(...)
  local parts = {...}
  local msg = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ")
  if fh then fh.writeLine(msg) fh.flush() end
end
log("=== Inicio ===")

local GUI = {}

local C = {
  header  = colors.blue,    body    = colors.black,  bar     = colors.gray,
  inputBg = colors.gray,    btn     = colors.cyan,   btnHov  = colors.lightBlue,
  selBg   = colors.blue,    title   = colors.white,  white   = colors.white,
  yellow  = colors.yellow,  green   = colors.green,  red     = colors.red,
  gray    = colors.lightGray,
}

local L = {}
local function layout()
  L.w, L.h = term.getSize()
  L.inputY = 3
  L.listTop = 5
  L.listBot = L.h - 1
  L.statusY = L.h
end

local state = {
  server = nil, items = {}, keys = {}, scroll = 0, sel = nil,
  status = "Iniciando...", query = "", input = false,
}

local btnList = {}
local function btn(label, action)
  table.insert(btnList, { label = label, action = action })
end

local function rClear(y)
  term.setCursorPos(1, y)
  term.clearLine()
end

local function rHeader()
  term.setBackgroundColor(C.header)
  rClear(1)
  term.setTextColor(C.title)
  term.write(" Stockpile ")
  local titleEnd = term.getCursorPos()
  local bx = L.w + 1
  for i = #btnList, 1, -1 do
    local b = btnList[i]
    local bw = #b.label + 3
    bx = bx - bw
    b.x = bx
    b.y = 1
    b.w = bw
  end
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
  if #txt < iw then term.write(string.rep(" ", iw - #txt)) end
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
  if n == 0 then
    for i = 1, vis do
      local y = L.listTop + i - 1
      term.setBackgroundColor(C.body)
      rClear(y)
      if i == math.ceil(vis / 2) then
        term.setTextColor(C.gray)
        local msg = " Sin items. Usa SCAN para escanear inventarios."
        if not state.server then msg = " Sin conexion al servidor."
        elseif state.status:find("Buscando") then msg = " Buscando servidor..."
        end
        term.write(msg)
      end
    end
    return
  end
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
      local barW = 8
      local fill = math.min(barW, math.ceil(amt / 64 * barW))
      local x0 = L.w - barW - 6
      if x0 > term.getCursorPos() then
        term.setCursorPos(x0, y)
        term.setTextColor(C.gray)
        term.write("[" .. string.rep("#", fill) .. string.rep(" ", barW - fill) .. "]")
      end
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
    log("cmd: sin servidor, comando ignorado:", cmdStr)
    return nil
  end
  local uuid = math.random(1, 2 ^ 32)
  log("cmd: >>", cmdStr, "uuid:", uuid)
  rednet.send(state.server, { cmdStr, uuid }, "stockpile")
  for i = 1, 5 do
    local id, msg = rednet.receive("stockpile", 2)
    if id and type(msg) == "table" then
      log("cmd: recv#" .. i .. " id:", id, "uuid:", tostring(msg[2]))
      if msg[2] == uuid then
        log("cmd: resultado:", tostring(msg[1]):sub(1, 200))
        if state.server == 0 or state.server ~= id then
          log("cmd: server ID actualizado a:", id)
          state.server = id
        end
        return msg[1]
      end
    end
  end
  log("cmd: FAIL - sin respuesta para:", cmdStr)
  return nil
end

local function findServer()
  state.status = "Buscando servidor..."
  log("findServer: lookup...")
  local id = rednet.lookup("stockpile")
  if id and id ~= 0 then
    state.server = id
    state.status = "Servidor #" .. id
    log("findServer: OK #" .. id)
    return true
  end
  -- Broadcast discovery: ping all computers on stockpile protocol
  log("findServer: broadcast discovery...")
  state.status = "Descubriendo servidor..."
  local uuid = math.random(1, 2 ^ 32)
  rednet.send(0, { "usage()", uuid }, "stockpile")
  for i = 1, 5 do
    local rid, msg = rednet.receive("stockpile", 2)
    if rid and type(msg) == "table" and msg[2] == uuid then
      state.server = rid
      state.status = "Servidor #" .. rid
      log("findServer: descubierto #" .. rid)
      return true
    end
  end
  state.server = nil
  state.status = "No se encontro servidor Stockpile. Verifica rednet."
  log("findServer: NO encontrado")
  return false
end

function actSearch(q)
  if not state.server and not findServer() then return end
  state.status = "Buscando..."
  GUI.render()
  local filter = (q and q ~= "") and q or "."
  log("actSearch: filter='" .. filter .. "'")
  local r = cmd('search("' .. filter:gsub('"', '\\"') .. '")')
  log("actSearch: resultado type=" .. type(r))
  if type(r) == "table" then
    state.items = r
    state.keys = {}
    for k, _ in pairs(r) do table.insert(state.keys, k) end
    table.sort(state.keys)
    state.scroll = 0
    state.sel = nil
    state.status = #state.keys .. " items encontrados"
    log("actSearch: " .. #state.keys .. " items")
  elseif r then
    state.status = "Error: " .. tostring(r)
    log("actSearch: error del servidor: " .. tostring(r))
  else
    state.status = "Error: timeout busqueda. Verifica conexion."
    log("actSearch: timeout")
  end
end

-- Acciones
local function actDump()
  if not state.server and not findServer() then return end
  log("actDump: iniciando")
  state.status = "Escaneando dump..."
  GUI.render()
  local r = cmd("scan(units.dump)")
  log("actDump: scan dump=" .. tostring(r))
  r = cmd("move_item(units.dump, units.storage)")
  log("actDump: move=" .. tostring(r))
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
  log("actRetrieve: " .. id)
  state.status = "Trayendo " .. id:gsub("^minecraft:", "") .. " al dump..."
  GUI.render()
  local r = cmd('move_item(units.storage, units.dump, "' .. id:gsub('"', '\\"') .. '")')
  log("actRetrieve: resultado=" .. tostring(r))
  state.status = r and tostring(r) or "Error: timeout retrieve"
  actSearch(state.query)
end

local function actPush()
  if not state.server and not findServer() then return end
  log("actPush: iniciando")
  state.status = "Push al dump..."
  GUI.render()
  local r = cmd("move_item(units.storage, units.dump)")
  log("actPush: resultado=" .. tostring(r))
  state.status = r and tostring(r) or "Error: timeout"
  actSearch(state.query)
end

local function actRefresh()
  actSearch(state.query)
end

local function actUsage()
  if not state.server and not findServer() then return end
  log("actUsage:")
  local r = cmd("usage()")
  log("actUsage: resultado=" .. tostring(r))
  if type(r) == "table" then
    local u = r.used_slots or 0
    local t = r.total_slots or 0
    local p = t > 0 and math.floor(u / t * 100) or 0
    state.status = string.format("Uso: %d/%d slots (%d%%)", u, t, p)
  else
    state.status = r and tostring(r) or "Error: timeout"
  end
end

local function actScanAll()
  if not state.server and not findServer() then return end
  log("actScanAll:")
  state.status = "Actualizando inventarios..."
  GUI.render()
  cmd("unit.get()")
  local units_reply = cmd("unit.get()")
  log("actScanAll: units=" .. textutils.serialize(units_reply):sub(1, 300))
  -- Auto-crear storage desde undefined si existe
  if type(units_reply) == "table" and type(units_reply.undefined) == "table" and #units_reply.undefined > 0 then
    local invs_str = textutils.serialize(units_reply.undefined)
    cmd('unit.set("storage",' .. invs_str .. ')')
    log("actScanAll: storage auto-creado desde undefined")
  end
  local all_scans_ok = true
  for _, name in ipairs({"storage", "dump", "undefined"}) do
    local r = cmd('scan(units.' .. name .. ')')
    log("actScanAll: scan " .. name .. "=" .. tostring(r))
    if not r or tostring(r):find("Error") then all_scans_ok = false end
  end
  state.status = all_scans_ok and "Scan completado" or "Algun scan fallo (revisa log)"
  actSearch(state.query)
end

local function actTest()
  if not state.server and not findServer() then return end
  log("actTest: === DIAGNOSTICO ===")
  state.status = "Diagnosticando..."
  GUI.render()
  local r1 = cmd("unit.get()")
  log("actTest: unit.get=" .. textutils.serialize(r1):sub(1, 500))
  local r2 = cmd("usage()")
  log("actTest: usage=" .. textutils.serialize(r2):sub(1, 200))
  local r3 = cmd('search(".")')
  log("actTest: search count=" .. (type(r3) == "table" and #r3 or tostring(r3)))
  state.status = "Diagnostico listo. Revisa " .. logFile
end

-- Input
local function handleClick(x, y)
  for _, b in ipairs(btnList) do
    if b.x and y == b.y and x >= b.x and x < b.x + b.w then
      log("click: boton '" .. b.label .. "'")
      b.action()
      return true
    end
  end
  if y >= L.listTop and y <= L.listBot then
    local idx = state.scroll + (y - L.listTop) + 1
    if idx <= #state.keys then
      state.sel = (state.sel == idx) and nil or idx
      log("click: seleccion item #" .. idx)
    end
    return true
  end
  if y == L.inputY then
    state.input = true
    log("click: activado input")
    return true
  end
  state.input = false
  return false
end

local function handleKey(code)
  if state.input then
    if code == keys.enter then
      state.input = false
      log("key: enter, buscando '" .. state.query .. "'")
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

local function actSetup()
  if not state.server and not findServer() then return end
  log("actSetup: === SETUP ===")
  state.status = "Configurando..."
  GUI.render()
  local units_tbl = cmd("unit.get()")
  log("actSetup: unit.get=" .. textutils.serialize(units_tbl):sub(1, 300))
  if type(units_tbl) ~= "table" then
    state.status = "Error: no se pudo obtener units"
    actSearch(state.query)
    return
  end
  -- Auto-crear storage desde undefined si hay
  local undef = units_tbl.undefined
  if type(undef) == "table" and #undef > 0 then
    local invs_str = textutils.serialize(undef)
    cmd('unit.set("storage",' .. invs_str .. ')')
    cmd('scan(units.storage)')
    state.status = "Storage creado con " .. #undef .. " inventarios. Configura dump manualmente."
  else
    local stor = units_tbl.storage
    if type(stor) == "table" and #stor > 0 then
      cmd('scan(units.storage)')
      state.status = #stor .. " inventarios en storage escaneados."
      local dump = units_tbl.dump
      if type(dump) ~= "table" or #dump == 0 then
        state.status = state.status .. " Falta configurar units.dump"
      end
    else
      state.status = "No hay inventarios detectados. Anadelos manualmente con Add."
    end
  end
  actSearch(state.query)
end

local function actAddChest()
  if not state.server and not findServer() then return end
  local name = state.query
  if not name or name == "" then
    state.status = "Escribe nombre del cofre (ej: minecraft:chest_59) y pulsa Add"
    return
  end
  log("actAddChest: " .. name)
  state.status = "Anadiendo " .. name .. "..."
  GUI.render()
  cmd('unit.add("storage",{"' .. name:gsub('"', '\\"') .. '"})')
  cmd("scan(units.storage)")
  state.status = "Anadido " .. name .. " y escaneado"
  actSearch(state.query)
end

function GUI.start()
  layout()
  log("layout: " .. L.w .. "x" .. L.h)

  btn("Q", function() error("quit") end)
  btn("Add", actAddChest)
  btn("Test", actTest)
  btn("Setup", actSetup)
  btn("Usage", actUsage)
  btn("Scan", actScanAll)
  btn("Push", actPush)
  btn("Refresh", actRefresh)
  btn("Retrieve", actRetrieve)
  btn("Dump", actDump)

  log("buscando servidor...")
  findServer()
  log("servidor encontrado: " .. tostring(state.server))
  actSearch("")

  GUI.render()

  local ok, err = pcall(function()
    while true do
      local ev = { os.pullEventRaw() }
      local t = ev[1]
      if t == "mouse_click" then
        handleClick(ev[3], ev[4])
        GUI.render()
      elseif t == "mouse_scroll" then
        if ev[2] > 0 then state.scroll = state.scroll + 1
        else state.scroll = math.max(0, state.scroll - 1) end
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

  if fh then fh.close() end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  if err and err ~= "quit" then
    log("Error fatal: " .. tostring(err))
    print("Error: " .. tostring(err))
    print("Log: " .. logFile)
  else
    log("=== Salida normal ===")
    print("Cliente cerrado. Log: " .. logFile)
  end
end

-- Arranque
local modemOpen = false
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.hasType(side, "modem") then
    rednet.open(side)
    modemOpen = true
    log("modem abierto en: " .. side)
    break
  end
end
if not modemOpen then
  local ok2, err2 = pcall(function() rednet.open("right") end)
  if ok2 then
    log("modem abierto en: right (fallback)")
    modemOpen = true
  else
    log("ERROR: no se pudo abrir modem en ningun lado")
    term.clear()
    term.setCursorPos(1, 1)
    print("Error: No se encontro modem")
    print("Conecta un modem y reinicia.")
    if fh then fh.close() end
    return
  end
end

GUI.start()
