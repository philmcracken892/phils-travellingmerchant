local RSGCore = exports['rsg-core']:GetCoreObject()

-- ========================================
-- STATE
-- ========================================
local State = {
    wagon = nil,
    driver = nil,
    blip = nil,
    currentStop = 1,
    isMoving = false,
    targetAdded = false,
    isUIOpen = false,
    hasControl = false
}

-- ========================================
-- HELPERS
-- ========================================

local function DebugPrint(msg)
    
end

local function LoadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    return HasModelLoaded(hash) and hash or nil
end

local function isNight()
    local h = GetClockHours() or 12
    local s = Config.NightStart or 20
    local e = Config.NightEnd or 6
    if s <= e then return h >= s and h < e else return h >= s or h < e end
end

local function GetStopByIndex(index)
    local stop = Config.Route[index]
    if not stop then return nil, nil end
    return stop.coords or stop, stop.label or ('Stop #' .. index)
end

-- ========================================
-- BLIP
-- ========================================

local function CreateWagonBlip()
    if not State.wagon or not DoesEntityExist(State.wagon) then return end
    if State.blip and DoesBlipExist(State.blip) then return end
    
    local blip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, 0x318C617C, State.wagon)
    if blip and blip ~= 0 then
        SetBlipSprite(blip, GetHashKey(Config.BlipSprite), true)
        SetBlipScale(blip, Config.BlipScale)
        if Config.BlipColor then
            Citizen.InvokeNative(0x662D364ABF16DE2F, blip, GetHashKey(Config.BlipColor))
        end
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, 'Traveling Merchant')
        State.blip = blip
    end
end

local function RemoveWagonBlip()
    if State.blip and DoesBlipExist(State.blip) then
        RemoveBlip(State.blip)
    end
    State.blip = nil
end

-- ========================================
-- NUI SHOP
-- ========================================

local function OpenShop()
    if State.isUIOpen then return end
    State.isUIOpen = true
    
    SetNuiFocus(true, true)
    
    local Player = RSGCore.Functions.GetPlayerData()
    local money = 0
    if Player and Player.money then
        money = Player.money[Config.MoneyAccount] or 0
    end
    
    SendNUIMessage({
        action = 'openShop',
        items = Config.Items,
        herbs = Config.Herbs,
        weapons = Config.Weapons,
        alcohol = Config.Alcohol,
        isNight = isNight(),
        money = money
    })
end

local function CloseShop()
    if not State.isUIOpen then return end
    State.isUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeShop' })
end

RegisterNUICallback('closeUI', function(data, cb)
    CloseShop()
    cb('ok')
end)

RegisterNUICallback('purchase', function(data, cb)
    local item = data.item
    local qty = data.quantity or 1
    local isWeapon = data.isWeapon
    local hour = GetClockHours()
    
    local callbackName = isWeapon and 'merchant:buyWeapon' or 'merchant:buyItem'
    local success, msg = lib.callback.await(callbackName, false, item, qty, hour)
    
    SendNUIMessage({
        action = 'purchaseResult',
        success = success,
        message = msg or (success and 'Purchase successful' or 'Purchase failed')
    })
    
    Wait(100)
    local Player = RSGCore.Functions.GetPlayerData()
    local money = 0
    if Player and Player.money then
        money = Player.money[Config.MoneyAccount] or 0
    end
    SendNUIMessage({ action = 'updateMoney', money = money })
    
    cb('ok')
end)

-- ========================================
-- TARGET
-- ========================================

local function AddWagonTarget()
    if State.targetAdded then return end
    if not State.wagon or not DoesEntityExist(State.wagon) then return end

    exports.ox_target:addLocalEntity(State.wagon, {
        {
            name = 'merchant_shop',
            icon = 'fa-solid fa-cart-shopping',
            label = 'Browse Wares',
            distance = 3.5,
            onSelect = function()
                OpenShop()
            end
        }
    })
    
    State.targetAdded = true
   
end

-- ========================================
-- DRIVER & VEHICLE SETUP
-- ========================================

