local RSGCore = exports['rsg-core']:GetCoreObject()
local wagonSpawned = false
local currentWagon = nil
local currentNPC = nil
local currentTown = nil
local wagonBlip = nil

local function CreateWagonBlip(coords)
    if wagonBlip then
        RemoveBlip(wagonBlip)
    end
    
    wagonBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
    SetBlipSprite(wagonBlip, Config.BlipSprite or 1475879922) -- Wagon sprite
    SetBlipScale(wagonBlip, Config.BlipScale or 0.2)
    Citizen.InvokeNative(0x9CB1A1623062F402, wagonBlip, "Merchant Wagon")
    
    return wagonBlip
end

local function RemoveWagonBlip()
    if wagonBlip then
        RemoveBlip(wagonBlip)
        wagonBlip = nil
    end
end

if not Config or not Config.Towns or #Config.Towns == 0 or 
   not Config.MerchantItems or #Config.MerchantItems == 0 or 
   not Config.VIPMerchantItems or #Config.VIPMerchantItems == 0 or 
   not Config.WagonModel or not Config.NPCModel then
    print("[WagonMerchant] Error: Config is missing or incomplete!")
    return
end


if not lib then
    print("[WagonMerchant] Error: ox_lib is not loaded!")
    return
end


local function NotifyPlayer(message, type)
    if lib and lib.notify then
        lib.notify({
            title = 'Merchant Wagon',
            description = message,
            type = type or 'info',
            position = 'top',
            icon = 'fas fa-horse-head'
        })
    else
        TriggerEvent('chat:addMessage', {
            color = type == 'error' and {255, 0, 0} or {255, 255, 255},
            args = {"[Merchant Wagon]", message}
        })
    end
end


local function DebugPrint(message)
    if Config.Debug then
        print("[WagonMerchant] " .. message)
    end
end


local function LoadModel(model)
    local modelHash = joaat(model)
    if not IsModelValid(modelHash) then
        DebugPrint("Error: Invalid model " .. model)
        return nil
    end
    RequestModel(modelHash)
    local timeout = 10000 -- 10 seconds
    local startTime = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        Wait(10)
        if GetGameTimer() - startTime > timeout then
            DebugPrint("Error: Failed to load model " .. model)
            return nil
        end
    end
    return modelHash
end


local function RemoveWagonAndNPC()
	RemoveWagonBlip()
    if DoesEntityExist(currentWagon) then
        exports.ox_target:removeLocalEntity(currentWagon)
        DeleteEntity(currentWagon)
    end
    if DoesEntityExist(currentNPC) then
        exports.ox_target:removeLocalEntity(currentNPC)
        DeleteEntity(currentNPC)
    end
    currentWagon = nil
    currentNPC = nil
    wagonSpawned = false
    currentTown = nil
    DebugPrint("Wagon and NPC have been removed")
end


local function OpenMerchantRegularMenu()
    local options = {}
    for _, item in ipairs(Config.MerchantItems) do
        if item and item.label and item.price then 
            table.insert(options, {
                title = item.label,
                description = (item.description or "No description") .. " - $" .. item.price,
                icon = 'box',
                onSelect = function()
                    TriggerServerEvent('wagon_merchant:server:buyItem', item.name, item.price)
                end,
                metadata = {
                    {label = 'Price', value = '$' .. item.price}
                }
            })
        end
    end

    

    lib.registerContext({
        id = 'merchant_regular_shop',
        title = 'Regular Goods',
        menu = 'merchant_regular_shop',
        options = options
    })
    lib.showContext('merchant_regular_shop')
end

