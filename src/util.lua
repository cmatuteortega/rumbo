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

-- Hash para REJILLAS: cuando lo que se pide son numeros de casillas vecinas, o
-- varios numeros distintos de la misma casilla. `Util.hash01` no sirve para eso,
-- y las dos razones se ven en pantalla:
--
--   * su tercer argumento no hace nada. Entra multiplicado por 2147483647, que
--     es justo el modulo, asi que se anula. Pedirle tres numeros a la misma
--     posicion cambiando solo ese argumento devuelve tres veces el mismo.
--   * y es casi AFIN -- por dentro son dos vueltas de congruencial --, asi que
--     dos posiciones seguidas se llevan un salto casi fijo: medida, la
--     correlacion con el vecino de al lado es del ocho por ciento. Repartido
--     por una rejilla eso no se lee como ruido, se lee como una rampa.
--
-- Para lo que hace `hash01` en el juego -- un puerto, una cara, un precio -- da
-- igual, porque ahi las entradas no son vecinas y no hay dos numeros que salgan
-- del mismo sitio. Y no se toca: cambiarla cambiaria los mundos ya guardados.
--
-- El seno es lo que rompe la linealidad. Sigue siendo funcion pura de la
-- entrada, sin una semilla que guardar, que es lo que pide la regla. Medido en
-- una rejilla de 256x256: media 0,500, correlacion con el vecino de al lado
-- 0,0004, y entre dos `k` distintos 0,008.
function Util.hashGrid(x, y, k)
    local n = math.sin(x * 127.1 + y * 311.7 + (k or 0) * 74.7) * 43758.5453123
    return n - math.floor(n)
end

-- Hash de un texto, para poder meter un nombre en Util.hash01. Es lo que
-- permite derivar de un tripulante la cara con la que se pinta y el compas de
-- su paseo por cubierta sin guardar ni una semilla mas en la partida.
--
-- Multiplica por 131 y no por un primo grande a proposito: el acumulador se
-- queda por debajo de 2^31 y el producto por debajo de 2^38, que es donde un
-- double todavia cuenta enteros exactos. Con un multiplicador de los gordos el
-- hash empieza a redondear y deja de ser el mismo numero en dos maquinas.
function Util.hashText(s)
    local n = 5381
    for i = 1, #s do
        n = (n * 131 + s:byte(i)) % 2147483647
    end
    return n
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
