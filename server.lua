local RSGCore = exports['rsg-core']:GetCoreObject()

local merchantData = {
    wagonNetId = nil,
    driverNetId = nil,
    spawned = false
}

-- Store entity IDs when client spawns
RegisterNetEvent('merchant:server:setEntities', function(wagonNetId, driverNetId)
    local src = source
    merchantData.wagonNetId = wagonNetId
    merchantData.driverNetId = driverNetId
    merchantData.spawned = true
    print(('[Merchant] Spawned by player %d - Wagon: %d, Driver: %d'):format(src, wagonNetId, driverNetId))
end)

-- ========================================
-- SHOP CALLBACKS
-- ========================================

local function isNightNow(clientHour)
    local hour = tonumber(clientHour) or 12
    local startH = Config.NightStart or 20
    local endH = Config.NightEnd or 6
    if startH <= endH then
        return hour >= startH and hour < endH
    else
        return hour >= startH or hour < endH
    end
end

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
    if not removed then return false, 'Not enough money' end

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