local function OpenMerchantVIPMenu()
    local options = {}
    for _, item in ipairs(Config.VIPMerchantItems) do
        if item and item.label and item.price then 
            table.insert(options, {
                title = item.label,
                description = (item.description or "No description") .. " - $" .. item.price,
                icon = 'gem',
                onSelect = function()
                    TriggerServerEvent('wagon_merchant:server:buyItem', item.name, item.price)
                end,
                metadata = {
                    {label = 'Price', value = '$' .. item.price},
                    {label = 'VIP', value = 'Exclusive Item'}
                }
            })
        end
    end

    

    lib.registerContext({
        id = 'merchant_vip_shop',
        title = 'VIP Exclusive Items',
        menu = 'merchant_vip_shop',
        options = options
    })
    lib.showContext('merchant_vip_shop')
end

local function OpenMerchantMainMenu()
    local options = {
        {
            title = 'General Store',
            description = 'Browse regular goods',
            icon = 'cart-shopping',
            onSelect = function()
                OpenMerchantRegularMenu()
            end
        }
    }

    RSGCore.Functions.TriggerCallback('wagon_merchant:server:checkVIP', function(isVIP)
        if isVIP then
            table.insert(options, {
                title = 'VIP Exclusive Items',
                description = 'Browse special goods for VIPs',
                icon = 'crown',
                onSelect = function()
                    OpenMerchantVIPMenu()
                end
            })
        end

        lib.registerContext({
            id = 'merchant_main_menu',
            title = 'Traveling Merchant',
            menu = 'merchant_main_menu',
            options = options
        })
        lib.showContext('merchant_main_menu')
    end)
end


local function ApplyTargetToEntities(wagonEntity, npcEntity)
    if DoesEntityExist(npcEntity) then
        exports.ox_target:removeLocalEntity(npcEntity)
        exports.ox_target:addLocalEntity(npcEntity, {
            {
                name = 'merchant_shop_npc',
                icon = 'fas fa-shopping-cart',
                label = 'Talk to Merchant',
                distance = 3.0,
                onSelect = function()
                    OpenMerchantMainMenu()
                end
            }
        })
    end
    
    if DoesEntityExist(wagonEntity) then
        exports.ox_target:removeLocalEntity(wagonEntity)
        exports.ox_target:addLocalEntity(wagonEntity, {
            {
                name = 'merchant_shop_wagon',
                icon = 'fas fa-shopping-cart',
                label = 'Browse Merchant Goods',
                distance = 3.0,
                onSelect = function()
                    OpenMerchantMainMenu()
                end
            }
        })
    end
end

local function SpawnWagonAtTown(town)
    if wagonSpawned or not town or not town.coords then
        
        return
    end
    
    wagonSpawned = true
    currentTown = town
    
    local wagonHash = LoadModel(Config.WagonModel)
    if not wagonHash then
        wagonSpawned = false
       
        return
    end
    
    currentWagon = CreateVehicle(wagonHash, town.coords.x, town.coords.y, town.coords.z, town.heading, true, false, false, false)
    if not DoesEntityExist(currentWagon) then
        wagonSpawned = false
        SetModelAsNoLongerNeeded(wagonHash)
        
        return
    end
    
    if NetworkGetEntityIsNetworked(currentWagon) == false then
        NetworkRegisterEntityAsNetworked(currentWagon)
    end
    Citizen.InvokeNative(0x9587913B9E772D29, currentWagon, true)
    SetVehicleDoorsLocked(currentWagon, 2)
    SetEntityAsMissionEntity(currentWagon, true, true)
    SetModelAsNoLongerNeeded(wagonHash)
    
    local npcHash = LoadModel(Config.NPCModel)
    if not npcHash then
        DeleteEntity(currentWagon)
        wagonSpawned = false
       
        return
    end
    
    currentNPC = CreatePed(npcHash, town.coords.x, town.coords.y, town.coords.z, town.heading, true, false, false, false)
    if not DoesEntityExist(currentNPC) then
        DeleteEntity(currentWagon)
        wagonSpawned = false
        SetModelAsNoLongerNeeded(npcHash)
        
        return
    end
    
    if NetworkGetEntityIsNetworked(currentNPC) == false then
        NetworkRegisterEntityAsNetworked(currentNPC)
    end
    SetEntityAsMissionEntity(currentNPC, true, true)
    Citizen.InvokeNative(0x283978A15512B2FE, currentNPC, true)
    SetModelAsNoLongerNeeded(npcHash)
    
    SetPedIntoVehicle(currentNPC, currentWagon, -1)
    SetBlockingOfNonTemporaryEvents(currentNPC, true)
    
    Citizen.Wait(500)
    
    local wagonNetId = NetworkGetNetworkIdFromEntity(currentWagon)
    local npcNetId = NetworkGetNetworkIdFromEntity(currentNPC)
    
    if wagonNetId ~= 0 and npcNetId ~= 0 then
        TriggerServerEvent('wagon_merchant:server:broadcastEntityIds', town.name, wagonNetId, npcNetId)
		CreateWagonBlip(town.coords)
    else
        DebugPrint("Failed to get valid network IDs for entities")
        RemoveWagonAndNPC()
        return
    end
    
    
