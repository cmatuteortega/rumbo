-- Rumbo - idle de navegacion en vista cenital.
--
-- main.lua se ocupa solo de tres cosas: montar el lienzo virtual, cargar las
-- fuentes y repartir los eventos de entrada. Todo lo demas vive en src/.
--
-- El puntero se convierte a coordenadas virtuales UNA vez, aqui, y se pasa
-- tanto a la UI inmediata (src/ui.lua) como a la pantalla activa. Ninguna
-- pantalla toca coordenadas de ventana.

local Constants     = require('src.constants')
local Palette       = require('src.palette')
local Viewport      = require('lib.viewport')
local ScreenManager = require('lib.screen_manager')
local UI            = require('src.ui')
local Session       = require('src.session')

local BootScreen   = require('src.screens.boot')
local VoyageScreen = require('src.screens.voyage')
local PortScreen   = require('src.screens.port')
local ChartScreen  = require('src.screens.chart')

Fonts = {}

-- El resize se aplaza: arrastrar una ventana en escritorio dispara decenas de
-- eventos por segundo y recargar fuentes y lienzo en cada uno da tirones.
local pendingResize, resizeTimer = nil, 0
local RESIZE_DELAY = 0.1
local lastW, lastH = 0, 0

local function loadFonts()
    for name, size in pairs({ large = Constants.FONT_SIZES.LARGE,
                              medium = Constants.FONT_SIZES.MEDIUM,
                              small = Constants.FONT_SIZES.SMALL,
                              tiny = Constants.FONT_SIZES.TINY }) do
        Fonts[name] = love.graphics.newFont("Pixellari.ttf", size)
        Fonts[name]:setFilter('nearest', 'nearest')
    end
end

local function fit(w, h)
    local sx, sy, sw, sh = 0, 0, w, h
    if love.window.getSafeArea then sx, sy, sw, sh = love.window.getSafeArea() end

    Constants.updateResolution(w, h)
    Constants.updateSafeInsets(sx, sy, sw, sh, w, h)
    loadFonts()
    Viewport.setup(Constants.GAME_WIDTH, Constants.GAME_HEIGHT, w, h)
end

function love.load()
    love.graphics.setDefaultFilter('nearest', 'nearest')
    love.graphics.setLineStyle('rough')

    local w, h = love.graphics.getDimensions()
    fit(w, h)
    lastW, lastH = w, h

    ScreenManager.init({
        boot   = BootScreen,
        voyage = VoyageScreen,
        port   = PortScreen,
        chart  = ChartScreen,
    }, 'boot')

    print(string.format("Rumbo | ventana %dx%d | virtual %dx%d | arte %dx%d (x%d)",
                        w, h, Constants.GAME_WIDTH, Constants.GAME_HEIGHT,
                        Constants.ART_W, Constants.ART_H, Constants.ART))
end

function love.update(dt)
    if pendingResize then
        resizeTimer = resizeTimer + dt
        if resizeTimer >= RESIZE_DELAY then
            local w, h = pendingResize.w, pendingResize.h
            pendingResize, resizeTimer = nil, 0
            if w ~= lastW or h ~= lastH then
                fit(w, h)
                lastW, lastH = w, h
                ScreenManager.resize()
            end
        end
    end

    ScreenManager.update(dt)
end

function love.draw()
    love.graphics.clear(Palette.deep)
    Viewport.start()
    ScreenManager.draw()
    UI.finish()          -- consume el toque de este fotograma
    Viewport.finish()
end

--== Entrada ===============================================================

local function press(x, y)
    x, y = Viewport.toGame(x, y)
    if not x then return end
    UI.press(x, y)
    ScreenManager.press(x, y)
end

local function move(x, y)
    x, y = Viewport.toGame(x, y)
    if not x then return end
    UI.move(x, y)
    ScreenManager.move(x, y)
end

local function release(x, y)
    x, y = Viewport.toGame(x, y)
    if not x then return end
    UI.release(x, y)
    ScreenManager.release(x, y)
end

function love.mousepressed(x, y, button, istouch)
    if istouch then return end   -- el tactil llega por su propio callback
    press(x, y)
end

function love.mousemoved(x, y, dx, dy, istouch)
    if istouch then return end
    move(x, y)
end

function love.mousereleased(x, y, button, istouch)
    if istouch then return end
    release(x, y)
end

-- Solo se atiende el primer dedo: no hay ningun gesto a dos manos.
local activeTouch = nil

function love.touchpressed(id, x, y)
    if activeTouch then return end
    activeTouch = id
    press(x, y)
end

function love.touchmoved(id, x, y)
    if id ~= activeTouch then return end
    move(x, y)
end

function love.touchreleased(id, x, y)
    if id ~= activeTouch then return end
    activeTouch = nil
    release(x, y)
end

function love.keypressed(key)
    if key == 'f11' or (key == 'return' and love.keyboard.isDown('lalt', 'ralt')) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        local w, h = love.graphics.getDimensions()
        fit(w, h)
        lastW, lastH = w, h
        return
    end
    if key == 'f5' then
        -- Depuracion: partida nueva.
        Session.reset()
        ScreenManager.switch('voyage')
        return
    end
    ScreenManager.keypressed(key)
end

function love.resize(w, h)
    if w == lastW and h == lastH then return end
    pendingResize, resizeTimer = { w = w, h = h }, 0
end

-- Guardar al perder el foco es lo que hace que el progreso ausente cuadre en
-- movil, donde love.quit puede no llegar a ejecutarse nunca.
function love.focus(focused)
    if not focused then Session.save() end
end

function love.quit()
    Session.save()
end
