local RSGCore = exports['rsg-core']:GetCoreObject()


GlobalState.Merchant = {
    wagonNetId = false,
    driverNetId = false,
    status = 'idle',
    spawnRequested = false  
}

local function requestClientSpawn(coords)
    local data = GlobalState.Merchant or {}
    
   
    if data.spawnRequested then
        print('[phils-travmerchant] Spawn already requested, skipping duplicate')
        return
    end
    
    data.status = 'spawning'
    data.wagonNetId = false
    data.driverNetId = false
    data.spawnRequested = true  
    GlobalState.Merchant = data
    
   
    local players = GetPlayers()
    if #players > 0 then
        local targetPlayer = tonumber(players[1])
        print(string.format('[phils-travmerchant] Requesting spawn from player %d', targetPlayer))
        TriggerClientEvent('merchant:client:spawnWagon', targetPlayer, { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 })
    else
        
        data.spawnRequested = false
        GlobalState.Merchant = data
    end
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    
    
    Wait(1000)
    local first = Config.Route[1]
    local coords = first and (first.coords or first) or nil
    if coords then
        requestClientSpawn(coords)
    end
end)


CreateThread(function()
    while true do
        Wait(15000)
        local players = GetPlayers()
        if #players == 0 then goto continue end
        
        local data = GlobalState.Merchant or {}
        
       
        if (not data.wagonNetId or not data.driverNetId or data.status ~= 'alive') and not data.spawnRequested then
            print('[phils-travmerchant] Wagon missing, requesting respawn')
            local first = Config.Route[1]
            local coords = first and (first.coords or first)
            if coords then
                requestClientSpawn(coords)
            end
        end
        
        ::continue::
    end
end)


RegisterNetEvent('merchant:server:setEntities', function(wagonNetId, driverNetId)
    local src = source
    if type(wagonNetId) ~= 'number' or type(driverNetId) ~= 'number' then return end
    
    GlobalState.Merchant = {
        wagonNetId = wagonNetId,
        driverNetId = driverNetId,
        status = 'alive',
        spawnRequested = false  
    }
    
    print(string.format('[phils-travmerchant] Merchant spawned by player %d (wagon:%s driver:%s)', src, wagonNetId, driverNetId))
end)


local function isNightNow(clientHour)
    local hour = tonumber(clientHour)
    if not hour or hour < 0 or hour > 23 then
        hour = tonumber(GlobalState.MerchantHour) or 12
    end
    local startH = Config.NightStart or 20
    local endH = Config.NightEnd or 6
    if startH <= endH then
        return hour >= startH and hour < endH
    else
        return hour >= startH or hour < endH
    end
end


RegisterNetEvent('merchant:server:timeSync', function(hour)
    hour = tonumber(hour)
    if hour and hour >= 0 and hour < 24 then
        GlobalState.MerchantHour = hour
    end
end)


lib.callback.register('merchant:buyItem', function(src, itemName, count, hour)
    local item = Config.Items[itemName]
    local alcohol = Config.Alcohol and Config.Alcohol[itemName]
    local herb = Config.Herbs and Config.Herbs[itemName]
    if not item and not alcohol and not herb then return false, 'Invalid item' end

    local night = isNightNow(hour)
    if (item or herb) and night then return false, 'This item is sold during the day only' end
    if alcohol and not night then return false, 'Alcohol is sold at night only' end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false, 'Player not found' end

    local qty = tonumber(count) or 1
    if qty < 1 then qty = 1 end

    local price = tonumber((item or alcohol or herb).price) or 0
    if price <= 0 then return false, 'Invalid price' end

    local total = price * qty
    local removed = Player.Functions.RemoveMoney(Config.MoneyAccount, total, 'travelling-merchant')
    if not removed then
        return false, 'Not enough money'
    end

    local added = Player.Functions.AddItem(itemName, qty, false, {})
    if not added then
        Player.Functions.AddMoney(Config.MoneyAccount, total, 'merchant-refund')
        return false, 'Inventory full'
    end

    return true, ("Purchased %dx %s for $%d"):format(qty, (item or alcohol or herb).label, total)
end)

lib.callback.register('merchant:buyWeapon', function(src, weaponName, count, hour)
    local w = Config.Weapons and Config.Weapons[weaponName]
    if not w then return false, 'Invalid weapon' end

    if not isNightNow(hour) then return false, 'Weapons are sold at night only' end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false, 'Player not found' end

    local qty = tonumber(count) or 1
    if qty < 1 then qty = 1 end

    local price = tonumber(w.price) or 200
    local total = price * qty

    local removed = Player.Functions.RemoveMoney(Config.MoneyAccount, total, 'merchant-weapon')
    if not removed then return false, 'Not enough money' end

    local added = Player.Functions.AddItem(weaponName, qty, false, {})
    if not added then
        Player.Functions.AddMoney(Config.MoneyAccount, total, 'merchant-refund-weapon')
        return false, 'Inventory full'
    end

    return true, ("Purchased %dx %s for $%d"):format(qty, (w.label or weaponName), total)
end)