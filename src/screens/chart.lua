-- Carta de marear.
--
-- La tercera pantalla, y la unica del juego que se dibuja CON EL NORTE
-- ARRIBA. La travesia lleva la camara solidaria a la proa (ver src/sea.lua)
-- porque es lo que ves desde cubierta; una carta es un papel sobre una mesa y
-- no gira con el barco. Que las dos vistas esten orientadas distinto es la
-- diferencia entre mirar por la borda y mirar el papel, y es a proposito.
--
-- Nada de lo que hay aqui es un sprite orientado: los puertos son puntos, el
-- barco es una marca con una aguja ploteada pixel a pixel como la del timon, y
-- la derrota al puerto de destino es una linea de puntos. Asi que la regla de
-- "nada girado" se cumple sin tener que fingir nada.
--
-- La carta no guarda nada: los puertos salen de state.discovered (claves de
-- celda) resueltas con Ports.fromKey. El encuadre y el zoom son de la
-- pantalla, no de la partida — al volver a abrirla se reencuadra sola, que es
-- lo que uno quiere el 90% de las veces.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Art       = require('src.art')
local UI        = require('src.ui')
local World     = require('src.world')
local Ports     = require('src.ports')
local Session   = require('src.session')
local ScreenManager = require('lib.screen_manager')

local Chart = {}

-- MIN_SCALE tiene que dar para la derrota mas larga que quepa imaginar: una
-- travesia de horas cubre cien mil pixeles de mundo y con un minimo mas alto
-- el encuadre se recortaba, el barco se salia del papel por abajo y solo se
-- veia la derrota entrando desde el borde. Aun asi frameAll comprueba que
-- entra, porque un minimo siempre se puede quedar corto.
local MIN_SCALE, MAX_SCALE = 0.0012, 0.30

local ports = {}       -- puertos descubiertos, cacheados
local known = 0        -- cuantos habia cuando se construyo la cache
local scale, camX, camY = 0.05, 0, 0
local selected = nil
local dragging, dragX, dragY = false, 0, 0
local moved = false

local function state() return Session.state end

--==========================================================================
-- Cache de puertos descubiertos
--==========================================================================

local function countDiscovered(s)
    local n = 0
    for _ in pairs(s.discovered) do n = n + 1 end
    return n
end

-- Resolver cada clave cuesta un hash, y con cientos de puertos hacerlo cada
-- fotograma se nota. Se reconstruye solo cuando aparece uno nuevo (el mundo
-- sigue corriendo mientras miras la carta).
local function refresh(s)
    local n = countDiscovered(s)
    if n == known and #ports > 0 then return end
    known = n
    ports = {}
    for key in pairs(s.discovered) do
        local port = Ports.fromKey(s.seed, key)
        if port then ports[#ports + 1] = port end
    end
    table.sort(ports, function(a, b) return a.key < b.key end)
end

--==========================================================================
-- Encuadre
--==========================================================================

local function viewport()
    local top = Constants.SAFE_TOP + 76
    local bottom = Constants.GAME_HEIGHT - Constants.SAFE_BOTTOM - 210
    return 0, top, Constants.GAME_WIDTH, bottom - top
end

local function toScreen(wx, wy)
    local vx, vy, vw, vh = viewport()
    return vx + vw / 2 + (wx - camX) * scale,
           vy + vh / 2 + (wy - camY) * scale
end

local function centreOnShip(s)
    camX, camY = s.x, s.y
    scale = Util.clamp(math.max(scale, 0.08), MIN_SCALE, MAX_SCALE)
end

-- Encaja el barco y todo lo descubierto con margen. Es lo que se hace al
-- abrir: la carta siempre empieza ensenandote todo lo que sabes.
local function frameAll(s)
    local minX, minY, maxX, maxY = s.x, s.y, s.x, s.y
    for _, port in ipairs(ports) do
        minX, maxX = math.min(minX, port.x), math.max(maxX, port.x)
        minY, maxY = math.min(minY, port.y), math.max(maxY, port.y)
    end
    camX, camY = (minX + maxX) / 2, (minY + maxY) / 2

    local _, vy, vw, vh = viewport()
    -- Margen generoso: sin el, el barco y el puerto mas lejano quedan pegados
    -- al borde y el de arriba se mete debajo de la cabecera.
    local spanX = math.max(400, maxX - minX)
    local spanY = math.max(400, maxY - minY)
    scale = Util.clamp(math.min((vw - 80) / spanX, (vh - 80) / spanY),
                       MIN_SCALE, MAX_SCALE)

    -- Si aun asi no entra todo, manda el barco: una carta sin el "estoy aqui"
    -- no sirve para nada, y lo demas esta a un toque de zoom.
    local sx, sy = toScreen(s.x, s.y)
    if sx < 8 or sy < vy + 8 or sx > vw - 8 or sy > vy + vh - 8 then
        centreOnShip(s)
    end
end

--==========================================================================
-- Dibujo
--==========================================================================

local function dot(x, y, size, color)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", math.floor(x - size / 2), math.floor(y - size / 2),
                            size, size)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Reticula de la carta: una linea cada celda de puertos, que es la unidad
