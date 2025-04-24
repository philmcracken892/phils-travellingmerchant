
local currentTownName = nil
local currentWagonNetId = nil
local currentNpcNetId = nil
local isWagonSpawning = false
local wagonSpawnCooldown = 5000 -- 5 seconds
local spawningPlayer = nil 
local RSGCore = exports['rsg-core']:GetCoreObject()


RegisterServerEvent('wagon_merchant:server:buyItem')
AddEventHandler('wagon_merchant:server:buyItem', function(itemName, price)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if Player then
        if Player.Functions.GetMoney('cash') >= price then
            if Player.Functions.RemoveMoney('cash', price, "merchant-purchase") then
                Player.Functions.AddItem(itemName, 1)
                TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items[itemName], 'add')
                print("Player " .. GetPlayerName(src) .. " purchased " .. itemName .. " for $" .. price)
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Merchant Wagon',
                    description = 'Failed to process payment',
                    type = 'error'
                })
            end
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Merchant Wagon',
                description = 'You don\'t have enough money!',
                type = 'error'
            })
        end
    end
end)

-- Check VIP status (unchanged)
RSGCore.Functions.CreateCallback('wagon_merchant:server:checkVIP', function(source, cb)
    if not Config.VIPJobName then
        print("[WagonMerchant] Error: Config.VIPJobName is not defined!")
        cb(false)
        return
    end
    local Player = RSGCore.Functions.GetPlayer(source)
    
    if Player and Player.PlayerData.job and Player.PlayerData.job.name == Config.VIPJobName then
        print("Player " .. GetPlayerName(source) .. " has VIP job: " .. Player.PlayerData.job.name)
        cb(true)
    else
        print("Player " .. GetPlayerName(source) .. " does not have VIP job. Current job: " .. 
              (Player and Player.PlayerData.job and Player.PlayerData.job.name or "Unknown"))
        cb(false)
    end
end)

-- Spawn a random wagon
local function SpawnWagonRandomTown()
    -- If there's a current town, make sure to clean up first before proceeding
    if currentTownName then
        TriggerClientEvent('wagon_merchant:client:deleteWagon', -1, currentTownName)
        TriggerClientEvent('wagon_merchant:client:wagonDeparted', -1, currentTownName)
        -- Wait a moment for cleanup to occur
        Citizen.Wait(1000)
        currentTownName = nil
        currentWagonNetId = nil
        currentNpcNetId = nil
        spawningPlayer = nil
    end
    
    -- Skip spawning if we're already in the process
    if isWagonSpawning then
        return
    end
    
    isWagonSpawning = true
    local randomTown = Config.Towns[math.random(#Config.Towns)]
    if not randomTown then
        isWagonSpawning = false
        return
    end
    
    local players = GetPlayers()
    if #players == 0 then
        isWagonSpawning = false
        return
    end
    
    local randomPlayer = players[math.random(#players)]
    spawningPlayer = randomPlayer 
   
    TriggerClientEvent('wagon_merchant:client:spawnWagon', randomPlayer, randomTown)
    
    Citizen.SetTimeout(wagonSpawnCooldown, function()
        isWagonSpawning = false
    end)
end


local function InitializeWagonCycle()
    Citizen.CreateThread(function()
        while true do
            SpawnWagonRandomTown()
            
            if currentTownName then
                Citizen.Wait(Config.VisitDuration * 60 * 1000) -- e.g., 1 minute
                print("[WagonMerchant] Wagon departing from " .. currentTownName)
               
                -- Notify ALL players to remove the wagon entities, not just the spawning player
                TriggerClientEvent('wagon_merchant:client:deleteWagon', -1, currentTownName)
                TriggerClientEvent('wagon_merchant:client:wagonDeparted', -1, currentTownName)
                
                currentTownName = nil
                currentWagonNetId = nil
                currentNpcNetId = nil
                spawningPlayer = nil
            end
            
            local remainingInterval = (Config.SpawnInterval - Config.VisitDuration) * 60 * 1000
            if remainingInterval > 0 then
                Citizen.Wait(remainingInterval) -- e.g., 1 minute
            end
        end
    end)
end

-- Broadcast entity IDs
RegisterServerEvent('wagon_merchant:server:broadcastEntityIds')
AddEventHandler('wagon_merchant:server:broadcastEntityIds', function(townName, wagonNetId, npcNetId)
    if not townName or not wagonNetId or not npcNetId then
       
        return
    end
    
    local validTown = false
    for _, town in ipairs(Config.Towns) do
        if town.name == townName then
            validTown = true
            break
        end
    end
    
    if not validTown then
        
        return
    end
    
    if not currentTownName then
        currentTownName = townName
        currentWagonNetId = wagonNetId
        currentNpcNetId = npcNetId
        
        
        TriggerClientEvent('wagon_merchant:client:setEntityTargets', -1, townName, wagonNetId, npcNetId)
        TriggerClientEvent('wagon_merchant:client:wagonSpawned', -1, townName)
    else
        
    end
end)


RegisterServerEvent('wagon_merchant:server:notifyDeparture')
AddEventHandler('wagon_merchant:server:notifyDeparture', function(townName)
    if currentTownName == townName then
        print("[WagonMerchant] Client-triggered departure from " .. townName)
        currentTownName = nil
        currentWagonNetId = nil
        currentNpcNetId = nil
        spawningPlayer = nil
        TriggerClientEvent('wagon_merchant:client:wagonDeparted', -1, townName)
    end
end)


RegisterServerEvent('wagon_merchant:server:requestWagonStatus')
AddEventHandler('wagon_merchant:server:requestWagonStatus', function()
    local src = source
    if currentTownName and currentWagonNetId and currentNpcNetId then
        TriggerClientEvent('wagon_merchant:client:setEntityTargets', src, currentTownName, currentWagonNetId, currentNpcNetId)
    elseif not isWagonSpawning and not currentTownName then
        SpawnWagonRandomTown()
    end
end)


AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if Config.SpawnInterval < Config.VisitDuration then
            print("[WagonMerchant] Error: SpawnInterval must be >= VisitDuration")
            return
        end
        Citizen.Wait(1000)
        InitializeWagonCycle()
    end
end)


AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        currentTownName = nil
        currentWagonNetId = nil
        currentNpcNetId = nil
        spawningPlayer = nil
        
    end
end)
