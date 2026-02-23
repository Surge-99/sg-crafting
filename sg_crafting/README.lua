--[[
sg_crafting - User Guide

This guide is for server owners using the script.
It explains setup, configuration, and where to edit integrations.

-----------------------------------------------------------------------
1) What This Resource Does
-----------------------------------------------------------------------
- Adds configurable crafting benches.
- Supports job-restricted benches.
- Supports qb-target / ox_target or marker + E interaction.
- Supports qb inventory and ox inventory modes.
- Supports recipe categories.
- Optional Discord webhook logs for successful crafts.

-----------------------------------------------------------------------
2) File Map
-----------------------------------------------------------------------
- fxmanifest.lua
  Resource load order and dependencies.

- config/config.lua
  Main settings (debug, target system, inventory mode, webhook, etc).

- config/locations_cfg.lua
  Bench locations, optional spawned prop setup, job rules, bench recipes.

- config/recipes_cfg.lua
  Crafting recipes and recipe categories.

- client/client.lua
  Interaction zones/targets, menu UI, amount input, progressbar.

- server/server.lua
  Secure validation, remove/add items, anti-abuse checks, webhooks.

-----------------------------------------------------------------------
3) Basic Setup
-----------------------------------------------------------------------
1. Put the resource in your server resources folder.
2. Ensure dependencies are started (`qb-core`, plus menu/input resources
   for your setup, and target/inventory resources you use).
3. Delete qb-crafting or any other crafting script used so no duplicates are encountered
4. Configure `config/config.lua`.
5. Configure recipes in `config/recipes_cfg.lua`.
6. Configure benches in `config/locations_cfg.lua`.
7. `restart sg_crafting`.

-----------------------------------------------------------------------
4) Main Config (config/config.lua)
-----------------------------------------------------------------------
- `Config.Debug`
  true/false debug prints in console.

- `Config.Target.enabled`
  true = target interactions, false = marker + E.

- `Config.Target.system`
  `'qb-target'` or `'ox_target'`.

- `Config.Menu`
  `'qb'` or `'ox'`.
  - `'qb'` uses `qb-menu` + `qb-input`
  - `'ox'` uses `ox_lib` context + input dialog

- `Config.Inventory`
  `'qb'` or `'ox'`.

- `Config.ItemsPath`
  Used for non-qb item definition loading.
  Allowed:
  - `'qb'` (alias to `qb-core/shared/items.lua`)
  - `'ox'` (alias to `ox_inventory/data/items.lua`)
  - Full custom path: `resource_name/path/to/items.lua`

- `Config.Webhook`
  Optional Discord logging for successful crafts.

-----------------------------------------------------------------------
5) Recipes (config/recipes_cfg.lua)
-----------------------------------------------------------------------
Recipes are grouped by category.

Example:
Config.Recipes = {
    Illegal = {
        items = {
            lockpick = {
                label = 'Lockpick',
                itemOut = 'lockpick',
                amountOut = 1,
                duration = 7000,
                items = {
                    metalscrap = 8,
                    plastic = 5
                }
            }
        }
    }
}

Recipe fields:
- `label`: menu display name
- `itemOut`: item to receive
- `amountOut`: output count per craft
- `duration`: milliseconds
- `items`: required materials table

-----------------------------------------------------------------------
6) Bench Locations (config/locations_cfg.lua)
-----------------------------------------------------------------------
Each location controls where and how players craft.

Important:
- If no spawned prop is used, `coords` can be `vec3`.
- If spawned prop is enabled, `prop.coords` must be `vec4(x, y, z, w)`.

Example:
public_bench = {
    label = 'Public Workbench',
    coords = vec3(-347.07, -133.64, 39.01),
    prop = {
        enabled = true,
        model = 'prop_tool_bench02_ld',
        coords = vec4(-347.07, -133.64, 38.01, 340.0)
    },
    recipes = { 'Illegal' },
    jobs = false
}

`recipes` supports:
- category names (recommended): `{ 'Illegal' }`
- legacy direct recipe keys
- mixed lists

`jobs`:
- `false` = open to everyone
- table = restricted by job/grade at that bench

If `prop.enabled = true` and the prop fails to spawn:
- no fallback zone target is created for that location.

-----------------------------------------------------------------------
7) Webhooks (config/config.lua)
-----------------------------------------------------------------------
Example:
Config.Webhook = {
    enabled = true,
    url = 'YOUR_DISCORD_WEBHOOK_URL',
    name = 'sg_crafting',
    color = 65280
}

Sent on successful craft:
- player name + server ID
- identifier
- bench used
- recipe used
- crafted item + amount received
- materials spent

-----------------------------------------------------------------------
8) Integrating Custom Inventory
-----------------------------------------------------------------------
Edit `server/server.lua`.

Main integration functions:
- `GetItemLabel(itemName)`
- `ItemExists(itemName)`
- `GetItemCount(Player, src, itemName)`
- `RemoveItem(Player, src, itemName, amount)`
- `AddItem(Player, src, itemName, amount)`

If you add a new inventory system:
1. Add a new config mode (example: `'my_inventory'`).
2. Add branches in the functions above for your inventory exports.
3. Keep validation server-side (never trust client-side item data).

-----------------------------------------------------------------------
9) Integrating Custom Target
-----------------------------------------------------------------------
Edit `client/client.lua`.

Target setup thread:
- look for `CreateThread(function()` block that checks:
  - `Config.Target.system == 'qb-target'`
  - `Config.Target.system == 'ox_target'`

For a new target system:
1. Add another branch for your target exports.
2. Register interactions for:
   - spawned prop entity when available
   - fallback zone when prop is not used
3. Keep `canInteract` job checks.

-----------------------------------------------------------------------
10) Troubleshooting
-----------------------------------------------------------------------
- No interaction appears:
  - verify `Config.Target.enabled` and target resource started
  - if using prop mode, verify prop model and `vec4` heading coords

- Items not recognized:
  - verify `Config.Inventory`
  - verify `Config.ItemsPath` alias/path for your mode

- No webhook messages:
  - verify `Config.Webhook.enabled = true`
  - verify webhook URL is valid
  - turn on `Config.Debug = true` and check startup logs

-----------------------------------------------------------------------
11) Security Note
-----------------------------------------------------------------------
Keep all item add/remove logic on server side (`server/server.lua`).
Do not move reward logic to client events.
]]
