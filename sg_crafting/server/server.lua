local QBCore = exports['qb-core']:GetCoreObject()
local PendingCrafts = {}
local ExternalItemDefs = nil
local ExternalItemDefsLoaded = false
local DefaultItemsPath = 'qb-core/shared/items.lua'
local DefaultOxItemsPath = 'ox_inventory/data/items.lua'
local RecipeCache = nil

local function DebugPrint(message)
    if not Config.Debug then
        return
    end

    print(('[sg_crafting] %s'):format(message))
end

local function Notify(src, message, msgType)
    TriggerClientEvent('QBCore:Notify', src, message, msgType or 'primary')
end

local function SendItemBox(src, itemDef, action, amount)
    if Config.Inventory == 'qb' then
        TriggerClientEvent('inventory:client:ItemBox', src, itemDef, action, amount)
    end
end

local function IsOxInventoryReady()
    return GetResourceState('ox_inventory') == 'started'
end

local function TrimString(value)
    if type(value) ~= 'string' then
        return ''
    end

    return value:match('^%s*(.-)%s*$')
end

local function ResolveItemsPath(rawPath)
    local itemsPath = rawPath
    if type(itemsPath) ~= 'string' then
        return DefaultItemsPath
    end

    itemsPath = TrimString(itemsPath)
    if itemsPath == '' then
        return DefaultItemsPath
    end

    local lowered = itemsPath:lower()
    if lowered == 'qb' then
        return DefaultItemsPath
    end

    if lowered == 'ox' then
        return DefaultOxItemsPath
    end

    return itemsPath
end

local function GetItemsPathMode(itemsPath)
    local lowered = itemsPath:lower()
    if lowered:find('ox_inventory', 1, true) then
        return 'ox'
    end

    if lowered:find('qb-core', 1, true) then
        return 'qb'
    end

    return 'custom'
end

local function GetWebhookConfig()
    if type(Config.Webhook) ~= 'table' or Config.Webhook.enabled ~= true then
        return nil
    end

    local url = TrimString(Config.Webhook.url)
    if url == '' then
        return nil
    end

    return {
        url = url,
        name = TrimString(Config.Webhook.name) ~= '' and Config.Webhook.name or 'sg_crafting',
        color = tonumber(Config.Webhook.color) or 65280
    }
end

