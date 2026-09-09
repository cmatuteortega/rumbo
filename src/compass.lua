-- El timon: la rueda con la que se elige rumbo.
--
-- Es lo unico del juego que se dibuja a cualquier angulo, y por eso no es un
-- sprite: las marcas (norte, viento, rumbo pedido) se pintan punto a punto
-- con rectangulos de 1x1, que es la salida legal a la regla de "nada girado"
-- de src/sea.lua. El bisel, que se ve igual desde cualquier rumbo, si es un
-- sprite ("ui.dial") y por tanto lo puedes redibujar tu.
--
-- La rueda gira con el barco: arriba es siempre la proa, igual que el mar.
-- Tocar un punto de la rueda es pedir "quiero la proa ahi", que es la lectura
-- directa de lo que se ve. Segun cae el barco al nuevo rumbo, la marca dorada
-- sube hasta el pico de arriba: eso es la maniobra terminada.
--
-- Va CENTRADO ARRIBA, no en una esquina. La rueda ya lleva dentro las tres
-- cosas que se miran al gobernar (rumbo, viento y rumbo pedido), asi que su
-- sitio esta con el resto de la navegacion y no lejos de ella. Cuesta pulgar:
-- en una esquina de abajo se alcanzaba sin mover la mano y arriba no. El
-- cambio se paga con el barco, que baja al centro de la pantalla porque ya no
-- hay que dejarle libre la esquina de estribor.
--
-- Cuelga SOBRE EL MAR, sin panel debajo: los dos bloques del HUD estan a los
-- lados y entre ellos no hay nada que tapar. El MARGIN generoso es lo que lo
-- separa del borde de la pantalla y lo que deja ver mar por encima; si la
-- rueda subiera hasta arriba, el hueco entre los dos bloques se cerraria y
-- volveria a parecer una franja maciza.
--
-- Este centro es ademas la referencia del HUD: `src/hud.lua` lee
-- `Compass.center()` y `Compass.RADIUS` para saber donde escribir las lecturas
-- de navegacion y donde acaba la zona de interfaz de arriba.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Art       = require('src.art')
local UI        = require('src.ui')

local Compass = {}

Compass.RADIUS = 66     -- radio tocable, en pixeles virtuales
Compass.MARGIN = 56     -- aire entre el margen seguro de arriba y el bisel

function Compass.center()
    return math.floor(Constants.GAME_WIDTH / 2),
           math.floor(Constants.SAFE_TOP + Compass.MARGIN + Compass.RADIUS)
end

function Compass.contains(x, y)
    local cx, cy = Compass.center()
    local dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= (Compass.RADIUS + 8) ^ 2
end

-- Convierte un punto de la pantalla en el rumbo que pide. `heading` es el
-- rumbo actual porque la rueda esta orientada a la proa.
function Compass.headingAt(state, x, y)
    local cx, cy = Compass.center()
    local dx, dy = x - cx, y - cy
    if dx * dx + dy * dy < 100 then return nil end   -- centro muerto
    local screenAngle = math.atan2(dx, -dy)          -- 0 = arriba = proa
    return Util.wrapAngle(state.heading + screenAngle)
end

local function plot(cx, cy, angle, radius, color, size)
    size = size or 1
    local x = cx + math.sin(angle) * radius
    local y = cy - math.cos(angle) * radius
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", math.floor(x - size / 2), math.floor(y - size / 2), size, size)
    love.graphics.setColor(1, 1, 1, 1)
end

local function needle(cx, cy, angle, from, to, color, size)
    local steps = math.max(2, math.floor((to - from) / 3))
    for i = 0, steps do
        plot(cx, cy, angle, Util.lerp(from, to, i / steps), color, size)
    end
end

local LETTERS = { [0] = "N", "E", "S", "O" }

function Compass.draw(state)
    local cx, cy = Compass.center()

    -- Bisel.
    local w, h = Art.size("ui.dial")
    local scale = math.floor((Compass.RADIUS * 2) / w)
    love.graphics.draw(Art.get("ui.dial"), math.floor(cx - w * scale / 2),
                       math.floor(cy - h * scale / 2), 0, scale, scale)

    -- Los cuatro rumbos cardinales, girados respecto a la proa.
    for i = 0, 3 do
        local worldAngle = i * math.pi / 2
        local rel = Util.wrapAngle(worldAngle - state.heading)
        local r = Compass.RADIUS - 20
        local x = cx + math.sin(rel) * r
        local y = cy - math.cos(rel) * r
        local color = (i == 0) and Palette.gold or Palette.dim
        UI.textCenter(LETTERS[i], x, y - Fonts.tiny:getHeight() / 2, color, Fonts.tiny)
    end

    -- Viento: la aguja apunta a DE DONDE sopla, con la cola a favor. El grosor
    -- de la marca crece con la fuerza, que es la unica lectura que hace falta.
    local windRel = Util.wrapAngle(state.wind.from - state.heading)
    local thickness = state.wind.strength > 0.85 and 3 or 2
    needle(cx, cy, windRel, 14, Compass.RADIUS - 26, Palette.foam, thickness)
    plot(cx, cy, windRel, Compass.RADIUS - 24, Palette.white, 4)

    -- Rumbo pedido.
    local targetRel = Util.angleDiff(state.heading, state.target)
    needle(cx, cy, targetRel, Compass.RADIUS - 22, Compass.RADIUS - 8, Palette.gold, 3)

    -- Proa: fija arriba, porque el barco no gira en pantalla.
    plot(cx, cy, 0, Compass.RADIUS - 4, Palette.white, 5)

    -- Lectura numerica en el centro.
    local label = string.format("%s %03d", Util.headingName(state.heading),
                                Util.headingDegrees(state.heading))
    UI.textCenter(label, cx, cy - Fonts.tiny:getHeight() / 2, Palette.text, Fonts.tiny)
end

return Compass
