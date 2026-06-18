-- scanner.lua
-- Escanea la red rednet en busca de turtles mineras y muestra su estado.
-- Usar desde una Pocket Computer (o cualquier ordenador con modem).
-- Funciona con Ender Modem (distancia ilimitada) o wireless normal.

local PROTOCOL = "turtle-status"
local SCAN_TIMEOUT = 3

-- ===================== MODEM =====================

local function findModem()
    if peripheral.getType("back") == "modem" or peripheral.hasType("back", "modem") then
        return "back"
    end
    for _, side in ipairs({"left", "right", "front", "top", "bottom"}) do
        if peripheral.getType(side) == "modem" or peripheral.hasType(side, "modem") then
            return side
        end
    end
    -- Pocket Computer: el modem integrado esta en "back"
    return nil
end

local function setupRednet()
    local side = findModem()
    if not side then
        print("ERROR: No hay modem conectado.")
        print("Las Pocket Computers tienen modem integrado en 'back'.")
        print("Las turtles necesitan un modem acoplado.")
        return false
    end
    rednet.open(side)
    return true
end

-- ===================== SCANEO =====================

local function scanTurtles()
    local all = {}
    local seen = {}

    for attempt = 1, 3 do
        if attempt > 1 then
            write(".")
            sleep(0.5)
        end
        local hosts = rednet.lookup(PROTOCOL)

        local function add(id, name)
            if not seen[id] then
                seen[id] = true
                table.insert(all, { id = id, name = name })
            end
        end

        if type(hosts) == "table" then
            for id, name in pairs(hosts) do
                add(id, name)
            end
        elseif type(hosts) == "number" then
            add(hosts, "miner")
        end
    end

    table.sort(all, function(a, b) return a.id < b.id end)
    return all
end

-- ===================== CONSULTA =====================

local function queryTurtle(id)
    rednet.send(id, "", PROTOCOL)
    local senderId, response, protocol = rednet.receive(PROTOCOL, 5)
    if senderId and response then
        return response
    end
    return nil
end

-- ===================== INTERFAZ =====================

local function showMenu(title, options)
    term.clear()
    term.setCursorPos(1, 1)
    print("=== " .. title .. " ===")
    print()
    for i, opt in ipairs(options) do
        print(("  %d. %s"):format(i, opt.label))
    end
    print()
    write("Selecciona (1-" .. #options .. "): ")
    local choice = tonumber(read())
    while not choice or choice < 1 or choice > #options do
        write("Invalido. Elige 1-" .. #options .. ": ")
        choice = tonumber(read())
    end
    return options[choice]
end

local function showTurtleStatus(id, name, response)
    term.clear()
    term.setCursorPos(1, 1)
    print("=== TURTLE #" .. id .. " (" .. (name or "?") .. ") ===")
    print("----------------------------------------")
    print(response)
    print("----------------------------------------")
    print()
    print("[R]efrescar  [Q]uit  Otra tecla = menu")
    local key = read():lower()
    if key == "r" then
        print()
        print("Consultando de nuevo...")
        local resp = queryTurtle(id)
        if resp then
            showTurtleStatus(id, name, resp)
        else
            print("ERROR: Sin respuesta. ¿Sigue encendida?")
            sleep(2)
        end
    end
end

-- ===================== MAIN =====================

local function main()
    if not setupRednet() then
        print()
        print("Pulsa Ctrl+T para salir.")
        return
    end
    print("Rednet iniciado.")

    while true do
        print("Escaneando red rednet...")
        local turtles = scanTurtles()
        print(" Hecho. Encontradas: " .. #turtles)

        if #turtles == 0 then
            term.clear()
            term.setCursorPos(1, 1)
            print("=== SCANNER REDNET ===")
            print()
            print("No se encontraron turtles con el protocolo '" .. PROTOCOL .. "'.")
            print()
            print("Asegurate de que:")
            print("  1. La turtle minera tiene un modem")
            print("  2. Esta ejecutando mine.lua (version con rednet)")
            print("  3. Ambas estan en la misma red (ender/wireless)")
            print()
            print("[R]eescanea  [S]alir")
            local key = read():lower()
            if key ~= "r" then break end
        else
            local options = {}
            for _, t in ipairs(turtles) do
                table.insert(options, {
                    label = ("[#%d] %s"):format(t.id, t.name),
                    value = t,
                })
            end
            table.insert(options, { label = "Reescanear", value = nil })

            local choice = showMenu("SCANNER REDNET - " .. #turtles .. " turtle(s)", options)
            if choice.value then
                local t = choice.value
                print()
                print("Consultando turtle #" .. t.id .. "...")
                local response = queryTurtle(t.id)
                if response then
                    showTurtleStatus(t.id, t.name, response)
                else
                    print("ERROR: No hubo respuesta (timeout 5s).")
                    print("Pulsa Enter para continuar.")
                    read()
                end
            else
                -- reescanear
            end
        end
    end
    print("Scanner cerrado.")
end

main()