local function GetPrimaryIdentifier(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, identifier in ipairs(identifiers) do
        if identifier:find('license:', 1, true) == 1 then
            return identifier
        end
    end

    return identifiers[1] or 'unknown'
end

local function BuildMaterialsSpentText(materialsSpent)
    local lines = {}
    for itemName, amount in pairs(materialsSpent or {}) do
        lines[#lines + 1] = ('%dx %s'):format(amount, itemName)
    end

    table.sort(lines)
    if #lines == 0 then
        return 'None'
    end

    return table.concat(lines, '\n')
end

local function SendCraftWebhook(src, craftData)
    local webhook = GetWebhookConfig()
    if not webhook then
        return
    end

    local playerName = GetPlayerName(src) or 'Unknown'
    local payload = {
        username = webhook.name,
        embeds = {
            {
                title = 'Craft Completed',
                color = webhook.color,
                fields = {
                    {
                        name = 'Player',
                        value = ('%s (ID: %d)'):format(playerName, src),
                        inline = false
                    },
                    {
                        name = 'Identifier',
                        value = GetPrimaryIdentifier(src),
                        inline = false
                    },
                    {
                        name = 'Bench',
                        value = ('%s (%s)'):format(craftData.locationLabel or craftData.locationKey, craftData.locationKey or 'unknown'),
                        inline = false
                    },
                    {
                        name = 'Recipe',
                        value = craftData.recipeLabel or craftData.recipeKey or 'unknown',
                        inline = true
                    },
                    {
                        name = 'Crafted',
                        value = ('%dx %s'):format(craftData.amountOut or 0, craftData.itemOut or 'unknown'),
                        inline = true
                    },
                    {
                        name = 'Materials Spent',
                        value = BuildMaterialsSpentText(craftData.materialsSpent),
                        inline = false
                    }
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    }

    PerformHttpRequest(webhook.url, function(statusCode)
        if statusCode < 200 or statusCode >= 300 then
            DebugPrint(('Webhook request failed with status %s'):format(tostring(statusCode)))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function LoadExternalItemDefinitions()
    if ExternalItemDefsLoaded then
        return ExternalItemDefs
    end

    ExternalItemDefsLoaded = true

    local itemsPath = ResolveItemsPath(Config.ItemsPath)

    local slashIndex = itemsPath:find('/')
    if not slashIndex then
        DebugPrint('Config.ItemsPath is invalid. Use: resource/path/to/items.lua')
        return nil
    end

    local resource = itemsPath:sub(1, slashIndex - 1)
    local file = itemsPath:sub(slashIndex + 1)
    if resource == '' or file == '' then
        DebugPrint('Config.ItemsPath is invalid. Use: resource/path/to/items.lua')
        return nil
    end

    local data = LoadResourceFile(resource, file)
    if not data then
        DebugPrint(('Failed to read item definitions from %s/%s'):format(resource, file))
        return nil
    end

    local env = {}
    setmetatable(env, { __index = _G })

    local chunk, loadErr = load(data, ('@@%s/%s'):format(resource, file), 't', env)
    if not chunk then
        DebugPrint(('Failed to parse item definitions: %s'):format(loadErr))
        return nil
    end

    local ok, result = pcall(chunk)
    if not ok then
        DebugPrint(('Failed to execute item definitions: %s'):format(result))
        return nil
    end

    if type(result) == 'table' then
        ExternalItemDefs = result
        return ExternalItemDefs
    end

    if type(env.Items) == 'table' then
        ExternalItemDefs = env.Items
        return ExternalItemDefs
    end

    if type(env.items) == 'table' then
        ExternalItemDefs = env.items
        return ExternalItemDefs
    end

    DebugPrint(('No item table found in %s/%s'):format(resource, file))
    return nil
end

local function GetExternalItemDef(itemName)
    local defs = LoadExternalItemDefinitions()
    if not defs then
        return nil
    end

    return defs[itemName]
end

local function GetItemLabel(itemName)
    if Config.Inventory == 'qb' then
        local shared = QBCore.Shared.Items[itemName]
        return shared and shared.label or itemName
    end

    local externalDef = GetExternalItemDef(itemName)
    if externalDef and externalDef.label then
        return externalDef.label
    end

    if Config.Inventory == 'ox' and IsOxInventoryReady() then
        local itemDef = exports.ox_inventory:Items(itemName)
        if itemDef and itemDef.label then
            return itemDef.label
        end
    end

    return itemName
end

local function ItemExists(itemName)
    if Config.Inventory == 'qb' then
        return QBCore.Shared.Items[itemName] ~= nil
    end

    local externalDef = GetExternalItemDef(itemName)
    if externalDef then
        return true
    end

    if Config.Inventory == 'ox' and IsOxInventoryReady() then
        local itemDef = exports.ox_inventory:Items(itemName)
        return itemDef ~= nil
    end

    return false
end

local function GetItemCount(Player, src, itemName)
    if Config.Inventory == 'ox' then
        if not IsOxInventoryReady() then
            return 0
        end

        return exports.ox_inventory:Search(src, 'count', itemName) or 0
    end

    local itemData = Player.Functions.GetItemByName(itemName)
    return itemData and itemData.amount or 0
end

local function RemoveItem(Player, src, itemName, amount)
    if Config.Inventory == 'ox' then
        if not IsOxInventoryReady() then
            return false
        end

        return exports.ox_inventory:RemoveItem(src, itemName, amount) ~= false
    end

    return Player.Functions.RemoveItem(itemName, amount)
end

local function AddItem(Player, src, itemName, amount)
    if Config.Inventory == 'ox' then
        if not IsOxInventoryReady() then
            return false
        end

        return exports.ox_inventory:AddItem(src, itemName, amount) ~= false
    end

    return Player.Functions.AddItem(itemName, amount)
end

local function IsJobAllowed(locationData, Player)
    if not locationData.jobs or locationData.jobs == false then
        return true
    end

    local job = Player.PlayerData.job
    if not job or not job.name then
        return false
    end

    local playerGrade = tonumber(job.grade and (job.grade.level or job.grade)) or 0

    if type(Config.BenchJobs) ~= 'table' or #Config.BenchJobs == 0 then
        return false
    end

    local globalAllowed = false
    for _, jobName in ipairs(Config.BenchJobs) do
        if jobName == job.name then
            globalAllowed = true
            break
        end
    end

    if not globalAllowed then
        return false
    end

    local minGrade = locationData.jobs[job.name]
    if minGrade == nil then
        return false
    end

    if minGrade == true then
        minGrade = 0
    end

    return playerGrade >= (tonumber(minGrade) or 0)
end

local function LocationHasRecipe(locationData, recipeKey)
    local cache = RecipeCache
    if not cache then
        return false
    end

    for _, recipeRef in ipairs(locationData.recipes or {}) do
        if recipeRef == recipeKey and cache.recipesById[recipeKey] then
            return true
        end

        local categoryIds = cache.categories[recipeRef]
        if categoryIds then
            for _, categoryRecipeId in ipairs(categoryIds) do
                if categoryRecipeId == recipeKey then
                    return true
                end
            end
        end
    end

    return false
end

local function GetRecipe(locationKey, recipeKey)
    if not RecipeCache then
        BuildRecipeCache()
    end

    local locationData = Config.Locations[locationKey]
    if not locationData then
        return nil, nil
    end

    if not LocationHasRecipe(locationData, recipeKey) then
        return nil, nil
    end

    local recipe = RecipeCache and RecipeCache.recipesById[recipeKey]
    if not recipe then
        return nil, nil
    end

    return locationData, recipe
end

local function BuildRecipeCache()
    local cache = {
        recipesById = {},
        categories = {}
    }

    for key, value in pairs(Config.Recipes or {}) do
        if type(value) == 'table' and type(value.items) == 'table' and value.itemOut == nil then
            local categoryIds = {}
            for recipeKey, recipe in pairs(value.items) do
                if type(recipe) == 'table' then
                    local recipeId = ('%s.%s'):format(key, recipeKey)
                    cache.recipesById[recipeId] = recipe
                    categoryIds[#categoryIds + 1] = recipeId
                end
            end

            table.sort(categoryIds)
            cache.categories[key] = categoryIds
        elseif type(value) == 'table' then
            cache.recipesById[key] = value
        end
    end

    RecipeCache = cache
end

local function HasRequiredItems(Player, src, recipe, amount)
    local missing = {}

    for itemName, itemAmount in pairs(recipe.items) do
        local required = itemAmount * amount
        local current = GetItemCount(Player, src, itemName)

        if current < required then
            missing[#missing + 1] = ('%s (%d/%d)'):format(itemName, current, required)
        end
    end

    return #missing == 0, missing
end

RegisterNetEvent('sg_crafting:server:TryCraft', function(locationKey, recipeKey, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        return
    end

    if Config.Inventory == 'ox' and not IsOxInventoryReady() then
        Notify(src, 'ox_inventory is not started.', 'error')
        return
    end

    if PendingCrafts[src] then
        Notify(src, 'You are already crafting something.', 'error')
        return
    end

    amount = tonumber(amount) or 1
    amount = math.floor(amount)
    amount = math.max(1, math.min(amount, Config.MaxCraftAmount))

    local locationData, recipe = GetRecipe(locationKey, recipeKey)
    if not recipe then
        Notify(src, 'Recipe not found for this location.', 'error')
        return
    end

    if not IsJobAllowed(locationData, Player) then
        Notify(src, 'Your job cannot use this crafting table.', 'error')
        return
    end

    if not ItemExists(recipe.itemOut) then
        Notify(src, 'Recipe output item is invalid.', 'error')
        return
    end

    for itemName, _ in pairs(recipe.items) do
        if not ItemExists(itemName) then
            Notify(src, ('Invalid required item in recipe: %s'):format(itemName), 'error')
            return
        end
    end

    local hasItems, missing = HasRequiredItems(Player, src, recipe, amount)
    if not hasItems then
        Notify(src, 'Missing materials: ' .. table.concat(missing, ', '), 'error')
        return
    end

    local materialsSpent = {}
    for itemName, itemAmount in pairs(recipe.items) do
        local total = itemAmount * amount
        materialsSpent[itemName] = total
        local removed = RemoveItem(Player, src, itemName, total)
        if not removed then
            PendingCrafts[src] = nil
            Notify(src, 'Failed to remove required items.', 'error')
            return
        end

        if Config.Inventory == 'qb' then
            SendItemBox(src, QBCore.Shared.Items[itemName], 'remove', total)
        end
    end

    local craftId = ('%d_%d'):format(src, math.random(100000, 999999))
    local duration = (recipe.duration or 5000) * amount

    PendingCrafts[src] = {
        id = craftId,
        locationKey = locationKey,
        locationLabel = locationData.label or locationKey,
        recipeKey = recipeKey,
        recipeLabel = recipe.label,
        itemOut = recipe.itemOut,
        amountOut = (recipe.amountOut or 1) * amount,
        materialsSpent = materialsSpent,
        expiresAt = GetGameTimer() + duration + 10000
    }

    TriggerClientEvent('sg_crafting:client:StartCraft', src, {
        craftId = craftId,
        label = recipe.label,
        duration = duration
    })
end)

RegisterNetEvent('sg_crafting:server:CompleteCraft', function(craftId)
    local src = source
    local craft = PendingCrafts[src]
    if not craft then
        return
    end

    if craft.id ~= craftId then
        return
    end

    if GetGameTimer() > craft.expiresAt then
        PendingCrafts[src] = nil
        Notify(src, 'Craft timed out.', 'error')
        return
    end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        PendingCrafts[src] = nil
        return
    end

    if not ItemExists(craft.itemOut) then
        PendingCrafts[src] = nil
        return
    end

    local added = AddItem(Player, src, craft.itemOut, craft.amountOut)
    if not added then
        PendingCrafts[src] = nil
        Notify(src, 'Inventory full. Crafted item could not be added.', 'error')
        return
    end

    if Config.Inventory == 'qb' then
        SendItemBox(src, QBCore.Shared.Items[craft.itemOut], 'add', craft.amountOut)
    end
    Notify(src, ('Crafted %dx %s'):format(craft.amountOut, GetItemLabel(craft.itemOut)), 'success')
    SendCraftWebhook(src, craft)
    PendingCrafts[src] = nil
end)

RegisterNetEvent('sg_crafting:server:CancelCraft', function(craftId)
    local src = source
    local craft = PendingCrafts[src]
    if not craft then
        return
    end

    if craft.id ~= craftId then
        return
    end

    PendingCrafts[src] = nil
    Notify(src, 'Craft canceled. Materials were consumed.', 'error')
end)

AddEventHandler('playerDropped', function()
    local src = source
    PendingCrafts[src] = nil
end)

-- DebugPrints
local function StartupCheck()
    assert(type(Config) == 'table', 'Config table is missing')
    assert(type(Config.Recipes) == 'table' and next(Config.Recipes), 'Config.Recipes is missing or empty')
    assert(type(Config.Locations) == 'table' and next(Config.Locations), 'Config.Locations is missing or empty')

    BuildRecipeCache()
    assert(next(RecipeCache.recipesById) ~= nil, 'No valid recipes found in Config.Recipes')

    local itemsPath = ResolveItemsPath(Config.ItemsPath)
    local itemsPathMode = GetItemsPathMode(itemsPath)

    if Config.Inventory == 'qb' and itemsPathMode == 'ox' then
        DebugPrint(('Config.Inventory is "qb" but Config.ItemsPath resolves to "%s" (ox). ItemsPath is ignored in qb mode.'):format(itemsPath))
    elseif Config.Inventory == 'ox' and itemsPathMode == 'qb' then
        DebugPrint(('Config.Inventory is "ox" but Config.ItemsPath resolves to "%s" (qb). This may break item lookups.'):format(itemsPath))
    end

    if type(Config.Webhook) == 'table' and Config.Webhook.enabled == true and TrimString(Config.Webhook.url) == '' then
        DebugPrint('Config.Webhook.enabled is true but Config.Webhook.url is empty. Webhooks will not be sent.')
    end

    if Config.Inventory == 'ox' then
        assert(GetResourceState('ox_inventory') == 'started', 'Config.Inventory=ox but ox_inventory is not started')
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    local ok, err = xpcall(StartupCheck, debug.traceback)
    if ok then
        DebugPrint('^2Startup check passed^7')
    else
        DebugPrint(('^1Startup check failed:^7\n%s'):format(err))
    end
end)
