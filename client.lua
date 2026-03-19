local RSGCore = exports['rsg-core']:GetCoreObject()

local wagonEntity, driverEntity
local targetAdded = false
local routeIndex = 1
local isController = false
local lastTaskTime = 0
local wagonBlip = nil
local isUIOpen = false

local function LoadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 200 do
        Wait(50); timeout = timeout + 1
    end
    return HasModelLoaded(hash) and hash or nil
end

local function getNetEntity(netId)
    if not netId or netId == false then return 0 end
    local ent = NetworkGetEntityFromNetworkId(netId)
    return ent or 0
end

local function ensureWagonBlip()
    if not wagonEntity or not DoesEntityExist(wagonEntity) then return end
    if wagonBlip and DoesBlipExist(wagonBlip) then return end
    
    local blip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, 0x318C617C, wagonEntity)
    if blip and blip ~= 0 then
        SetBlipSprite(blip, GetHashKey(Config.BlipSprite), true)
        SetBlipScale(blip, Config.BlipScale)
        
        
        if Config.BlipColor then
            Citizen.InvokeNative(0x662D364ABF16DE2F, blip, GetHashKey(Config.BlipColor))
        end
        
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, 'Merchant Wagon')
        wagonBlip = blip
    end
end

local function clearWagonBlip()
    if wagonBlip and DoesBlipExist(wagonBlip) then
        RemoveBlip(wagonBlip)
    end
    wagonBlip = nil
end

local function refreshEntities()
    local data = GlobalState.Merchant or {}
    local w = getNetEntity(data.wagonNetId)
    local d = getNetEntity(data.driverNetId)
    if w ~= 0 and DoesEntityExist(w) then wagonEntity = w end
    if d ~= 0 and DoesEntityExist(d) then driverEntity = d end
end

local function withinDist(a, b, dist)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) <= dist
end

local function getStop(i)
    local p = Config.Route[i]
    if not p then return nil, nil end
    if p.coords then
        return p.coords, (p.label or ('Stop #' .. tostring(i)))
    else
        return p, ('Stop #' .. tostring(i))
    end
end

local function isNight()
    local h = GetClockHours() or 12
    local s = Config.NightStart or 20
    local e = Config.NightEnd or 6
    if s <= e then return h >= s and h < e else return h >= s or h < e end
end

-- ===================== NUI FUNCTIONS =====================

local function openMerchantUI()
    if isUIOpen then return end
    isUIOpen = true
    
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

local function closeMerchantUI()
    if not isUIOpen then return end
    isUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeShop' })
end

-- NUI Callbacks
RegisterNUICallback('closeUI', function(data, cb)
    closeMerchantUI()
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
    SendNUIMessage({
        action = 'updateMoney',
        money = money
    })
    
    cb('ok')
end)

-- ===================== TARGET =====================

local function addTargetOnce()
    if targetAdded or not wagonEntity or not DoesEntityExist(wagonEntity) then return end

    exports.ox_target:addLocalEntity(wagonEntity, {
        {
            name = 'merchant_open_shop',
            icon = 'fa-solid fa-cart-shopping',
            label = 'Browse Wares',
            distance = 3.5,
            onSelect = function()
                openMerchantUI()
            end
        }
    })

    targetAdded = true
end

-- ===================== WAGON SPAWN =====================

RegisterNetEvent('merchant:client:spawnWagon', function(coords)
    local vec = coords and vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0) or nil
    if not vec then return end
    if wagonEntity and DoesEntityExist(wagonEntity) then return end
    
    local data = GlobalState.Merchant or {}
    if data.wagonNetId and data.wagonNetId ~= false then
        refreshEntities()
        if wagonEntity and DoesEntityExist(wagonEntity) then return end
    end

    local wagonHash = LoadModel(Config.WagonModel)
    local driverHash = LoadModel(Config.DriverModel)
    if not wagonHash or not driverHash then
        lib.notify({ title = 'Merchant', description = 'Failed to load models', type = 'error' })
        return
    end

    RequestCollisionAtCoord(vec.x, vec.y, vec.z)
    local wagon = CreateVehicle(wagonHash, vec.x, vec.y, vec.z, 0.0, true, false)
    if not DoesEntityExist(wagon) then return end

    SetVehicleOnGroundProperly(wagon)
    while not HasCollisionLoadedAroundEntity(wagon) do Wait(50) end

    local driver = CreatePed(driverHash, vec.x, vec.y, vec.z, 0.0, true, true, true)
    if not DoesEntityExist(driver) then
        DeleteVehicle(wagon)
        return
    end

    SetEntityAsMissionEntity(wagon, true, true)
    SetEntityAsMissionEntity(driver, true, true)
    SetVehicleDoorsLocked(wagon, 2)
    SetVehicleDoorsLockedForAllPlayers(wagon, true)
    SetPedFleeAttributes(driver, 0, false)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetEntityInvincible(driver, true)
    SetPedKeepTask(driver, true)
    Citizen.InvokeNative(0x283978A15512B2FE, driver, true)
    Citizen.InvokeNative(0xB8B6430EAD2D2437, driver, GetHashKey("COACH_DRIVER"))

    for i = -1, 3 do
        Citizen.InvokeNative(0x7C65DAC73C35C862, wagon, i, false)
    end

    SetPedIntoVehicle(driver, wagon, -1)
    Wait(500)
    if not IsPedInVehicle(driver, wagon, false) then
        TaskEnterVehicle(driver, wagon, -1, -1, 2.0, 1, 0)
        local attempts = 0
        while not IsPedInVehicle(driver, wagon, false) and attempts < 40 do
            Wait(100)
            attempts = attempts + 1
        end
        if not IsPedInVehicle(driver, wagon, false) then
            DeletePed(driver)
            DeleteVehicle(wagon)
            return
        end
    end

    wagonEntity = wagon
    driverEntity = driver

    local wagonNetId = NetworkGetNetworkIdFromEntity(wagon)
    local driverNetId = NetworkGetNetworkIdFromEntity(driver)
    if type(SetNetworkIdCanMigrate) == 'function' then
        SetNetworkIdCanMigrate(wagonNetId, true)
        SetNetworkIdCanMigrate(driverNetId, true)
    end
    if type(SetNetworkIdExistsOnAllMachines) == 'function' then
        SetNetworkIdExistsOnAllMachines(wagonNetId, true)
        SetNetworkIdExistsOnAllMachines(driverNetId, true)
    end

    SetModelAsNoLongerNeeded(wagonHash)
    SetModelAsNoLongerNeeded(driverHash)

    TriggerServerEvent('merchant:server:setEntities', wagonNetId, driverNetId)

    ensureWagonBlip()
    lib.notify({ title = 'Merchant', description = 'Merchant wagon is on the road.', type = 'inform' })
