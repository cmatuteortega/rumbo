-- El mar, y la camara.
--
-- REGLA DE ORO DEL JUEGO: nada se dibuja rotado. Nunca.
--
-- Un sprite girado en tiempo de dibujo muestrea fuera de la rejilla y se
-- deshace, asi que aqui la camara es SOLIDARIA AL BARCO: la proa apunta
-- siempre hacia arriba de la pantalla, el barco se dibuja quieto en el centro
-- y lo que se mueve es el mar. Cambiar de rumbo hace girar el mundo, no el
-- barco.
--
-- Eso obliga a que nada del mundo tenga una orientacion propia que se note:
-- las olas son trazos, las islas son manchas y los puertos son manchas con un
-- fanal. Todos se leen igual desde cualquier demora, asi que se pueden pintar
-- sin girar y nadie lo echa de menos. Si algun dia se anade algo con proa
-- (otro barco), o se dibuja en ocho rumbos, o rompe la regla.
--
-- Ademas, nada del mar se guarda: olas, rachas, islas y escollos son funcion
-- pura de la posicion del mundo y de la semilla (Util.hash01). El mar es
-- infinito y ocupa cero bytes.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Art       = require('src.art')
local Ports     = require('src.ports')

local Sea = {}

Sea.WAVE_CELL    = 15   -- una ola por celda de mundo
Sea.GUST_CELL    = 46
Sea.SCENERY_CELL = 250  -- islas y escollos

-- Estela: solo es adorno, asi que vive aqui y no en el estado guardado.
local wake = {}
local WAKE_MAX = 42
local lastWakeX, lastWakeY

--==========================================================================
-- Camara
--==========================================================================

-- Mundo -> arte. El eje "adelante" del barco es el eje -y de la pantalla.
function Sea.project(state, wx, wy)
    local cx, cy = Constants.shipAnchor()
    local h = state.heading
    local dx, dy = wx - state.x, wy - state.y
    local sinH, cosH = math.sin(h), math.cos(h)
    local along  = dx * sinH - dy * cosH   -- positivo = por la proa
    local across = dx * cosH + dy * sinH   -- positivo = por estribor
    return cx + across, cy - along
end

-- Radio en pixeles de mundo que hay que barrer para cubrir la pantalla desde
-- el barco, sea cual sea el rumbo.
function Sea.viewRadius()
    local w, h = Constants.ART_W, Constants.ART_H
    return math.sqrt(w * w + h * h) / 2 + 24
end

local function onScreen(x, y, margin)
    margin = margin or 24
    return x > -margin and y > -margin
       and x < Constants.ART_W + margin and y < Constants.ART_H + margin
end

--==========================================================================
-- Estela
--==========================================================================

-- La estela nace en el ESPEJO DE POPA, no en el centro del barco: sembrada en
-- state.x/y queda entera debajo del casco y no se ve nunca.
local STERN_OFFSET = 34

function Sea.updateWake(state, dt)
    if state.docked then return end
    local fx, fy = Util.headingToVector(state.heading)
    local sx = state.x - fx * STERN_OFFSET
    local sy = state.y - fy * STERN_OFFSET
    if not lastWakeX or Util.dist(lastWakeX, lastWakeY, sx, sy) > 5 then
        lastWakeX, lastWakeY = sx, sy
        table.insert(wake, 1, { x = sx, y = sy, age = 0 })
        while #wake > WAKE_MAX do table.remove(wake) end
    end
    for i = #wake, 1, -1 do
        wake[i].age = wake[i].age + dt
        if wake[i].age > 6 then table.remove(wake, i) end
    end
end

function Sea.clearWake()
    wake = {}
    lastWakeX, lastWakeY = nil, nil
end

--==========================================================================
-- Dibujo
--==========================================================================

local function drawWaves(state)
    local radius = Sea.viewRadius()
    local cell = Sea.WAVE_CELL
    local c0x = math.floor((state.x - radius) / cell)
    local c1x = math.floor((state.x + radius) / cell)
    local c0y = math.floor((state.y - radius) / cell)
    local c1y = math.floor((state.y + radius) / cell)

    local t = state.time
    for cy = c0y, c1y do
        for cx = c0x, c1x do
            local r1 = Util.hash01(cx, cy, 1)
            local r2 = Util.hash01(cx, cy, 2)
            -- Solo dos de cada tres celdas llevan ola: si no, el mar se ve
            -- como una rejilla y no como agua.
            if r1 > 0.34 then
                local wx = (cx + r1) * cell
                local wy = (cy + r2) * cell
                -- La ola cabecea con el tiempo, cada una en su fase.
                local bob = math.sin(t * 1.4 + (r1 + r2) * 12) * 1.5
                local x, y = Sea.project(state, wx, wy + bob)
                if onScreen(x, y, 10) then
                    Art.draw(r2 > 0.55 and "sea.wave" or "sea.ripple", x, y)
                end
            end
        end
    end
