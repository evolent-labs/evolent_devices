fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

author 'Evolent Labs'
description 'Evolent Devices: laptops, computers, terminals and tablets, their admin panel and the app API'
version '1.0.2'

dependencies { 'ox_lib', 'oxmysql', '/onesync' }

shared_script '@ox_lib/init.lua'

ox_lib 'locale'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/init.lua',
}

client_script 'client/init.lua'

ui_page 'web/build/index.html'

files {
    'config/*.lua',
    'locales/*.json',
    'bridge/init.lua',
    'bridge/client/*.lua',
    'integrations/init.lua',
    'integrations/client/*.lua',
    'shared/*.lua',
    'client/*.lua',
    'sdk/app.lua',
    'web/build/index.html',
    'web/build/os.html',
    'web/build/idle.html',
    'web/build/out_of_service.html',
    'web/build/map.json',
    'web/build/assets/*',
    'web/build/fonts/*',
    'web/build/idle/*',
    'web/build/items/*',
    'web/build/marker/*',
    'web/build/store/*',
    'web/build/wallpapers/*',
    'stream/evd_devices.ytyp',
    'stream/evd_tablet.ytyp',
    'stream/evd_studio_set.ytyp',
}

data_file 'DLC_ITYP_REQUEST' 'stream/evd_devices.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/evd_tablet.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/evd_studio_set.ytyp'
