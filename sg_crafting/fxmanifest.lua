fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sg_crafting'
author 'sg_crafting'
description 'Simple QBCore crafting example with menu + server validation'
version '1.0.0'

shared_scripts {
    'config/config.lua',
    'config/locations_cfg.lua',
    'config/recipes_cfg.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server/server.lua'
}

dependencies {
    'qb-core',
    'qb-menu',
    'qb-input'
}