local function ConfigureDriver(driver)
    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedFleeAttributes(driver, 0, false)
    SetPedCombatAttributes(driver, 46, true)
    SetEntityInvincible(driver, true)
    SetPedKeepTask(driver, true)
    
  
    Citizen.InvokeNative(0x283978A15512B2FE, driver, true) -- SetRandomOutfitVariation
    Citizen.InvokeNative(0xB8B6430EAD2D2437, driver, GetHashKey("COACH_DRIVER")) -- SetPedConfigFlag for scenario
    
   
    Citizen.InvokeNative(0x9F8AA94D6D97DBF4, driver, true) -- SetPedCanBeDraggedOut false
    
   
end

local function ConfigureWagon(wagon)
    SetEntityAsMissionEntity(wagon, true, true)
    SetVehicleDoorsLocked(wagon, 2)
    SetVehicleDoorsLockedForAllPlayers(wagon, true)
    
   
    Citizen.InvokeNative(0x7263332501E07F52, wagon, true)
    
   
    for i = -1, 3 do
        Citizen.InvokeNative(0x7C65DAC73C35C862, wagon, i, false)
    end
    
    DebugPrint('Wagon configured')
end

local function PutDriverInWagon(driver, wagon)
    SetPedIntoVehicle(driver, wagon, -1)
    Wait(500)
    
    if not IsPedInVehicle(driver, wagon, false) then
        DebugPrint('Driver not in wagon, trying TaskEnterVehicle')
        TaskEnterVehicle(driver, wagon, -1, -1, 2.0, 1, 0)
        local timeout = 0
        while not IsPedInVehicle(driver, wagon, false) and timeout < 30 do
            Wait(100)
            timeout = timeout + 1
        end
    end
    
    local inVehicle = IsPedInVehicle(driver, wagon, false)
   
    return inVehicle
end

-- ========================================
-- NETWORK CONTROL
-- ========================================

local function RequestControl()
    if not State.driver or not DoesEntityExist(State.driver) then 
       
        return false 
    end
    if not State.wagon or not DoesEntityExist(State.wagon) then 
        
        return false 
    end
    
    local timeout = 0
    local maxTimeout = 30
    
    while timeout < maxTimeout do
        local hasDriverControl = NetworkHasControlOfEntity(State.driver)
        local hasWagonControl = NetworkHasControlOfEntity(State.wagon)
        
        if hasDriverControl and hasWagonControl then
            State.hasControl = true
            DebugPrint('Got control of both entities')
            return true
        end
        
        if not hasDriverControl then
            NetworkRequestControlOfEntity(State.driver)
        end
        if not hasWagonControl then
            NetworkRequestControlOfEntity(State.wagon)
        end
        
        Wait(100)
        timeout = timeout + 1
    end
    
    DebugPrint('FAILED to get control after ' .. maxTimeout .. ' attempts')
    State.hasControl = false
    return false
end

-- ========================================
-- DRIVING - REDM SPECIFIC
-- ========================================

local function DriveToStop(stopIndex)
    local coords, label = GetStopByIndex(stopIndex)
    if not coords then
        
        return false
    end
    
    
    
    if not State.driver or not DoesEntityExist(State.driver) then 
        
        return false 
    end
    if not State.wagon or not DoesEntityExist(State.wagon) then 
       
        return false 
    end
    
    -- Check if driver is in wagon
    if not IsPedInVehicle(State.driver, State.wagon, false) then
       
        PutDriverInWagon(State.driver, State.wagon)
        Wait(500)
        if not IsPedInVehicle(State.driver, State.wagon, false) then
            
            return false
        end
    end
    
   
    if not RequestControl() then
      
        return false
    end
    
    -- Clear existing tasks
    ClearPedTasks(State.driver)
    Wait(200)
    
    local speed = Config.Speed or 6.0
    
    DebugPrint('Issuing drive task - Speed: ' .. speed)
    
   
    TaskGoToCoordAnyMeans(
        State.driver,
        coords.x,
        coords.y,
        coords.z,
        speed,
        0,
        false,
        786603,
        -1.0
    )
    
    State.isMoving = true
    State.currentStop = stopIndex
    
    DebugPrint('Drive task issued successfully (TaskGoToCoordAnyMeans)')
    return true
end


local function DriveToStopMethod2(stopIndex)
    local coords, label = GetStopByIndex(stopIndex)
    if not coords then return false end
    
   
    
    if not RequestControl() then return false end
    
    ClearPedTasks(State.driver)
    Wait(200)
    
    local speed = Config.Speed or 6.0
    
   
    Citizen.InvokeNative(0xE2A2AA2F659D77A7, State.driver, State.wagon, coords.x, coords.y, coords.z, speed, 786603, 5.0)
    
    State.isMoving = true
    State.currentStop = stopIndex
    return true
