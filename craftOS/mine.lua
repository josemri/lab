-- Intelligent Ore Miner v2
-- CC:Tweaked turtle con seleccion de mineral, navegacion automatica a capa optima,
-- retorno exacto al inicio, y consulta remota via rednet.

-- ===================== CONFIGURACION =====================

local ORE_OPTIONS = {
    { name = "Diamond Ore",       id = "diamond_ore",     y = -59 },
    { name = "Iron Ore",          id = "iron_ore",        y = 15 },
    { name = "Gold Ore",          id = "gold_ore",        y = -16 },
    { name = "Redstone Ore",      id = "redstone_ore",    y = -59 },
    { name = "Lapis Lazuli Ore",  id = "lapis_ore",       y = 0 },
    { name = "Copper Ore",        id = "copper_ore",      y = 48 },
    { name = "Coal Ore",          id = "coal_ore",        y = 96 },
    { name = "Emerald Ore",       id = "emerald_ore",     y = 236 },
    { name = "Ancient Debris",    id = "ancient_debris",  y = 15 },
    { name = "Cualquier Mineral", id = nil,               y = nil },
}

local MIN_STARTING_FUEL = 200
local RETRY_LIMIT = 3
local VEIN_MAX_DEPTH = 100
local FUEL_BUFFER = 25
local MAX_ATTEMPT_BLOCKED = 8

-- Rednet
local REDNET_PROTOCOL = "turtle-status"

-- ===================== ESTADO =====================

local returnStack = {}
local tracking = true
local targetOre = nil
local targetY = nil
local retryCount = 0

local pos = { x = 0, y = 0, z = 0 }
local facing = 0
local distance = 0

-- ===================== MENU =====================

