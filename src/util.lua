-- Utilidades puras. Nada aqui toca love, para que la simulacion se pueda
-- correr sin ventana (ver tests/test_sim.lua).

local Util = {}

function Util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Util.lerp(a, b, t) return a + (b - a) * t end
function Util.round(v) return math.floor(v + 0.5) end
function Util.sign(v) return (v > 0 and 1) or (v < 0 and -1) or 0 end

-- Ruido determinista: misma entrada, mismo numero, sin guardar semillas ni
-- tablas. Todo lo variado del juego (olas, nombres, precios de un puerto,
-- grano de un sprite) sale de aqui, asi que el mundo es reproducible y el
-- arte generado es identico en cada arranque.
function Util.hash01(a, b, c)
    local n = (a or 0) * 374761393 + (b or 0) * 668265263 + (c or 0) * 2147483647
    n = n % 2147483647
    n = (n * 1103515245 + 12345) % 2147483647
    n = (n * 1103515245 + 12345) % 2147483647
    return n / 2147483647
end

-- Entero en [lo, hi] a partir del hash.
function Util.hashInt(lo, hi, a, b, c)
    return lo + math.floor(Util.hash01(a, b, c) * (hi - lo + 1)) % (hi - lo + 1)
end

-- Angulos en radianes, 0 = norte, creciendo hacia el este (sentido horario),
-- que es como se lee un rumbo de verdad y como los dibuja la rosa.
local TAU = math.pi * 2
Util.TAU = TAU

function Util.wrapAngle(a)
    a = a % TAU
    if a < 0 then a = a + TAU end
    return a
end

-- Diferencia mas corta entre dos rumbos, en (-pi, pi].
function Util.angleDiff(from, to)
    local d = (to - from + math.pi) % TAU - math.pi
    if d <= -math.pi then d = d + TAU end
    return d
end

function Util.headingToVector(h)
    return math.sin(h), -math.cos(h)
end

-- Nombre del rumbo en la rosa de 8 vientos.
local ROSE = { "N", "NE", "E", "SE", "S", "SO", "O", "NO" }
function Util.headingName(h)
    local i = math.floor(Util.wrapAngle(h) / TAU * 8 + 0.5) % 8
    return ROSE[i + 1]
end

function Util.headingDegrees(h)
    return math.floor(Util.wrapAngle(h) / TAU * 360 + 0.5) % 360
end

function Util.dist(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

-- Numeros cortos para el HUD: 1240 -> "1.2k".
function Util.short(n)
    n = math.floor(n)
    if n < 1000 then return tostring(n) end
    if n < 1000000 then
        local v = n / 1000
        return (v < 10 and string.format("%.1fk", v) or string.format("%dk", math.floor(v)))
    end
    return string.format("%.1fM", n / 1000000)
end

-- Duracion legible: 5400 -> "1h 30m".
function Util.duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%dh %dm", h, m) end
    if m > 0 then return string.format("%dm %ds", m, s) end
    return string.format("%ds", s)
end

return Util
