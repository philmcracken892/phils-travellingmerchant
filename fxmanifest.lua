fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'phil'
description 'Travelling merchant wagon '
lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    
    'server.lua'
}

client_scripts {
    
    'client.lua'
}

dependencies {
    'rsg-core',
    'ox_lib',
    'ox_target'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}


