-- Intelligent Ore Miner Script
-- Uses Depth-First Search (DFS) to mine complete veins of any ore
-- Automatically refuels using mined coal/charcoal
-- Automatically returns home when inventory is full or fuel is low

-- Checks if the block data matches our target (any ore or ancient debris)
local function isTarget(success, data)
    if success and data and data.name then
        local name = data.name
        -- Detect any block containing "_ore" or matching "ancient_debris"
        if name:find("_ore") or name == "minecraft:ancient_debris" then
            return true
        end
    end
    return false
end

-- Navigation stack for returning home
local returnStack = {}
local tracking = true

local function recordMove(move)
    if not tracking then return end
    local opposites = {
        ["forward"] = "back",
        ["back"] = "forward",
        ["up"] = "down",
        ["down"] = "up",
        ["turnLeft"] = "turnRight",
        ["turnRight"] = "turnLeft"
    }
    
    local returnAction = opposites[move]
    if #returnStack > 0 and returnStack[#returnStack] == move then
        table.remove(returnStack)
    else
        table.insert(returnStack, returnAction)
    end
end

-- Tries to refuel using coal or charcoal from inventory if fuel is low
local function checkFuel()
    if turtle.getFuelLevel() == "unlimited" then return true end
    
    if turtle.getFuelLevel() < 100 then
        -- Search inventory for coal/charcoal to refuel
        for i = 1, 16 do
            turtle.select(i)
            local item = turtle.getItemDetail()
            if item and (item.name == "minecraft:coal" or item.name == "minecraft:charcoal") then
                turtle.refuel(1)
                if turtle.getFuelLevel() >= 100 then
                    break
                end
            end
        end
        turtle.select(1) -- reset selection to slot 1
    end
    
    if turtle.getFuelLevel() < 10 then
        print("Warning: Critically low on fuel! Please add fuel.")
        return false
    end
    return true
end

-- Checks if all inventory slots are occupied
local function isInventoryFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end
    return true
end

-- Robust movement functions to handle falling sand/gravel
local function goForward()
    local attempts = 0
    while not turtle.forward() do
        if turtle.detect() then
            turtle.dig()
        else
            turtle.attack()
            attempts = attempts + 1
            if attempts > 50 then
                return false -- Blocked by bedrock or indestructible block
            end
            sleep(0.1)
        end
    end
    return true
end

local function goBack()
    local attempts = 0
    while not turtle.back() do
        turtle.attack()
        attempts = attempts + 1
        if attempts > 50 then
            return false
        end
        sleep(0.1)
    end
    return true
end

local function goUp()
    while not turtle.up() do
        if turtle.detectUp() then
            turtle.digUp()
        else
            return false
        end
    end
    return true
end

local function goDown()
    while not turtle.down() do
        if turtle.detectDown() then
            turtle.digDown()
        else
            return false
        end
    end
    return true
end

-- Movement wrappers that track movements on the stack
local function trackForward()
    if goForward() then
        recordMove("forward")
        return true
    end
    return false
end

local function trackBack()
    if goBack() then
        recordMove("back")
        return true
    end
    return false
end

local function trackUp()
    if goUp() then
        recordMove("up")
        return true
    end
    return false
end

local function trackDown()
    if goDown() then
        recordMove("down")
        return true
    end
    return false
end

local function trackTurnRight()
    turtle.turnRight()
    recordMove("turnRight")
end

local function trackTurnLeft()
    turtle.turnLeft()
    recordMove("turnLeft")
end

-- Check if we should abort mining and return home
local function shouldAbort()
    if isInventoryFull() then
        return true
    end
    if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < #returnStack + 15 then
        return true
    end
    return false
end

-- Returns home using the navigation stack
local function goHome()
    print("Returning home using path stack...")
    tracking = false
    while #returnStack > 0 do
        local action = table.remove(returnStack)
        if action == "forward" then
            goForward()
        elseif action == "back" then
            goBack()
        elseif action == "up" then
            goUp()
        elseif action == "down" then
            goDown()
        elseif action == "turnRight" then
            turtle.turnRight()
        elseif action == "turnLeft" then
            turtle.turnLeft()
        end
    end
    tracking = true
    print("Arrived home!")
end

-- Discharge items to chest behind and refuel using coal
local function dischargeAndRefuel()
    print("Discharging items and refueling...")
    local prevTracking = tracking
    tracking = false
    
    -- Turn to face the chest behind
    turtle.turnRight()
    turtle.turnRight()
    
    -- Refuel from inventory first to maximize fuel level
    for i = 1, 16 do
        turtle.select(i)
        local item = turtle.getItemDetail()
        if item and (item.name == "minecraft:coal" or item.name == "minecraft:charcoal") then
            turtle.refuel()
        end
    end
    
    -- Drop items to chest
    for i = 1, 16 do
        turtle.select(i)
        if turtle.getItemCount(i) > 0 then
            if not turtle.drop() then
                print("Warning: Chest might be full!")
            end
        end
    end
    
    turtle.select(1) -- Reset slot selection
    
    -- Turn back to face forward
    turtle.turnRight()
    turtle.turnRight()
    
    tracking = prevTracking
    print("Discharge and refuel complete.")