end

local function drawGusts(state)
    local radius = Sea.viewRadius()
    local cell = Sea.GUST_CELL
    local wx0, wy0 = Util.headingToVector(Util.wrapAngle(state.wind.from + math.pi))
    -- Las rachas corren a favor del viento; el modulo las recicla en vez de
    -- irse al infinito.
    local drift = (state.time * 16 * state.wind.strength) % (cell * 3)

    local c0x = math.floor((state.x - radius) / cell)
    local c1x = math.floor((state.x + radius) / cell)
    local c0y = math.floor((state.y - radius) / cell)
    local c1y = math.floor((state.y + radius) / cell)

    for cy = c0y, c1y do
        for cx = c0x, c1x do
            if Util.hash01(cx, cy, 5) > 0.80 then
                local wx = (cx + Util.hash01(cx, cy, 6)) * cell + wx0 * drift
                local wy = (cy + Util.hash01(cx, cy, 7)) * cell + wy0 * drift
                local x, y = Sea.project(state, wx, wy)
                if onScreen(x, y, 12) then
                    Art.draw("sea.gust", x, y)
                end
            end
        end
    end
end

local function drawScenery(state)
    local radius = Sea.viewRadius() + 40
    local cell = Sea.SCENERY_CELL
    local c0x = math.floor((state.x - radius) / cell)
    local c1x = math.floor((state.x + radius) / cell)
    local c0y = math.floor((state.y - radius) / cell)
    local c1y = math.floor((state.y + radius) / cell)

    for cy = c0y, c1y do
        for cx = c0x, c1x do
            local roll = Util.hash01(state.seed + cx, cy, 21)
            if roll > 0.72 then
                local wx = (cx + Util.hash01(cx, cy, 22)) * cell
                local wy = (cy + Util.hash01(cx, cy, 23)) * cell
                local x, y = Sea.project(state, wx, wy)
                if onScreen(x, y, 40) then
                    Art.drawCentered(roll > 0.88 and "sea.island" or "sea.rock", x, y)
                end
            end
        end
    end
end

local function drawPorts(state)
    for _, port in ipairs(Ports.near(state.seed, state.x, state.y, Sea.viewRadius() + 60)) do
        local x, y = Sea.project(state, port.x, port.y)
        if onScreen(x, y, 40) then
            Art.drawCentered("sea.port", x, y)
        end
    end
end

local function drawWake(state)
    for _, p in ipairs(wake) do
        local x, y = Sea.project(state, p.x, p.y)
        if onScreen(x, y, 8) then
            -- La espuma se apaga bajando por la paleta, no con alpha: mezclar
            -- con transparencia inventaria un color que no esta en la paleta.
            local fade = p.age / 6
            love.graphics.setColor(fade < 0.4 and Palette.white
                                or (fade < 0.75 and Palette.foam or Palette.shallow))
            Art.drawCentered("sea.foam", x, y)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Marca de rumbo: una fila de puntos hacia la proa. Como el barco no gira en
-- pantalla, esta guia es lo unico que ensena que se esta virando (el mar gira
-- debajo, pero cuesta leerlo en un movil).
local function drawHeadingGuide(state)
    local cx, cy = Constants.shipAnchor()
    local diff = Util.angleDiff(state.heading, state.target)
    if math.abs(diff) < 0.02 then return end
    local sx = cx + math.sin(diff) * 30
    love.graphics.setColor(Palette.gold)
    for i = 1, 5 do
        local t = i / 5
        local x = Util.lerp(cx, sx, t)
        local y = cy - 34 - i * 5
        love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Sea.draw(state)
    love.graphics.setColor(Palette.sea)
    love.graphics.rectangle("fill", 0, 0, Constants.ART_W, Constants.ART_H)
    love.graphics.setColor(1, 1, 1, 1)

    drawWaves(state)
    drawGusts(state)
    drawScenery(state)
    drawPorts(state)
    drawWake(state)
    drawHeadingGuide(state)
end

return Sea