end

local function DriveToStopMethod3(stopIndex)
    local coords, label = GetStopByIndex(stopIndex)
    if not coords then return false end
    
   
    
    if not RequestControl() then return false end
    
    ClearPedTasks(State.driver)
    Wait(200)
    
    local speed = Config.Speed or 6.0
    
    -- Method 3: Direct native call with hash
    Citizen.InvokeNative(0xE44B47A4D4E1D6BB, 
        State.driver, 
        State.wagon, 
        coords.x, 
        coords.y, 
        coords.z, 
        speed,
        0,
        GetHashKey(Config.WagonModel),
        786603,
        5.0,
        -1.0,
        true
    )
    
    State.isMoving = true
    State.currentStop = stopIndex
    return true
end

local function DriveToStopMethod4(stopIndex)
    local coords, label = GetStopByIndex(stopIndex)
    if not coords then return false end
    
   
    
    if not RequestControl() then return false end
    
    ClearPedTasks(State.driver)
    Wait(200)
    
    local speed = Config.Speed or 6.0
    
    
    local seq = OpenSequenceTask()
    TaskGoToCoordAnyMeans(0, coords.x, coords.y, coords.z, speed, 0, false, 786603, -1.0)
    CloseSequenceTask(seq)
    TaskPerformSequence(State.driver, seq)
    ClearSequenceTask(seq)
    
    State.isMoving = true
    State.currentStop = stopIndex
    return true
end

local function StopWagon()
    if not State.driver or not DoesEntityExist(State.driver) then return end
    if not State.wagon or not DoesEntityExist(State.wagon) then return end
    
    
    
    if NetworkHasControlOfEntity(State.driver) then
        ClearPedTasks(State.driver)
        TaskVehicleTempAction(State.driver, State.wagon, 1, 1000)
    end
    
    State.isMoving = false
end

-- ========================================
-- SPAWN MERCHANT
-- ========================================

local function SpawnMerchant()
    if State.wagon and DoesEntityExist(State.wagon) then
       
        return true
    end
    
    local coords, label = GetStopByIndex(1)
    if not coords then
       
        return false
    end
    
    DebugPrint('Spawning at ' .. label .. ' (' .. coords.x .. ', ' .. coords.y .. ', ' .. coords.z .. ')')
    
    local wagonHash = LoadModel(Config.WagonModel)
    local driverHash = LoadModel(Config.DriverModel)
    
    if not wagonHash or not driverHash then
       
        return false
    end
    
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    Wait(500)
    
    
    local foundRoad, roadPos = GetClosestVehicleNode(coords.x, coords.y, coords.z, 1, 3.0, 0)
    local spawnCoords = foundRoad and roadPos or coords
    
  
    local _, _, heading = GetClosestVehicleNodeWithHeading(spawnCoords.x, spawnCoords.y, spawnCoords.z, 1, 3.0, 0)
    heading = heading or 0.0
    
    
    
   
    local wagon = CreateVehicle(wagonHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, false)
    if not DoesEntityExist(wagon) then
       
        return false
    end
    
    
    SetVehicleOnGroundProperly(wagon)
    
    local timeout = 0
    while not HasCollisionLoadedAroundEntity(wagon) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    -- Create driver slightly offset
    local driverCoords = GetOffsetFromEntityInWorldCoords(wagon, 0.0, 2.0, 0.0)
    local driver = CreatePed(driverHash, driverCoords.x, driverCoords.y, driverCoords.z, heading, true, true, true)
    if not DoesEntityExist(driver) then
        DeleteVehicle(wagon)
       
        return false
    end
    
    
    -- Configure entities
    ConfigureWagon(wagon)
    ConfigureDriver(driver)
    
    -- Put driver in wagon
    if not PutDriverInWagon(driver, wagon) then
        DeletePed(driver)
        DeleteVehicle(wagon)
       
        return false
    end
    
    -- Store references
    State.wagon = wagon
    State.driver = driver
    State.currentStop = 1
    State.isMoving = false
    State.targetAdded = false
    State.hasControl = false
    
    -- Network registration
    NetworkRegisterEntityAsNetworked(wagon)
    NetworkRegisterEntityAsNetworked(driver)
    
    local wagonNetId = NetworkGetNetworkIdFromEntity(wagon)
    local driverNetId = NetworkGetNetworkIdFromEntity(driver)
    DebugPrint('Wagon NetID: ' .. tostring(wagonNetId) .. ', Driver NetID: ' .. tostring(driverNetId))
    
    SetModelAsNoLongerNeeded(wagonHash)
    SetModelAsNoLongerNeeded(driverHash)
    
    TriggerServerEvent('merchant:server:setEntities', wagonNetId, driverNetId)
    
    CreateWagonBlip()
    AddWagonTarget()
    
    lib.notify({ title = 'Merchant', description = 'Traveling Merchant has arrived!', type = 'success' })
    
    
    return true