-- real del mundo. Da escala sin tener que escribir numeros por todas partes.
local function drawGrid()
    local vx, vy, vw, vh = viewport()
    local step = Ports.CELL * scale
    while step < 40 do step = step * 2 end

    local ox = (vx + vw / 2 - camX * scale) % step
    local oy = (vy + vh / 2 - camY * scale) % step
    love.graphics.setColor(Palette.mix(Palette.sand, Palette.woodDark, 0.18))
    for x = ox, vw, step do
        love.graphics.rectangle("fill", math.floor(vx + x), vy, 1, vh)
    end
    for y = oy, vh, step do
        love.graphics.rectangle("fill", vx, math.floor(vy + y), vw, 1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawShip(s)
    local x, y = toScreen(s.x, s.y)
    -- Aguja de rumbo: ploteada, no un sprite, asi que apunta a cualquier lado.
    local dx, dy = Util.headingToVector(s.heading)
    for i = 4, 22, 3 do
        dot(x + dx * i, y + dy * i, 3, Palette.red)
    end
    -- Aro claro debajo: en una carta llena de puntos oscuros, un punto rojo de
    -- cinco pixeles se pierde entre los puertos. El aro es lo que hace que "yo
    -- estoy aqui" se vea de un vistazo.
    dot(x, y, 19, Palette.white)
    dot(x, y, 13, Palette.ink)
    dot(x, y, 7, Palette.red)
end

local function drawCourse(s)
    local port = World.boundPort(s)
    if not port then return end
    local x0, y0 = toScreen(s.x, s.y)
    local x1, y1 = toScreen(port.x, port.y)
    local steps = math.max(2, math.floor(Util.dist(x0, y0, x1, y1) / 8))
    for i = 0, steps do
        local t = i / steps
        dot(Util.lerp(x0, x1, t), Util.lerp(y0, y1, t), 2, Palette.red)
    end
end

local function drawPorts(s)
    local vx, vy, vw, vh = viewport()
    for _, port in ipairs(ports) do
        local x, y = toScreen(port.x, port.y)
        if x > vx - 20 and x < vx + vw + 20 and y > vy - 20 and y < vy + vh + 20 then
            local isHome  = (port.key == s.docked)
            local isBound = (port.key == s.bound)
            local color = isHome and Palette.green
                       or (isBound and Palette.red or Palette.ink)
            -- El tamano del punto es el tamano del puerto: se lee de un
            -- vistazo donde estan los mercados grandes.
            dot(x, y, 3 + port.size * 2, color)
            if port.size == 3 then dot(x, y, 2, Palette.gold) end

            -- Solo el puerto tocado lleva nombre: con cincuenta etiquetas la
            -- carta es ilegible, y el nombre de los demas esta a un toque.
            if selected and port.key == selected.key then
                love.graphics.setColor(Palette.red)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", math.floor(x) - 9, math.floor(y) - 9, 18, 18)
                love.graphics.setColor(1, 1, 1, 1)
                local label = port.name
                local lw = Fonts.tiny:getWidth(label)
                local lx = Util.clamp(x - lw / 2, 8, Constants.GAME_WIDTH - lw - 8)
                UI.rect(lx - 4, y + 12, lw + 8, 20, Palette.sand)
                UI.text(label, lx, y + 14, Palette.ink, Fonts.tiny)
            end
        end
    end
end

--==========================================================================
-- Ciclo de pantalla
--==========================================================================

function Chart.enter()
    local s = state()
    known = 0
    refresh(s)
    selected = World.boundPort(s) or World.dockedPort(s)
    frameAll(s)
    dragging, moved = false, false
end

function Chart.update(dt)
    World.advance(state(), dt)
    Session.update(dt)
    refresh(state())
end

function Chart.press(x, y)
    local _, vy, _, vh = viewport()
    if y >= vy and y <= vy + vh then
        dragging, moved = true, false
        dragX, dragY = x, y
    end
end

function Chart.move(x, y)
    if not dragging then return end
    local dx, dy = x - dragX, y - dragY
    if dx * dx + dy * dy > 36 then moved = true end
    camX = camX - dx / scale
    camY = camY - dy / scale
    dragX, dragY = x, y
end

function Chart.release(x, y)
    if not dragging then return end
    dragging = false
    if moved then return end

    -- Toque limpio: coger el puerto mas cercano, con tolerancia generosa
    -- porque en un movil un punto de cinco pixeles no se acierta.
    local best, bestDist
    for _, port in ipairs(ports) do
        local px, py = toScreen(port.x, port.y)
        local d = Util.dist(x, y, px, py)
        if d < 34 and (not bestDist or d < bestDist) then best, bestDist = port, d end
    end
    selected = best
end

function Chart.keypressed(key)
    if key == "escape" then ScreenManager.switch("voyage") end
end

function Chart.draw()
    local s = state()
    local w, h = Constants.GAME_WIDTH, Constants.GAME_HEIGHT

    -- Papel.
    UI.rect(0, 0, w, h, Palette.sand)
    local vx, vy, vw, vh = viewport()
    drawGrid()
    drawCourse(s)
    drawPorts(s)
    drawShip(s)

    -- Cabecera, encima del papel.
    local head = Constants.SAFE_TOP + 8
    UI.rect(0, 0, w, head + 60, Palette.uiBack)
    UI.text("Carta de marear", 16, head + 6, Palette.gold, Fonts.medium)
    UI.textRight(string.format("%d %s · %d millas por cuadro", #ports,
                               #ports == 1 and "puerto" or "puertos",
                               math.floor(Ports.CELL / 10)),
                 w - 16, head + 40, Palette.dim, Fonts.tiny)

    -- Mandos de la carta, flotando sobre el papel.
    if UI.button(w - 60, vy + 10, 44, 44, "+") then
        scale = Util.clamp(scale * 1.6, MIN_SCALE, MAX_SCALE)
    end
    if UI.button(w - 60, vy + 60, 44, 44, "-") then
        scale = Util.clamp(scale / 1.6, MIN_SCALE, MAX_SCALE)
    end
    if UI.button(w - 60, vy + 110, 44, 44, "", { icon = "icon.anchor" }) then
        centreOnShip(s)
    end
    if UI.button(16, vy + 10, 96, 40, "Todo", { font = Fonts.tiny }) then
        frameAll(s)
    end

    -- Ficha del puerto tocado.
    local cardY = h - Constants.SAFE_BOTTOM - 200
    UI.panel(12, cardY, w - 24, 130)

    if selected then
        local dist = Util.dist(s.x, s.y, selected.x, selected.y)
        local bearing = Util.wrapAngle(math.atan2(selected.x - s.x, -(selected.y - s.y)))
        UI.text(selected.name, 28, cardY + 12, Palette.text, Fonts.small)
        UI.text(string.format("%s · %d millas · demora %s %03d",
                              ({ "una cala", "buen calado", "gran calado" })[selected.size],
                              math.floor(dist / 10),
                              Util.headingName(bearing), Util.headingDegrees(bearing)),
                28, cardY + 42, Palette.dim, Fonts.tiny)

        local bound = (s.bound == selected.key)
        local here  = (s.docked == selected.key)
        if here then
            UI.text("Estas amarrado aqui.", 28, cardY + 70, Palette.green, Fonts.tiny)
        elseif UI.button(28, cardY + 66, w - 56, 48,
                         bound and "Soltar el rumbo" or "Hacer rumbo",
                         { tone = Palette.gold }) then
            if bound then
                World.clearCourse(s)
            else
                World.setCourse(s, selected)
            end
        end
    else
        UI.text("Toca un puerto para hacerle rumbo.", 28, cardY + 12, Palette.dim, Fonts.small)
        UI.text("El timonel corrige solo y el barco atraca al llegar,",
                28, cardY + 46, Palette.dim, Fonts.tiny)
        UI.text("tambien con la app cerrada.", 28, cardY + 66, Palette.dim, Fonts.tiny)
    end

    if UI.button(12, h - Constants.SAFE_BOTTOM - 62, w - 24, 50, "Volver a cubierta",
                 { tone = Palette.gold }) then
        ScreenManager.switch("voyage")
    end
end

return Chart
