local QBCore = exports['qb-core']:GetCoreObject()
local CraftingBlips = {}
local PlayerData = {}
local UseTarget = Config.Target.enabled
local SpawnedProps = {}
local RecipeCache = nil

local function DebugPrint(message)
    if not Config.Debug then
        return
    end

    print(('[sg_crafting] %s'):format(message))
end

local function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local width = (string.len(text)) / 370
    DrawRect(0.0, 0.0125, 0.017 + width, 0.03, 0, 0, 0, 100)
    ClearDrawOrigin()
end

local function GetPlayerJob()
    if not PlayerData.job then
        return nil, 0
    end

    local name = PlayerData.job.name
    local gradeLevel = 0

    if PlayerData.job.grade then
        gradeLevel = tonumber(PlayerData.job.grade.level or PlayerData.job.grade) or 0
    end

    return name, gradeLevel
end

local function IsJobAllowed(locationData)
    if not locationData.jobs or locationData.jobs == false then
        return true
    end

    local playerJob, playerGrade = GetPlayerJob()
    if not playerJob then
        return false
    end

    if type(Config.BenchJobs) ~= 'table' or #Config.BenchJobs == 0 then
        return false
    end

    local globalAllowed = false
    for _, jobName in ipairs(Config.BenchJobs) do
        if jobName == playerJob then
            globalAllowed = true
            break
        end
    end

    if not globalAllowed then
        return false
    end

    local minGrade = locationData.jobs[playerJob]
    if minGrade == nil then
        return false
    end

    if minGrade == true then
        minGrade = 0
    end

    return playerGrade >= (tonumber(minGrade) or 0)
end

local function ResolveBlipSettings(locationData)
    if type(locationData.blip) ~= 'table' then
        return nil
    end

    if locationData.blip.enabled == false then
        return nil
    end

    return {
        sprite = locationData.blip.sprite or 1,
        color = locationData.blip.color or 0,
        scale = locationData.blip.scale or 0.8,
        display = locationData.blip.display or 4,
        shortRange = locationData.blip.shortRange ~= false
    }
end