local function showMenu()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== MINERO INTELIGENTE v2 ===")
    print("Selecciona el mineral a minar:")
    print()
    for i, opt in ipairs(ORE_OPTIONS) do
        local layer = opt.y and ("Y=" .. opt.y) or "Actual"
        print(("  %d. %s  (%s)"):format(i, opt.name, layer))
    end
    print()
    write("Opcion (1-" .. #ORE_OPTIONS .. "): ")

    local choice = tonumber(read())
    while not choice or choice < 1 or choice > #ORE_OPTIONS do
        write("Invalido. Elige 1-" .. #ORE_OPTIONS .. ": ")
        choice = tonumber(read())
    end
    return ORE_OPTIONS[choice]
end

-- ===================== DETECCION DE OBJETIVO =====================

local function isTarget(success, data)
    if not success or not data or not data.name then return false end
    local name = data.name
    if targetOre.id == nil then
        return name:find("_ore") or name == "minecraft:ancient_debris"
    end
    local normal = "minecraft:" .. targetOre.id
    local deepslate = "minecraft:deepslate_" .. targetOre.id
    return name == normal or name == deepslate
end

-- ===================== NAVEGACION =====================

local OPPOSITES = {
    forward = "back", back = "forward",
    up = "down", down = "up",
    turnLeft = "turnRight", turnRight = "turnLeft",
}

local function recordMove(move)
    if not tracking then return end
    if #returnStack > 0 and returnStack[#returnStack] == move then
        table.remove(returnStack)
    else
        table.insert(returnStack, OPPOSITES[move])
    end
end

local function updatePosition(move)
    if move == "forward" then
        if facing == 0 then pos.z = pos.z + 1
        elseif facing == 1 then pos.x = pos.x + 1
        elseif facing == 2 then pos.z = pos.z - 1
        else pos.x = pos.x - 1 end
    elseif move == "back" then
        if facing == 0 then pos.z = pos.z - 1
        elseif facing == 1 then pos.x = pos.x - 1
        elseif facing == 2 then pos.z = pos.z + 1
        else pos.x = pos.x + 1 end
    elseif move == "up" then pos.y = pos.y + 1
    elseif move == "down" then pos.y = pos.y - 1
    elseif move == "turnRight" then facing = (facing + 1) % 4
    elseif move == "turnLeft" then facing = (facing + 3) % 4
    end
end

-- ===================== MOVIMIENTO =====================

local function goForward()
    local attempts = 0
    while not turtle.forward() do
        if turtle.detect() then
            if not turtle.dig() then
                attempts = attempts + 1
                if attempts > MAX_ATTEMPT_BLOCKED then return false end
            end
        elseif not turtle.attack() then
            attempts = attempts + 1
            if attempts > MAX_ATTEMPT_BLOCKED then return false end
        end
        os.sleep(0.05)
    end
    return true
end

local function goBack()
    local attempts = 0
    while not turtle.back() do
        if not turtle.attack() then
            attempts = attempts + 1
            if attempts > MAX_ATTEMPT_BLOCKED then return false end
        end
        os.sleep(0.05)
    end
    return true
end

local function goUp()
    while not turtle.up() do
        if turtle.detectUp() then
            if not turtle.digUp() then return false end
        else return false end
        os.sleep(0.05)
    end
    return true
end

local function goDown()
    while not turtle.down() do
        if turtle.detectDown() then
            if not turtle.digDown() then return false end
        else return false end
        os.sleep(0.05)
    end
    return true
end

local function trackForward()
    if goForward() then
        recordMove("forward"); updatePosition("forward")
        return true
    end
    return false
end

local function trackBack()
    if goBack() then
        recordMove("back"); updatePosition("back")
        return true
    end
    return false
end

local function trackUp()
    if goUp() then
        recordMove("up"); updatePosition("up")
        return true
    end
    return false
end

local function trackDown()
    if goDown() then
        recordMove("down"); updatePosition("down")
        return true
    end
    return false
end

local function trackTurnRight()
    turtle.turnRight(); recordMove("turnRight"); updatePosition("turnRight")
end

local function trackTurnLeft()
    turtle.turnLeft(); recordMove("turnLeft"); updatePosition("turnLeft")
end

-- ===================== COMBUSTIBLE =====================

local function isUnlimitedFuel()
    return turtle.getFuelLevel() == "unlimited"
end

local function checkFuel()
    if isUnlimitedFuel() then return true end
    if turtle.getFuelLevel() < 100 then
        for i = 1, 16 do
            turtle.select(i)
            local item = turtle.getItemDetail()
            if item and (item.name == "minecraft:coal" or item.name == "minecraft:charcoal") then
                turtle.refuel(1)
                if turtle.getFuelLevel() >= 100 then break end
            end
        end
        turtle.select(1)
    end
    if turtle.getFuelLevel() < 10 then
        print("AVISO: Combustible critico!")
        return false
    end
    return true
end

local function fuelToReturn()
    if isUnlimitedFuel() then return 0 end
    return #returnStack + FUEL_BUFFER
end

local function hasFuelToMine()
    if isUnlimitedFuel() then return true end
    return turtle.getFuelLevel() >= fuelToReturn() + 5
end

-- ===================== INVENTARIO =====================

local function isInventoryFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then return false end
    end
    return true
end

local function shouldAbort()
    if isInventoryFull() then return "inventory_full" end
    if not hasFuelToMine() then return "fuel_low" end
    return false
end

-- ===================== NAVEGACION DE RETORNO =====================

local function goHome()
    print("Volviendo al punto de inicio...")
    tracking = false
    while #returnStack > 0 do
        local action = table.remove(returnStack)
        if action == "forward" then goForward()
        elseif action == "back" then goBack()
        elseif action == "up" then goUp()
        elseif action == "down" then goDown()
        elseif action == "turnRight" then turtle.turnRight()
        elseif action == "turnLeft" then turtle.turnLeft()
        end
        updatePosition(action)
    end
    tracking = true
    print("Llegada al inicio!")
end

local function copyStack(stk)
    local c = {}
    for i = 1, #stk do c[i] = stk[i] end
    return c
end

local function dischargeAndRefuel()
    print("Descargando inventario y repostando...")
    local prevTracking = tracking
    tracking = false
    turtle.turnRight(); updatePosition("turnRight")
    turtle.turnRight(); updatePosition("turnRight")
    for i = 1, 16 do
        turtle.select(i)
        local item = turtle.getItemDetail()
        if item and (item.name == "minecraft:coal" or item.name == "minecraft:charcoal") then
            turtle.refuel()
        end
    end
    for i = 1, 16 do
        turtle.select(i)
        if turtle.getItemCount(i) > 0 then
            if not turtle.drop() then print("AVISO: El cofre podria estar lleno!") end
        end
    end
    turtle.select(1)
    turtle.turnRight(); updatePosition("turnRight")
    turtle.turnRight(); updatePosition("turnRight")
    tracking = prevTracking
    print("Descarga completada.")
end

local function resumeMining(savedPath)
    if not savedPath or #savedPath == 0 then return end
    print("Volviendo al frente de mineria...")
    tracking = true
    returnStack = {}
    for i = 1, #savedPath do
        local move = OPPOSITES[savedPath[i]]
        if move == "forward" then trackForward()
        elseif move == "back" then trackBack()
        elseif move == "up" then trackUp()
        elseif move == "down" then trackDown()
        elseif move == "turnRight" then trackTurnRight()
        elseif move == "turnLeft" then trackTurnLeft()
        end
    end
    print("De vuelta en el frente!")
end

local function returnToMainTunnel(savedLength)
    tracking = false
    while #returnStack > savedLength do
        local action = table.remove(returnStack)
        if action == "forward" then goForward()
        elseif action == "back" then goBack()
        elseif action == "up" then goUp()
        elseif action == "down" then goDown()
        elseif action == "turnRight" then turtle.turnRight()
        elseif action == "turnLeft" then turtle.turnLeft()
        end
        updatePosition(action)
    end
    tracking = true
end

-- ===================== MINADO DE VENAS (DFS) =====================

local function mineVein(depth)
    depth = depth or 0
    if depth > VEIN_MAX_DEPTH then return end
    local reason = shouldAbort()
    if reason then return end

    for i = 1, 4 do
        reason = shouldAbort()
        if reason then break end
        if isTarget(turtle.inspect()) then
            turtle.dig()
            if trackForward() then
                mineVein(depth + 1)
                reason = shouldAbort()
                if not reason then trackBack() end
            end
        end
        reason = shouldAbort()
        if reason then break end
        trackTurnRight()
    end

    reason = shouldAbort()
    if not reason and isTarget(turtle.inspectUp()) then
        turtle.digUp()
        if trackUp() then
            mineVein(depth + 1)
            reason = shouldAbort()
            if not reason then trackDown() end
        end
    end

    reason = shouldAbort()
    if not reason and isTarget(turtle.inspectDown()) then
        turtle.digDown()
        if trackDown() then
            mineVein(depth + 1)
            reason = shouldAbort()
            if not reason then trackUp() end
        end
    end
end

-- ===================== NAVEGACION A CAPA Y =====================

local function getCurrentY()
    write("Altitud Y actual de la turtle (0 si no sabes): ")
    local input = read()
    local yPos = tonumber(input)
    if yPos then return yPos end
    return nil
end

local function navigateToTargetY()
    if targetY == nil then
        print("Minando en la altitud actual.")
        return true
    end
    local currentY = getCurrentY()
    if currentY == nil then
        print("Altitud desconocida. Minando en la posicion actual.")
        return true
    end
    local delta = targetY - currentY
    if delta == 0 then
        print("Ya estas en la capa Y=" .. targetY .. ". Minando aqui.")
        return true
    end
    local direction = delta > 0 and "subir" or "bajar"
    local blocks = math.abs(delta)
    print("Necesitas " .. direction .. " " .. blocks .. " bloques hasta Y=" .. targetY .. ".")

    if not isUnlimitedFuel() and turtle.getFuelLevel() < blocks + fuelToReturn() then
        print("ERROR: Combustible insuficiente para alcanzar la capa objetivo y volver.")
        print("Necesitas al menos " .. (blocks + fuelToReturn()) .. " de combustible.")
        return false
    end

    if delta > 0 then
        for i = 1, blocks do
            if not isUnlimitedFuel() and turtle.getFuelLevel() < #returnStack + 5 then
                print("AVISO: Combustible agotado durante ascenso.")
                return false
            end
            if turtle.detectUp() then turtle.digUp() end
            if not trackUp() then print("ERROR: Bloqueado al subir."); return false end
            if i % 20 == 0 then print("Subiendo... Y actual: ~" .. (currentY + i)); os.sleep(0) end
        end
    else
        for i = 1, blocks do
            if not isUnlimitedFuel() and turtle.getFuelLevel() < #returnStack + 5 then
                print("AVISO: Combustible agotado durante descenso.")
                return false
            end
            if turtle.detectDown() then turtle.digDown() end
            if not trackDown() then print("ERROR: Bloqueado al bajar."); return false end
            if i % 20 == 0 then print("Bajando... Y actual: ~" .. (currentY - i)); os.sleep(0) end
        end
    end
    print("Llegaste a Y=" .. targetY .. "!")
    return true
end

-- ===================== CONSULTA REMOTA (REDNET) =====================

local function buildStatusText()
    local lines = {}
    table.insert(lines, "=== MINERO INTELIGENTE v2 ===")
    table.insert(lines, "Objetivo: " .. (targetOre and targetOre.name or "N/A"))
    table.insert(lines, string.format("Posicion: X=%d Y=%d Z=%d  Orientacion: %s",
        pos.x, pos.y, pos.z, ({ "+Z", "+X", "-Z", "-X" })[facing + 1] or "?"))
    table.insert(lines, "Combustible: " .. tostring(turtle.getFuelLevel()))
    table.insert(lines, "Distancia: " .. tostring(distance))
    table.insert(lines, "")
    local count = 0
    for i = 1, 16 do
        local detail = turtle.getItemDetail(i)
        if detail then
            local name = detail.name:gsub("minecraft:", "")
            table.insert(lines, string.format("  [%02d] %s x%d", i, name, detail.count))
            count = count + detail.count
        end
    end
    if count == 0 then
        table.insert(lines, "  (inventario vacio)")
    else
        table.insert(lines, "  Total: " .. count .. " items")
    end
    return table.concat(lines, "\n")
end

local function setupModem()
    for _, side in ipairs({"left", "right", "back", "front", "top", "bottom"}) do
        if peripheral.getType(side) == "modem" or peripheral.hasType(side, "modem") then
            rednet.open(side)
            return true
        end
    end
    return false
end

-- ===================== LISTENER REDNET =====================

local function rednetListener()
    while true do
        local senderId, message, protocol = rednet.receive(REDNET_PROTOCOL)
        if senderId and protocol == REDNET_PROTOCOL then
            rednet.send(senderId, buildStatusText(), REDNET_PROTOCOL)
        end
    end
end

-- ===================== MINADO =====================

local function doMining()
    local mainTunnelPathLength = 0

    while true do
        if not checkFuel() then print("Combustible agotado. Volviendo a casa."); break end

        local reason = shouldAbort()
        if reason then
            if reason == "fuel_low" then
                print("Combustible insuficiente para continuar minando.")
                break
            elseif reason == "inventory_full" and retryCount < RETRY_LIMIT then
                print("Inventario lleno! Gestionando descarga...")
                local savedPath = copyStack(returnStack)
                goHome()
                dischargeAndRefuel()
                retryCount = retryCount + 1
                reason = shouldAbort()
                if reason then
                    print("No se puede continuar tras descarga. Finalizando.")
                    if reason == "inventory_full" then print("El cofre destino podria estar lleno.") end
                    break
                end
                resumeMining(savedPath)
                mainTunnelPathLength = #returnStack
            else break end
        else
            retryCount = 0
            if turtle.detect() then turtle.dig() end
            if not trackForward() then
                print("Bloqueado! (posiblemente bedrock o entidad)")
                break
            end
            distance = distance + 1
            mainTunnelPathLength = #returnStack

            local ceilingTarget = false
            reason = shouldAbort()
            if not reason then ceilingTarget = isTarget(turtle.inspectUp()) end
            if ceilingTarget then
                turtle.digUp()
                if trackUp() then
                    mineVein()
                    reason = shouldAbort()
                    if not reason then trackDown() end
                end
            elseif turtle.detectUp() then turtle.digUp() end

            mineVein()
            returnToMainTunnel(mainTunnelPathLength)

            if distance % 10 == 0 then
                print("Distancia: " .. distance .. " | Combustible: " .. turtle.getFuelLevel() ..
                    " | Pos: " .. pos.x .. "," .. pos.y .. "," .. pos.z)
            end
        end
    end

    goHome()
    print("Mision completada.")
    print("Distancia total explorada: " .. distance)
    print("Combustible restante: " .. tostring(turtle.getFuelLevel()))
end

-- ===================== INICIO =====================

local function explore()
    print("Iniciando Minero Inteligente v2...")
    print("Objetivo: " .. targetOre.name)

    -- Consumir todo el carbon del inventario antes de empezar
    if not isUnlimitedFuel() then
        print("Repostando con carbon/charcoal del inventario...")
        for i = 1, 16 do
            turtle.select(i)
            local item = turtle.getItemDetail()
            if item and (item.name == "minecraft:coal" or item.name == "minecraft:charcoal") then
                turtle.refuel()
            end
        end
        turtle.select(1)
        local fuel = turtle.getFuelLevel()
        if fuel < MIN_STARTING_FUEL then
            print("ERROR: Combustible insuficiente para empezar.")
            print("Tienes: " .. fuel .. " | Necesitas minimo: " .. MIN_STARTING_FUEL)
            print("Ponle carbon/charcoal a la turtle y vuelve a ejecutar.")
            return
        end
        print("Combustible actual: " .. fuel)
    end

    local hasModem = setupModem()
    if hasModem then
        print("Modem detectado. Consulta remota activa.")
        rednet.host(REDNET_PROTOCOL, "miner-" .. os.getComputerID())
    end

    if not navigateToTargetY() then
        print("Mision abortada durante navegacion a capa objetivo.")
        goHome()
        return
    end

    distance = 0

    if hasModem then
        parallel.waitForAny(doMining, rednetListener)
    else
        doMining()
    end
end

-- ===================== INICIO =====================

local ok, err = pcall(function()
    targetOre = showMenu()
    targetY = targetOre.y
    explore()
end)

if not ok then
    print("ERROR INESPERADO:")
    print(err)
    print("Volviendo a casa por seguridad...")
    tracking = false
    while #returnStack > 0 do
        local action = table.remove(returnStack)
        if action == "forward" then goForward()
        elseif action == "back" then goBack()
        elseif action == "up" then goUp()
        elseif action == "down" then goDown()
        elseif action == "turnRight" then turtle.turnRight()
        elseif action == "turnLeft" then turtle.turnLeft()
        end
    end
end