end


local function RequestWagonStatus()
    TriggerServerEvent('wagon_merchant:server:requestWagonStatus')
end


Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if currentWagon and DoesEntityExist(currentWagon) then
            local ped = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)
            local wagonCoords = GetEntityCoords(currentWagon)
            local distance = #(pedCoords - wagonCoords)
            
            if distance < 2.5 and Citizen.InvokeNative(0x84D0BF2B21862059, ped) and 
               GetVehiclePedIsEntering(ped) == currentWagon then
                ClearPedTasksImmediately(ped)
                NotifyPlayer("This wagon is not for passengers!", "error")
            end
        end
    end
end)


RegisterNetEvent('wagon_merchant:client:setEntityTargets')
AddEventHandler('wagon_merchant:client:setEntityTargets', function(townName, wagonNetId, npcNetId)
    local maxRetries = 10
    local retryInterval = 500
    local attempt = 0
    
    local function tryApplyTargets()
        local wagonEntity = NetworkGetEntityFromNetworkId(wagonNetId)
        local npcEntity = NetworkGetEntityFromNetworkId(npcNetId)
        
        if DoesEntityExist(wagonEntity) and DoesEntityExist(npcEntity) then
            
            ApplyTargetToEntities(wagonEntity, npcEntity)
        elseif attempt < maxRetries then
            attempt = attempt + 1
            
            Citizen.SetTimeout(retryInterval, tryApplyTargets)
        else
            
        end
    end
    
    tryApplyTargets()
end)


AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        Citizen.Wait(1000)
        RequestWagonStatus()
    end
end)

RegisterNetEvent('playerSpawned')
AddEventHandler('playerSpawned', function()
    Citizen.Wait(1000)
    RequestWagonStatus()
end)

RegisterNetEvent('wagon_merchant:client:spawnWagon')
AddEventHandler('wagon_merchant:client:spawnWagon', function(town)
    if not wagonSpawned then
        SpawnWagonAtTown(town)
    end
end)

RegisterNetEvent('wagon_merchant:client:wagonSpawned')
AddEventHandler('wagon_merchant:client:wagonSpawned', function(townName)
    NotifyPlayer("A merchant wagon has arrived in " .. townName .. "!", "info")
    
    
    for _, town in ipairs(Config.Towns) do
        if town.name == townName then
            CreateWagonBlip(town.coords)
            break
        end
    end
end)


RegisterNetEvent('wagon_merchant:client:deleteWagon')
AddEventHandler('wagon_merchant:client:deleteWagon', function(townName)
    
    RemoveWagonAndNPC()
end)

RegisterNetEvent('wagon_merchant:client:wagonDeparted')
AddEventHandler('wagon_merchant:client:wagonDeparted', function(townName)
    
    RemoveWagonAndNPC()
	RemoveWagonBlip()
    NotifyPlayer("The merchant wagon has departed from " .. townName .. ".", "info")
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        RemoveWagonAndNPC()
    end
end)
