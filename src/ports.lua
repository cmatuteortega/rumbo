-- Puertos.
--
-- El mar es infinito y no se guarda en ningun sitio. Esta dividido en celdas
-- de PORT_CELL pixeles y cada celda tiene, o no, un puerto: lo decide un hash
-- de sus coordenadas y de la semilla de la partida. Consecuencias:
--
--   * navegar hacia donde sea siempre acaba encontrando puertos;
--   * la partida guardada son cuatro numeros, no un mapa;
--   * dos jugadores con la misma semilla ven el mismo mundo.
--
-- Lo unico que si se guarda es cuales has descubierto, indexados por la clave
-- de su celda ("3:-1"), porque eso si es historia de tu partida.

local Util = require('src.util')

local Ports = {}

Ports.CELL = 820          -- lado de la celda, en pixeles de mundo
Ports.DENSITY = 0.55      -- fraccion de celdas con puerto
Ports.DOCK_RADIUS = 34    -- a esta distancia se puede atracar

-- Nombres.
--
-- Los tres trozos NO salen de un hash: cada uno indexa su lista por el resto
-- de una coordenada, asi que el nombre es una funcion periodica de la celda y
-- el periodo esta bajo control. Con listas de 14, 30 y 11 (primas entre si en
-- lo que importa), dos puertos solo comparten nombre si estan a 14 celdas en x
-- Y 30 en y Y el distintivo tambien cae — mas de once mil pixeles de mundo
-- entre ellos, en esquinas opuestas de cualquier carta.
--
-- Un hash normal no valia: con 8 x 16 = 128 nombres, cuarenta puertos
-- descubiertos colisionaban casi seguro (paradoja del cumpleanos), y en la
-- carta de marear salian dos "Puerto de Anclas" sin manera de distinguirlos.
-- tests/test_sim.lua barre 40x40 celdas y comprueba que no se repite ninguno.
-- Cada cabecera lleva su genero, porque el adjetivo del medio concuerda con
-- ella: "Cala Larga del Cuervo" pero "Islote Largo del Cuervo". Es la razon de
-- que el adjetivo vaya pegado a la cabecera y no al final — una cola en
-- femenino detras de "Islote" cantaba, y el genero de la cola no se puede
-- deducir de nada.
local HEADS = {
    { "Puerto", "m" }, { "Cala",   "f" }, { "Punta",  "f" }, { "Bahia", "f" },
    { "Isla",   "f" }, { "Faro",   "m" }, { "Rada",   "f" }, { "Abra",  "f" },
    { "Caleta", "f" }, { "Boca",   "f" }, { "Muelle", "m" }, { "Cabo",  "m" },
    { "Islote", "m" }, { "Banco",  "m" },
}

local ADJECTIVES = {
    { "Largo",    "Larga" },    { "Nuevo",    "Nueva" },
    { "Viejo",    "Vieja" },    { "Hondo",    "Honda" },
    { "Roto",     "Rota" },     { "Manso",    "Mansa" },
    { "Negro",    "Negra" },    { "Claro",    "Clara" },
    { "Angosto",  "Angosta" },  { "Alto",     "Alta" },
    { "Quebrado", "Quebrada" },
}

-- Las colas son sintagmas preposicionales a proposito: no concuerdan con
-- nada, asi que valen detras de cualquier cabecera.
local TAILS = {
    "del Norte", "del Sur", "del Este", "de Poniente", "de Sal", "de Niebla",
    "del Cuervo", "de Anclas", "de Gaviotas", "del Sable", "de Brea",
    "de Cobre", "de Cabras", "de Coral", "de la Vieja", "del Naufragio",
    "de Amargura", "del Sordo", "de Barlovento", "de Sotavento", "del Rey",
    "de los Muertos", "de la Sirena", "del Humo", "de Espinas", "del Reloj",
    "de la Cruz", "del Ciervo", "de Marfil", "de Levante",
}

-- Resto no negativo: en Lua el % de un negativo ya lo es, pero dejarlo escrito
-- evita que alguien lo cambie por math.fmod y rompa el hemisferio sur.
local function wrapIndex(v, n)
    return 1 + (v % n)
end