end

-- ========================================
-- CLEANUP
-- ========================================

local function CleanupMerchant()
    
    RemoveWagonBlip()
    
    if State.wagon and DoesEntityExist(State.wagon) then
        if State.targetAdded then
            pcall(function()
                exports.ox_target:removeLocalEntity(State.wagon, 'merchant_shop')
            end)
        end
        SetEntityAsMissionEntity(State.wagon, true, true)
        DeleteVehicle(State.wagon)
    end
    
    if State.driver and DoesEntityExist(State.driver) then
        SetEntityAsMissionEntity(State.driver, true, true)
        DeletePed(State.driver)
    end
    
    State.wagon = nil
    State.driver = nil
    State.blip = nil
    State.targetAdded = false
    State.isMoving = false
    State.hasControl = false
end

-- ========================================
-- MAIN THREADS
-- ========================================

-- Initial spawn and start driving
CreateThread(function()
   
    Wait(5000)
    
    if not SpawnMerchant() then
      
        Wait(5000)
        if not SpawnMerchant() then
            DebugPrint('Second spawn failed!')
            return
        end
    end
    
    -- Wait then start driving to stop #2
    Wait(3000)
   
    DriveToStop(2)
end)

-- Route monitoring
CreateThread(function()
    Wait(10000)
    
    while true do
        Wait(3000)
        
        if State.wagon and DoesEntityExist(State.wagon) and State.driver and DoesEntityExist(State.driver) then
            local destCoords, destLabel = GetStopByIndex(State.currentStop)
            
            if destCoords then
                local wagonPos = GetEntityCoords(State.wagon)
                local distance = #(wagonPos - destCoords)
                local wagonSpeed = GetEntitySpeed(State.wagon)
                
                DebugPrint('Distance to ' .. destLabel .. ': ' .. string.format('%.1f', distance) .. ' | Speed: ' .. string.format('%.1f', wagonSpeed))
                
                -- Check if arrived
                if distance <= Config.ArrivalDist then
                    DebugPrint('ARRIVED at ' .. destLabel)
                    StopWagon()
                    
                    lib.notify({ title = 'Merchant', description = 'Arrived at ' .. destLabel, type = 'success' })
                    
                   
                    Wait(Config.IdleAtStopMs)
                    
                    local nextIndex = State.currentStop + 1
                    if nextIndex > #Config.Route then
                        nextIndex = 1
                    end
                    
                    local nextCoords, nextLabel = GetStopByIndex(nextIndex)
                   
                    
                    lib.notify({ title = 'Merchant', description = 'Departing to ' .. nextLabel, type = 'inform' })
                    
                    Wait(1000)
                    DriveToStop(nextIndex)
                    
                elseif not State.isMoving or wagonSpeed < 0.5 then
                    -- Not moving - try to restart
                   
                    DriveToStop(State.currentStop)
                end
            end
            
            CreateWagonBlip()
            AddWagonTarget()
        else
            DebugPrint('Wagon or driver missing!')
        end
    end
end)

-- Prevent players from boarding
CreateThread(function()
    while true do
        Wait(1000)
        
        if State.wagon and DoesEntityExist(State.wagon) then
            local ped = PlayerPedId()
            if IsPedInVehicle(ped, State.wagon, false) then
                TaskLeaveVehicle(ped, State.wagon, 16)
                lib.notify({ title = 'Merchant', description = 'You cannot ride the merchant wagon', type = 'error' })
            end
        end
    end
end)



-- ========================================
-- RESOURCE CLEANUP
-- ========================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CloseShop()
    CleanupMerchant()
end)