end

-- Returns to the mining site by replaying the saved path
local function resumeMining(savedPath)
    print("Returning to mining site...")
    tracking = true
    returnStack = {} -- Start with a clean stack
    
    local opposites = {
        ["forward"] = "back",
        ["back"] = "forward",
        ["up"] = "down",
        ["down"] = "up",
        ["turnLeft"] = "turnRight",
        ["turnRight"] = "turnLeft"
    }
    
    for i = 1, #savedPath do
        local action = savedPath[i]
        local move = opposites[action]
        if move == "forward" then
            trackForward()
        elseif move == "back" then
            trackBack()
        elseif move == "up" then
            trackUp()
        elseif move == "down" then
            trackDown()
        elseif move == "turnRight" then
            trackTurnRight()
        elseif move == "turnLeft" then
            trackTurnLeft()
        end
    end
    print("Arrived back at mining site!")
end

-- Returns to the main tunnel from a branch
local function returnToMainTunnel(mainTunnelPathLength)
    tracking = false
    while #returnStack > mainTunnelPathLength do
        local action = table.remove(returnStack)
        if action == "forward" then
            goForward()
        elseif action == "back" then
            goBack()
        elseif action == "up" then
            goUp()
        elseif action == "down" then
            goDown()
        elseif action == "turnRight" then
            turtle.turnRight()
        elseif action == "turnLeft" then
            turtle.turnLeft()
        end
    end
    tracking = true
end

-- DFS algorithm to mine veins
local function mineVein()
    if shouldAbort() then return end
    
    -- Check 4 horizontal directions by rotating
    for i = 1, 4 do
        if shouldAbort() then break end
        if isTarget(turtle.inspect()) then
            turtle.dig()
            if trackForward() then
                mineVein()
                if shouldAbort() then
                    break -- Aborted, don't backtrack manually
                else
                    trackBack()
                end
            end
        end
        if shouldAbort() then break end
        trackTurnRight()
    end
    
    -- Check Up
    if not shouldAbort() and isTarget(turtle.inspectUp()) then
        turtle.digUp()
        if trackUp() then
            mineVein()
            if shouldAbort() then
                -- Aborted, don't backtrack manually
            else
                trackDown()
            end
        end
    end
    
    -- Check Down
    if not shouldAbort() and isTarget(turtle.inspectDown()) then
        turtle.digDown()
        if trackDown() then
            mineVein()
            if shouldAbort() then
                -- Aborted, don't backtrack manually
            else
                trackUp()
            end
        end
    end
end

-- Main exploration loop (digs a 1x2 tunnel forward indefinitely)
local function explore()
    print("Starting Intelligent Ore Miner...")
    local distance = 0
    local mainTunnelPathLength = 0
    
    while true do
        if not checkFuel() then break end
        if isInventoryFull() then
            print("Inventory full! Going home.")
            break
        end
        
        -- Move forward (digging if necessary)
        if turtle.detect() then turtle.dig() end
        if trackForward() then
            distance = distance + 1
            mainTunnelPathLength = #returnStack
            
            -- Check ceiling block before blindly digging it to make a 2-high tunnel
            local ceilingTarget = false
            if not shouldAbort() then
                ceilingTarget = isTarget(turtle.inspectUp())
            end
            
            if ceilingTarget then
                turtle.digUp()
                if trackUp() then
                    mineVein()
                end
            elseif turtle.detectUp() then
                turtle.digUp()
            end
            
            -- After checking ceiling, check surroundings from main tunnel level
            mineVein()
            
            if shouldAbort() then
                while shouldAbort() do
                    -- Copy the return path
                    local savedPath = {}
                    for i = 1, #returnStack do
                        savedPath[i] = returnStack[i]
                    end
                    
                    goHome()
                    dischargeAndRefuel()
                    resumeMining(savedPath)
                    
                    -- Check if we are still low on fuel or if inventory is still full
                    if shouldAbort() then
                        print("Error: Still in abort state after discharge/refuel!")
                        break
                    end
                    
                    -- Continue mining the vein
                    mineVein()
                end
                returnToMainTunnel(mainTunnelPathLength)
            else
                returnToMainTunnel(mainTunnelPathLength)
            end
            
        else
            print("Blocked! Can't move forward (possibly bedrock or an entity).")
            break
        end
        
        if distance % 10 == 0 then
            print("Distance traveled: " .. distance .. " blocks.")
            print("Current Fuel: " .. turtle.getFuelLevel())
        end
    end
    
    goHome()
    dischargeAndRefuel()
    print("Finished mining.")
    print("Total distance explored: " .. distance)
end

-- Start the program
explore()