-- Los tres indices son formas lineales de la celda, y de ahi sale la garantia:
-- dos puertos solo comparten nombre si las TRES coinciden a la vez. Resolver
-- ese sistema con estos coeficientes deja la repeticion mas cercana a 49
-- celdas — unas cuatro mil millas, esquinas opuestas de cualquier carta que
-- alguien vaya a mirar. No es una garantia probabilistica como la de un hash:
-- aguanta cualquier numero de puertos descubiertos.
--
-- Los dos ejes van mezclados en las tres formas por una razon concreta que
-- solo se vio jugando: con la cabecera dependiendo solo de cx y la cola solo
-- de cy, las listas se leian como bandas, y un barco navegando en vertical
-- avistaba veinte puertos seguidos llamados todos "Abra algo" (y en
-- horizontal, todos "... del Este"). Los coeficientes estan elegidos entre los
-- que mezclan por el que mas alejaba la repeticion; si se tocan, hay que medir
-- otra vez esa distancia, no basta con que "parezca aleatorio".
local function portName(cx, cy)
    local head = HEADS[wrapIndex(cx + cy * 5, #HEADS)]
    local adj  = ADJECTIVES[wrapIndex(cx * 3 + cy * 7, #ADJECTIVES)]
    local tail = TAILS[wrapIndex(cx * 7 + cy, #TAILS)]
    return head[1] .. " " .. adj[head[2] == "m" and 1 or 2] .. " " .. tail
end
Ports.name = portName

local function key(cx, cy)
    return cx .. ":" .. cy
end
Ports.key = key

-- Puerto de una celda, o nil. La celda (0,0) siempre tiene uno: es el puerto
-- de origen y la partida empieza a la vista de el.
function Ports.get(seed, cx, cy)
    local home = (cx == 0 and cy == 0)
    if not home and Util.hash01(seed + cx * 7919, cy * 104729, 1) > Ports.DENSITY then
        return nil
    end

    local jitterX = Util.hash01(seed, cx, cy * 3) * 0.6 + 0.2
    local jitterY = Util.hash01(seed, cx * 5, cy) * 0.6 + 0.2
    local size = home and 3 or Util.hashInt(1, 3, seed, cx * 11, cy * 13)

    return {
        key  = key(cx, cy),
        cx = cx, cy = cy,
        x = (cx + jitterX) * Ports.CELL,
        y = (cy + jitterY) * Ports.CELL,
        name = home and "Puerto Madre" or portName(cx, cy),
        size = size,
    }
end

-- Puerto a partir de la clave que guarda la partida ("3:-1"), o nil si la
-- clave no es de esta semilla. Lo usan la carta de marear y el rumbo fijado,
-- que guardan claves y no puertos: un puerto es cuatro campos derivados y no
-- tiene sentido meterlo en el archivo de guardado.
function Ports.fromKey(seed, k)
    if type(k) ~= "string" then return nil end
    local cx, cy = k:match("^(-?%d+):(-?%d+)$")
    if not cx then return nil end
    return Ports.get(seed, tonumber(cx), tonumber(cy))
end

-- Todos los puertos cuyo centro cae a menos de radius del punto dado.
function Ports.near(seed, x, y, radius)
    local out = {}
    local c0x = math.floor((x - radius) / Ports.CELL)
    local c1x = math.floor((x + radius) / Ports.CELL)
    local c0y = math.floor((y - radius) / Ports.CELL)
    local c1y = math.floor((y + radius) / Ports.CELL)
    for cy = c0y, c1y do
        for cx = c0x, c1x do
            local p = Ports.get(seed, cx, cy)
            if p and Util.dist(x, y, p.x, p.y) <= radius then
                out[#out + 1] = p
            end
        end
    end
    return out
end

-- Precios del puerto. Varian por puerto y por dia de travesia, asi que
-- volver mas tarde al mismo sitio no es lo mismo, sin guardar un mercado.
-- El tamano del puerto inclina la balanza: los grandes pagan mejor el
-- pescado y venden mas barato lo demas.
function Ports.prices(seed, port, day)
    local a = seed + port.cx * 61 + port.cy * 71 + day * 977
    local swing = function(k) return 0.75 + Util.hash01(a, k, 0) * 0.5 end
    local sizeBonus = 1 + (port.size - 2) * 0.12

    return {
        fish   = math.max(1, math.floor(6 * swing(1) * sizeBonus)),         -- venta
        wood   = math.max(2, math.floor(9 * swing(2) / sizeBonus)),         -- compra
        ration = math.max(1, math.floor(5 * swing(3) / sizeBonus)),         -- compra
        repairPerPoint = math.max(1, math.floor(3 * swing(4) / sizeBonus)), -- compra
    }
end

-- Cuantos candidatos ofrece la taberna. Un puerto grande tiene mas gente.
function Ports.tavernSize(port)
    return 1 + port.size
end

return Ports
