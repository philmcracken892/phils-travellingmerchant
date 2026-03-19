local RSGCore = exports['rsg-core']:GetCoreObject()


local State = {
    wagon = nil,
    blip = nil,
    currentLocationIndex = 1,
    isUIOpen = false
}



local function LoadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
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

local function GetCurrentLocation()
    return Config.Locations[State.currentLocationIndex]
end

local function GetNextLocationIndex()
    local next = State.currentLocationIndex + 1
    if next > #Config.Locations then
        next = 1
    end
    return next
end



local function CreateWagonBlip(coords, label)
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
    if blip and blip ~= 0 then
        SetBlipSprite(blip, GetHashKey(Config.BlipSprite), true)
        SetBlipScale(blip, Config.BlipScale)
        if Config.BlipColor then
            Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(Config.BlipColor))
        end
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, label or 'Traveling Merchant')
    end
    return blip
end

local function RemoveWagonBlip()
    if State.blip and DoesBlipExist(State.blip) then
        RemoveBlip(State.blip)
    end
    State.blip = nil
end



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



local function AddWagonTarget(wagon)
    if not wagon or not DoesEntityExist(wagon) then return end

    exports.ox_target:addLocalEntity(wagon, {
        {
            name = 'merchant_shop',
            icon = 'fa-solid fa-cart-shopping',
            label = 'Browse Wares',
            distance = 3.0,
            onSelect = function()
                OpenShop()
            end
        }
    })
end

local function RemoveWagonTarget(wagon)
    if not wagon or not DoesEntityExist(wagon) then return end
    pcall(function()
        exports.ox_target:removeLocalEntity(wagon, 'merchant_shop')
    end)
end



local function SpawnWagon(location)
    local coords = location.coords
    local label = location.label or 'Merchant'
    local heading = location.heading or 0.0
    
  
    local modelHash = joaat(Config.WagonModel)
    RequestModel(modelHash)
    
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    
    if not HasModelLoaded(modelHash) then
        print('[Merchant] Failed to load wagon model: ' .. Config.WagonModel)
        return nil, nil
    end
    
   
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    Wait(500)
    
    
    local wagon = CreateObject(modelHash, coords.x, coords.y, coords.z - 1.0, false, false, false)
    
    if not wagon or not DoesEntityExist(wagon) then
        print('[Merchant] Failed to create wagon object at ' .. label)
        return nil, nil
    end
    
   
    SetEntityHeading(wagon, heading)
    
    
    PlaceObjectOnGroundProperly(wagon)
    
    
    SetEntityAsMissionEntity(wagon, true, true)
    FreezeEntityPosition(wagon, true)
    SetEntityInvincible(wagon, true)
    
   
    SetModelAsNoLongerNeeded(modelHash)
    
   
    AddWagonTarget(wagon)
    
   
    local blip = CreateWagonBlip(coords, label)
    
    print('[Merchant] Spawned wagon at ' .. label)
    
    return wagon, blip
end

-- ========================================
-- CLEANUP
-- ========================================

local function CleanupWagon()
  
    RemoveWagonBlip()
    
    -- Remove wagon
    if State.wagon and DoesEntityExist(State.wagon) then
        RemoveWagonTarget(State.wagon)
        SetEntityAsMissionEntity(State.wagon, true, true)
        DeleteEntity(State.wagon) 
    end
    State.wagon = nil
end

local function CleanupMerchant()
    CloseShop()
    CleanupWagon()
end

-- ========================================
-- ROTATION SYSTEM
-- ========================================

local function SpawnAtCurrentLocation()
  
    CleanupWagon()
    
    local location = GetCurrentLocation()
    if not location then
        print('[Merchant] Invalid location index: ' .. State.currentLocationIndex)
        return false
    end
    
    local wagon, blip = SpawnWagon(location)
    if wagon then
        State.wagon = wagon
        State.blip = blip
        
        lib.notify({ 
            title = 'Traveling Merchant', 
            description = 'The merchant has arrived at ' .. location.label, 
            type = 'success' 
        })
        
        return true
    end
    
    return false
end

local function RotateToNextLocation()
    local currentLocation = GetCurrentLocation()
    
    
    if State.isUIOpen then
        CloseShop()
        lib.notify({ 
            title = 'Traveling Merchant', 
            description = 'The merchant is packing up and leaving...', 
            type = 'warning' 
        })
    end
    
    
    lib.notify({ 
        title = 'Traveling Merchant', 
        description = 'The merchant is leaving ' .. (currentLocation and currentLocation.label or 'this location') .. '...', 
        type = 'inform' 
    })
    
   
    State.currentLocationIndex = GetNextLocationIndex()
    
    
    Wait(Config.TransitionTime or 5000)
    
   
    SpawnAtCurrentLocation()
end

-- ========================================
-- MAIN THREADS
-- ========================================


CreateThread(function()
    Wait(5000) 
    
  
    if Config.RandomStart then
        State.currentLocationIndex = math.random(1, #Config.Locations)
    end
    
    SpawnAtCurrentLocation()
end)

-- Rotation timer
CreateThread(function()
    Wait(10000) 
    
    while true do
        Wait(Config.RotateTime or 600000) 
        RotateToNextLocation()
    end
end)


CreateThread(function()
    Wait(15000)
    
    while true do
        Wait(30000) -- Check every 30 seconds
        
        if not State.wagon or not DoesEntityExist(State.wagon) then
            print('[Merchant] Wagon missing, respawning...')
            SpawnAtCurrentLocation()
        end
    end
end)



-- ========================================
-- RESOURCE CLEANUP
-- ========================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CleanupMerchant()
end)
