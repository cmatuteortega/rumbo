-- Gestor de pantallas minimo.
--
-- Una pantalla es un modulo con las funciones que le interesen: enter(...),
-- leave(), update(dt), draw(), press/move/release(x, y), keypressed(key) y
-- resize(). Las que no defina simplemente no se llaman.
--
-- El cambio de pantalla se aplaza al final del fotograma: cambiar dentro de
-- un press() mientras se recorre la pantalla vieja es la forma clasica de
-- comerse un evento a medias.

local ScreenManager = {}

local screens = {}
local current, currentName
local pending

function ScreenManager.init(list, first, ...)
    screens = list
    ScreenManager.switch(first, ...)
    ScreenManager.apply()
end

function ScreenManager.switch(name, ...)
    assert(screens[name], "pantalla desconocida: " .. tostring(name))
    pending = { name = name, args = { ... } }
end

function ScreenManager.apply()
    if not pending then return end
    local next_ = pending
    pending = nil
    if current and current.leave then current.leave() end
    current = screens[next_.name]
    currentName = next_.name
    if current.enter then current.enter(unpack(next_.args)) end
end

function ScreenManager.name() return currentName end

local function forward(fn, ...)
    if current and current[fn] then current[fn](...) end
end

function ScreenManager.update(dt)
    forward("update", dt)
    ScreenManager.apply()
end

function ScreenManager.draw()      forward("draw") end
function ScreenManager.press(x, y) forward("press", x, y) end
function ScreenManager.move(x, y)  forward("move", x, y) end
function ScreenManager.release(x, y) forward("release", x, y) end
function ScreenManager.keypressed(key) forward("keypressed", key) end
function ScreenManager.resize()    forward("resize") end

return ScreenManager