local function BuildRequirementsText(recipe)
    local required = {}
    for item, amount in pairs(recipe.items) do
        required[#required + 1] = ('%dx %s'):format(amount, item)
    end
    return table.concat(required, ', ')
end

local function BuildRecipeCache()
    if RecipeCache then
        return RecipeCache
    end

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
    return RecipeCache
end

local function GetLocationRecipeIds(locationData)
    local cache = BuildRecipeCache()
    local ids = {}
    local seen = {}

    for _, recipeRef in ipairs(locationData.recipes or {}) do
        if cache.categories[recipeRef] then
            for _, recipeId in ipairs(cache.categories[recipeRef]) do
                if not seen[recipeId] then
                    seen[recipeId] = true
                    ids[#ids + 1] = recipeId
                end
            end
        elseif cache.recipesById[recipeRef] and not seen[recipeRef] then
            seen[recipeRef] = true
            ids[#ids + 1] = recipeRef
        end
    end

    return ids
end

local function EnsureModelLoaded(modelHash, timeoutMs)
    if HasModelLoaded(modelHash) then
        return true
    end

    RequestModel(modelHash)

    local expiresAt = GetGameTimer() + (timeoutMs or 5000)
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() >= expiresAt then
            return false
        end
        Wait(0)
    end

    return true
end

local function IsValidCoords3(coords)
    if not coords then
        return false
    end

    return tonumber(coords.x) ~= nil
        and tonumber(coords.y) ~= nil
        and tonumber(coords.z) ~= nil
end

local function IsValidCoords4(coords)
    return IsValidCoords3(coords) and tonumber(coords.w) ~= nil
end

local function CoordsToVec3(coords)
    return vec3(coords.x, coords.y, coords.z)
end

local function GetLocationCoords(locationKey, locationData)
    local entity = SpawnedProps[locationKey]
    if entity and DoesEntityExist(entity) then
        return GetEntityCoords(entity)
    end

    local propData = locationData.prop
    if type(propData) == 'table' and propData.coords then
        if IsValidCoords3(propData.coords) then
            return CoordsToVec3(propData.coords)
        end

        DebugPrint(('Location "%s" prop.coords is invalid, expected vec3/vec4.'):format(locationKey))
        return nil
    end

    if IsValidCoords3(locationData.coords) then
        return CoordsToVec3(locationData.coords)
    end

    DebugPrint(('Location "%s" coords is invalid, expected vec3/vec4.'):format(locationKey))
    return nil
end

local function SpawnLocationProp(locationKey, locationData)
    local existingEntity = SpawnedProps[locationKey]
    if existingEntity and DoesEntityExist(existingEntity) then
        return existingEntity
    end

    local propData = locationData.prop
    if type(propData) ~= 'table' or propData.enabled == false then
        return nil
    end

    local model = propData.model
    if not model then
        DebugPrint(('Location "%s" has prop enabled but no model configured.'):format(locationKey))
        return nil
    end

    local modelHash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(modelHash) then
        DebugPrint(('Location "%s" has invalid prop model: %s'):format(locationKey, tostring(model)))
        return nil
    end

    local coords4 = propData.coords or locationData.coords
    if not IsValidCoords4(coords4) then
        DebugPrint(('Location "%s" prop spawn requires vec4 coords (x, y, z, w).'):format(locationKey))
        return nil
    end

    if not EnsureModelLoaded(modelHash, propData.loadTimeoutMs or 5000) then
        DebugPrint(('Location "%s" failed to load prop model: %s'):format(locationKey, tostring(model)))
        return nil
    end

    local entity = CreateObjectNoOffset(modelHash, coords4.x, coords4.y, coords4.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)

    if not DoesEntityExist(entity) then
        DebugPrint(('Location "%s" failed to create prop entity.'):format(locationKey))
        return nil
    end

    SetEntityHeading(entity, coords4.w)

    SpawnedProps[locationKey] = entity
    return entity
end

local function OpenCraftMenu(locationKey)
    local locationData = Config.Locations[locationKey]
    if not locationData then
        return
    end

    if not IsJobAllowed(locationData) then
        QBCore.Functions.Notify('You do not have access to this crafting table.', 'error')
        return
    end

    local menu = {
        {
            header = locationData.label,
            isMenuHeader = true
        }
    }

    local cache = BuildRecipeCache()
    for _, recipeKey in ipairs(GetLocationRecipeIds(locationData)) do
        local recipe = cache.recipesById[recipeKey]
        if recipe then
            menu[#menu + 1] = {
                header = recipe.label,
                txt = ('Needs: %s | Time: %.1fs'):format(BuildRequirementsText(recipe), recipe.duration / 1000),
                params = {
                    event = 'sg_crafting:client:ChooseAmount',
                    args = {
                        locationKey = locationKey,
                        recipeKey = recipeKey
                    }
                }
            }
        end
    end

    menu[#menu + 1] = {
        header = 'Close',
        params = { event = 'qb-menu:closeMenu' }
    }

    exports['qb-menu']:openMenu(menu)
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
end)

RegisterNetEvent('sg_crafting:client:OpenMenuForLocation', function(locationKey)
    OpenCraftMenu(locationKey)
end)

RegisterNetEvent('sg_crafting:client:ChooseAmount', function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = 'Craft Amount',
        submitText = 'Craft',
        inputs = {
            {
                text = 'Amount (1-' .. Config.MaxCraftAmount .. ')',
                name = 'amount',
                type = 'number',
                isRequired = true
            }
        }
    })

    if not dialog or not dialog.amount then
        return
    end

    local amount = tonumber(dialog.amount)
    if not amount then
        QBCore.Functions.Notify('Invalid amount.', 'error')
        return
    end

    TriggerServerEvent('sg_crafting:server:TryCraft', data.locationKey, data.recipeKey, amount)
end)

RegisterNetEvent('sg_crafting:client:StartCraft', function(payload)
    QBCore.Functions.Progressbar(
        'sg_crafting_' .. payload.craftId,
        ('Crafting %s...'):format(payload.label),
        payload.duration,
        false,
        true,
        {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true
        },
        {},
        {},
        {},
        function()
            TriggerServerEvent('sg_crafting:server:CompleteCraft', payload.craftId)
        end,
        function()
            TriggerServerEvent('sg_crafting:server:CancelCraft', payload.craftId)
        end
    )
end)

CreateThread(function()
    PlayerData = QBCore.Functions.GetPlayerData()

    for locationKey, locationData in pairs(Config.Locations) do
        SpawnLocationProp(locationKey, locationData)
    end

    for locationKey, locationData in pairs(Config.Locations) do
        local coords = GetLocationCoords(locationKey, locationData)
        if not coords then
            goto continue_blips
        end
        local blipSettings = ResolveBlipSettings(locationData)
        if blipSettings then
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(blip, blipSettings.sprite)
            SetBlipDisplay(blip, blipSettings.display)
            SetBlipScale(blip, blipSettings.scale)
            SetBlipColour(blip, blipSettings.color)
            SetBlipAsShortRange(blip, blipSettings.shortRange)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(locationData.label)
            EndTextCommandSetBlipName(blip)
            CraftingBlips[locationKey] = blip
        end

        ::continue_blips::
    end
end)

