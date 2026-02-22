Config = {}
Config.Debug = true

Config.MaxCraftAmount = 10
Config.InteractDistance = 2.0

Config.Target = {
    enabled = true,
    system = 'qb_target',  --- 'qb_target' or 'ox_target'
    icon = 'fas fa-hammer',
    label = 'Open Crafting'
}

Config.Inventory = 'qb'  --- 'qb' or 'ox'

Config.ItemsPath = 'qb'
-- Aliases: 'qb' -> qb-core/shared/items.lua, 
--          'ox' -> ox_inventory/data/items.lua
-- Or use full format: 'resource_name/path/to/items.lua'

Config.Webhook = {  -- Discord Webhook URL
    enabled = false,
    url = '',
    name = 'sg_crafting',
    color = 65280
}

Config.BenchJobs = {
    --'mechanic',
    --'police'
}
-- Use job names from qb-core/shared/jobs.lua.

Config.Marker = { --- Only used if Config.Target is set to false
    type = 2,
    scale = vec3(0.2, 0.2, 0.2),
    color = { r = 46, g = 204, b = 113, a = 180 }
}
