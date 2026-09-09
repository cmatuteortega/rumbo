-- Rumbo - idle de navegacion en vista cenital, formato vertical (movil).
-- La ventana base es 540x960 igual que AutoChest: el arte es de 16px y se
-- dibuja a escala entera 5x, asi que el area de juego son ~108x192 pixeles
-- de arte. Ver src/constants.lua.

function love.conf(t)
    t.identity = "rumbo"
    t.version = "11.4"
    t.console = false
    t.accelerometerjoystick = false
    t.externalstorage = false
    t.gammacorrect = false

    t.audio.mic = false
    t.audio.mixwithsystem = true

    t.window.title = "Rumbo"
    t.window.icon = nil
    t.window.width = 540
    t.window.height = 960
    t.window.borderless = false
    t.window.resizable = true
    t.window.minwidth = 270
    t.window.minheight = 480
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.highdpi = false     -- pixel perfecto: sin escalado de DPI
    t.window.usedpiscale = false

    -- En movil bloqueamos vertical y vamos a pantalla completa.
    if love.system and love.system.getOS then
        local os = love.system.getOS()
        if os == "Android" or os == "iOS" then
            t.window.orientation = "portrait"
            t.window.fullscreen = true
            t.window.fullscreentype = "desktop"
        end
    end

    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = false
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false
    t.modules.sound = true
    t.modules.system = true
    t.modules.thread = false
    t.modules.timer = true
    t.modules.touch = true
    t.modules.video = false
    t.modules.window = true
end