CreateThread(function()
    if not UseTarget then
        return
    end

    if Config.Target.system == 'qb-target' then
        if GetResourceState('qb-target') ~= 'started' then
            print('[sg_crafting] qb-target is not started. Disabling target interactions.')
            UseTarget = false
            return
        end

        for locationKey, locationData in pairs(Config.Locations) do
            local propData = locationData.prop
            local propEnabled = type(propData) == 'table' and propData.enabled ~= false
            local propEntity = SpawnLocationProp(locationKey, locationData)
            if propEntity and DoesEntityExist(propEntity) then
                exports['qb-target']:AddTargetEntity(propEntity, {
                    options = {
                        {
                            icon = Config.Target.icon,
                            label = Config.Target.label,
                            event = 'sg_crafting:client:OpenMenuForLocation',
                            args = locationKey,
                            canInteract = function()
                                return IsJobAllowed(locationData)
                            end
                        }
                    },
                    distance = Config.InteractDistance
                })
            else
                if propEnabled then
                    DebugPrint(('Location "%s" prop target skipped because prop failed to spawn.'):format(locationKey))
                    goto continue_qb_target
                end

                local coords = GetLocationCoords(locationKey, locationData)
                if not coords then
                    goto continue_qb_target
                end

                exports['qb-target']:AddCircleZone(
                    'sg_crafting_' .. locationKey,
                    coords,
                    Config.InteractDistance,
                    {
                        name = 'sg_crafting_' .. locationKey,
                        useZ = true
                    },
                    {
                        options = {
                            {
                                icon = Config.Target.icon,
                                label = Config.Target.label,
                                event = 'sg_crafting:client:OpenMenuForLocation',
                                args = locationKey,
                                canInteract = function()
                                    return IsJobAllowed(locationData)
                                end
                            }
                        },
                        distance = Config.InteractDistance
                    }
                )
            end

            ::continue_qb_target::
        end
    elseif Config.Target.system == 'ox_target' then
        if GetResourceState('ox_target') ~= 'started' then
            print('[sg_crafting] ox_target is not started. Disabling target interactions.')
            UseTarget = false
            return
        end

        for locationKey, locationData in pairs(Config.Locations) do
            local propData = locationData.prop
            local propEnabled = type(propData) == 'table' and propData.enabled ~= false
            local propEntity = SpawnLocationProp(locationKey, locationData)
            if propEntity and DoesEntityExist(propEntity) then
                exports.ox_target:addLocalEntity(propEntity, {
                    {
                        name = 'sg_crafting_' .. locationKey,
                        icon = Config.Target.icon,
                        label = Config.Target.label,
                        onSelect = function()
                            OpenCraftMenu(locationKey)
                        end,
                        canInteract = function()
                            return IsJobAllowed(locationData)
                        end
                    }
                })
            else
                if propEnabled then
                    DebugPrint(('Location "%s" prop target skipped because prop failed to spawn.'):format(locationKey))
                    goto continue_ox_target
                end

                local coords = GetLocationCoords(locationKey, locationData)
                if not coords then
                    goto continue_ox_target
                end

                exports.ox_target:addSphereZone({
                    coords = coords,
                    radius = Config.InteractDistance,
                    debug = false,
                    options = {
                        {
                            name = 'sg_crafting_' .. locationKey,
                            icon = Config.Target.icon,
                            label = Config.Target.label,
                            onSelect = function()
                                OpenCraftMenu(locationKey)
                            end,
                            canInteract = function()
                                return IsJobAllowed(locationData)
                            end
                        }
                    }
                })
            end

            ::continue_ox_target::
        end
    end
end)

CreateThread(function()
    while true do
        local wait = 1500
        if UseTarget then
            Wait(wait)
            goto continue
        end

        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        for locationKey, locationData in pairs(Config.Locations) do
            local coords = GetLocationCoords(locationKey, locationData)
            if not coords then
                goto continue_markers
            end
            local dist = #(playerCoords - coords)

            if dist < 20.0 then
                wait = 0
                DrawMarker(
                    Config.Marker.type,
                    coords.x,
                    coords.y,
                    coords.z,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    Config.Marker.scale.x,
                    Config.Marker.scale.y,
                    Config.Marker.scale.z,
                    Config.Marker.color.r,
                    Config.Marker.color.g,
                    Config.Marker.color.b,
                    Config.Marker.color.a,
                    false,
                    true,
                    2,
                    false,
                    nil,
                    nil,
                    false
                )
            end

            if dist <= Config.InteractDistance and IsJobAllowed(locationData) then
                wait = 0
                DrawText3D(coords.x, coords.y, coords.z + 0.20, '[E] Open Crafting')
                if IsControlJustReleased(0, 38) then
                    OpenCraftMenu(locationKey)
                end
            end

            ::continue_markers::
        end

        Wait(wait)
        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for locationKey, entity in pairs(SpawnedProps) do
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
        SpawnedProps[locationKey] = nil
    end
end)