end)

-- ===================== CONTROLLER LOGIC =====================

local function tryBecomeController()
    if not wagonEntity or not DoesEntityExist(wagonEntity) then return end
    if not driverEntity or not DoesEntityExist(driverEntity) then return end
    if not NetworkHasControlOfEntity(driverEntity) then
        NetworkRequestControlOfEntity(driverEntity)
    end
    isController = NetworkHasControlOfEntity(driverEntity)
end

local function advanceIfArrived()
    if not wagonEntity or not driverEntity then return end
    if not DoesEntityExist(wagonEntity) or not DoesEntityExist(driverEntity) then return end

    local coords, label = getStop(routeIndex)
    if not coords then
        routeIndex = 1
        coords, label = getStop(routeIndex)
    end
    if not coords then return end

    local wagonPos = GetEntityCoords(wagonEntity)
    local arrived = withinDist(wagonPos, coords, Config.ArrivalDist)

    if arrived then
        if NetworkHasControlOfEntity(driverEntity) then
            ClearPedTasks(driverEntity)
            TaskVehicleTempAction(driverEntity, wagonEntity, 1, Config.IdleAtStopMs)
        end
        lib.notify({ title = 'Merchant', description = ('Arrived at %s'):format(label or ('stop #' .. tostring(routeIndex))), type = 'success' })
        Wait(Config.IdleAtStopMs)
        routeIndex = routeIndex + 1
        if routeIndex > #Config.Route then routeIndex = 1 end
        local nextCoords, nextLabel = getStop(routeIndex)
        lib.notify({ title = 'Merchant', description = ('Departing to %s'):format(nextLabel or ('stop #' .. tostring(routeIndex))), type = 'inform' })
        coords = nextCoords or coords
    end

    local now = GetGameTimer()
    if now - lastTaskTime < 3000 then return end
    lastTaskTime = now

    local speed = Config.Speed or 6.0
    TaskVehicleDriveToCoord(driverEntity, wagonEntity, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, speed, 1.0, GetEntityModel(wagonEntity), 67633207, 1.0, true)
end

-- ===================== THREADS =====================

CreateThread(function()
    while true do
        refreshEntities()
        if wagonEntity and DoesEntityExist(wagonEntity) then
            addTargetOnce()
            ensureWagonBlip()
        else
            targetAdded = false
            clearWagonBlip()
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        tryBecomeController()
        advanceIfArrived()
        Wait(1000)
    end
end)

-- Prevent players from boarding or dragging the driver
CreateThread(function()
    while true do
        if wagonEntity and DoesEntityExist(wagonEntity) then
            for i = -1, 3 do
                local pedInSeat = GetPedInVehicleSeat(wagonEntity, i)
                if pedInSeat and pedInSeat ~= 0 and DoesEntityExist(pedInSeat) then
                    if not driverEntity or pedInSeat ~= driverEntity then
                        if IsPedAPlayer(pedInSeat) then
                            TaskLeaveVehicle(pedInSeat, wagonEntity, 16)
                        end
                    end
                end
            end
        end
        Wait(1000)
    end
end)

-- Sync world hour to server for time-gated shop
CreateThread(function()
    while true do
        local h = GetClockHours()
        TriggerServerEvent('merchant:server:timeSync', h)
        Wait(30000)
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    closeMerchantUI()
    clearWagonBlip()
    if wagonEntity and DoesEntityExist(wagonEntity) then
        DeleteVehicle(wagonEntity)
    end
    if driverEntity and DoesEntityExist(driverEntity) then
        DeletePed(driverEntity)
    end
end)