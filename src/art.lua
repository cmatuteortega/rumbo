-- Registro de sprites.
--
-- Cada sprite tiene un id, un tamano en pixeles de arte y un generador. Al
-- arrancar, Art busca primero un PNG en assets/ con el nombre del sprite; si
-- existe lo carga tal cual y el generador no se ejecuta. Ese es todo el
-- contrato para sustituir el arte provisional por el tuyo:
--
--     assets/ship2.png  ->  gana sobre el generador de "ship.hull"
--
-- El PNG no tiene por que medir exactamente lo declarado (el juego usa el
-- tamano real de la imagen), pero si se desvia mucho descuadra los anclajes
-- de cubierta de src/stations.lua, que son fracciones del lienzo del barco.
--
-- Un sprite puede registrarse SIN generador. Entonces es una capa opcional:
-- si el PNG no esta, la capa no existe y quien la dibuja se calla
-- (Art.drawIfAny). Es lo que permite tener sitio reservado para arte que
-- todavia no se usa -- los canones -- sin inventarse una version procedural
-- que nadie ha pedido.
--
-- Los generadores son deterministas: toda su variacion sale de Util.hash01,
-- asi que el mar tiene siempre las mismas olas y un sprite regenerado es
-- identico al de la ejecucion anterior. Sin semillas guardadas.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Stations  = require('src.stations')
local Crew      = require('src.crew')

local Art = {}

Art.images = {}   -- id -> love Image
Art.sizes  = {}   -- id -> {w = , h = }
Art.list   = {}   -- orden de carga, para la barra de progreso del arranque
Art.fromFile = {} -- id -> true si vino de assets/
Art.absent = {}   -- id -> true si es capa opcional y no habia PNG

--==========================================================================
-- Lienzo de pixeles
--==========================================================================

local Canvas = {}
Canvas.__index = Canvas

local function newCanvas(w, h)
    return setmetatable({
        w = w, h = h,
        data = love.image.newImageData(w, h),
    }, Canvas)
end

function Canvas:px(x, y, c, a)
    x, y = math.floor(x), math.floor(y)
    if x < 0 or y < 0 or x >= self.w or y >= self.h then return end
    self.data:setPixel(x, y, c[1], c[2], c[3], a or 1)
end

function Canvas:rect(x, y, w, h, c)
    for iy = y, y + h - 1 do
        for ix = x, x + w - 1 do self:px(ix, iy, c) end
    end
end

function Canvas:frame(x, y, w, h, c)
    self:hline(y, x, x + w - 1, c)
    self:hline(y + h - 1, x, x + w - 1, c)
    self:vline(x, y, y + h - 1, c)
    self:vline(x + w - 1, y, y + h - 1, c)
end

function Canvas:hline(y, x0, x1, c)
    if x1 < x0 then x0, x1 = x1, x0 end
    for x = x0, x1 do self:px(x, y, c) end
end

function Canvas:vline(x, y0, y1, c)
    if y1 < y0 then y0, y1 = y1, y0 end
    for y = y0, y1 do self:px(x, y, c) end
end

-- Bresenham. No usamos love.graphics.line en ningun sitio: interpola.
function Canvas:line(x0, y0, x1, y1, c)
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
    local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
        self:px(x0, y0, c)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy; x0 = x0 + sx end
        if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
end

-- Disco relleno. rx/ry distintos dan una elipse; es lo que usan el casco de
-- los iconos, las islas y las cabezas de la tripulacion.
function Canvas:disc(cx, cy, rx, ry, c)
    ry = ry or rx
    for y = math.floor(cy - ry), math.ceil(cy + ry) do
        for x = math.floor(cx - rx), math.ceil(cx + rx) do
            local nx = (x + 0.5 - cx) / (rx + 0.5)
            local ny = (y + 0.5 - cy) / (ry + 0.5)
            if nx * nx + ny * ny <= 1 then self:px(x, y, c) end
        end
    end
end

function Canvas:ring(cx, cy, rx, ry, c)
    ry = ry or rx
    for y = math.floor(cy - ry), math.ceil(cy + ry) do
        for x = math.floor(cx - rx), math.ceil(cx + rx) do
            local nx = (x + 0.5 - cx) / (rx + 0.5)
            local ny = (y + 0.5 - cy) / (ry + 0.5)
            local d = nx * nx + ny * ny
            if d <= 1 and d > 0.45 then self:px(x, y, c) end
        end
    end
end

function Canvas:image()
    local img = love.graphics.newImage(self.data)
    img:setFilter('nearest', 'nearest')
    return img
end

--==========================================================================
-- Generadores
--==========================================================================

-- Semiancho del casco en la fila t (0 = roda, 1 = espejo de popa).
--
-- Son dos tramos con la manga en BOW (el 45% de la eslora): delante, una cuna
-- de exponente mayor que uno, que es lo que hace la proa afilada en vez de
-- redonda; detras, una parabola suave que deja el espejo de popa a poco mas
-- de la mitad de la manga. Una sola formula para todo el casco daba un huevo.
--
-- Es la unica funcion de la que dependen los anclajes de cubierta, asi que si
-- se cambia la silueta hay que mirar src/stations.lua.
local BOW = 0.42     -- donde esta la manga, en fraccion de eslora
local STERN = 0.94   -- a partir de aqui el espejo de popa es recto
local function hullHalf(t, maxHalf)
    if t <= BOW then
        return maxHalf * (t / BOW) ^ 1.6
    end
    -- El espejo de popa se corta plano: un casco que termina en punta por los
    -- dos lados parece una hoja, no un barco.
    local k = (math.min(t, STERN) - BOW) / (1 - BOW)
    return maxHalf * (1 - 0.55 * k * k)
end
Art.hullHalf = hullHalf

-- El barco no es un sprite: es una PILA de capas registradas sobre el mismo
-- lienzo de SHIP_W x SHIP_H. Casco, velas, cocina, redes y bodega miden todas
-- lo mismo y el arte viene ya casado dentro, asi que se dibujan las cinco en
-- el mismo origen y encajan sin un solo offset a mano. El orden de dibujo
-- esta en drawShip() de src/screens/voyage.lua.
local SHIP_W, SHIP_H = 80, 96

-- Donde cae el CASCO dentro de ese lienzo, en fraccion del lienzo. Sobra aire
-- alrededor a proposito: las vergas asoman por fuera de la borda y las bocas
-- de los canones tambien, y con el casco llenando el lienzo no cabrian.
--
-- Estan medidas sobre assets/ship2.png, y son fracciones y no pixeles para
-- que un PNG de otro tamano siga cuadrando. Lo que NO sobrevive es cambiar el
-- aire: si redibujas el casco con otro margen, vuelve a medir esto.
Art.HULL_BOX = { x = 16 / 80, y = 5 / 96, w = 48 / 80, h = 82 / 96 }

-- La caja en pixeles enteros para un lienzo de w x h.
local function hullBox(w, h)
    local b = Art.HULL_BOX
    return math.floor(w * b.x + 0.5), math.floor(h * b.y + 0.5),
           math.floor(w * b.w + 0.5), math.floor(h * b.h + 0.5)
end

-- Publica porque src/deck.lua pasea a la tripulacion por el casco y necesita
-- la misma caja con la que se dibujo, no una medida a ojo.
Art.hullRect = hullBox

local gen = {}

function gen.shipHull(w, h)
    local c = newCanvas(w, h)
    local hx, hy, hw, hh = hullBox(w, h)
    local cx = hx + (hw - 1) / 2

    -- Todo se cuenta en filas del casco (i), no del lienzo, y se baja a la
    -- caja al escribir. Asi la silueta es la misma con cualquier margen.
    local function halfAt(i) return hullHalf(i / (hh - 1), (hw - 1) / 2) end

    for i = 0, hh - 1 do
        local half = halfAt(i)
        if half >= 0.5 then
            local x0, x1 = math.floor(cx - half + 0.5), math.floor(cx + half + 0.5)
            -- Obra muerta: borde oscuro, regala interior de cubierta.
            c:hline(hy + i, x0, x1, Palette.woodDark)
            c:hline(hy + i, x0 + 1, x1 - 1, Palette.wood)
            if x1 - x0 > 5 then
                c:hline(hy + i, x0 + 2, x1 - 2, Palette.deck)
            end
        end
    end

    -- Tablazon: vetas verticales alternas para que la cubierta no sea plana.
    for i = 0, hh - 1 do
        local half = halfAt(i)
        for x = math.floor(cx - half + 2), math.ceil(cx + half - 2) do
            if (x % 3) == 0 and Util.hash01(x, hy + i, 7) > 0.35 then
                c:px(x, hy + i, Palette.deckLite)
            end
        end
    end

    -- Bauprés: donde el casco ya no llega a un pixel de ancho queda el palo
    -- asomando, que es lo que dice de un vistazo por donde va la proa.
    for i = 0, math.floor(hh * 0.12) do
        if halfAt(i) < 0.5 then c:px(cx, hy + i, Palette.woodDark) end
    end

    -- Crujia.
    c:vline(math.floor(cx), hy + math.floor(hh * 0.12), hy + hh - 4, Palette.woodLite)

    -- Castillo de proa y toldilla: dos bloques mas claros, estrechos, para que
    -- se lea que hay dos cubiertas altas y no una mancha.
    local function castle(t0, t1)
        for i = math.floor(hh * t0), math.floor(hh * t1) do
            local half = halfAt(i) * 0.55
            if half >= 1 then
                c:hline(hy + i, math.floor(cx - half), math.ceil(cx + half), Palette.deckLite)
            end
        end
    end
    castle(0.16, 0.22)
    castle(0.80, 0.90)

    -- La escotilla ya no se pinta aqui: es "ship.hold", su propia capa, para
    -- que la trampilla y el punto tocable de la bodega no puedan separarse.
    return c
end

-- Escotilla de bodega.
--
-- Es la unica capa de cubierta que se genera. La cocina y las redes son
-- opcionales -- si falta el PNG no hay nada ahi y se acabo --, pero la bodega
-- es un puesto tocable en medio de la cubierta y quedaria un aro dorado
-- flotando sobre tablas: hasta que exista assets/bodega1.png, esta trampilla.
--
-- Se planta EN el punto del puesto "hold" de src/stations.lua, con la misma
-- cuenta que Ship.deckPoint. Mover el ancla mueve la trampilla; no hay dos
-- sitios que ajustar.
function gen.shipHold(w, h)
    local c = newCanvas(w, h)
    local def = Stations.byId.hold
    local cx, cy = math.floor(def.deckX * w), math.floor(def.deckY * h)
    local rx = math.max(3, math.floor(w * 0.075))
    local ry = math.max(4, math.floor(h * 0.052))

    c:rect(cx - rx, cy - ry, rx * 2 + 1, ry * 2 + 1, Palette.woodDark)
    c:frame(cx - rx, cy - ry, rx * 2 + 1, ry * 2 + 1, Palette.woodLite)
    -- Enjaretado: barrotes alternos. Es lo que distingue una escotilla de un
    -- parche de cubierta oscuro.
    for x = cx - rx + 2, cx + rx - 2, 2 do
        c:vline(x, cy - ry + 1, cy + ry - 1, Palette.wood)
    end
    return c
end

-- Velamen: un solo palo en la crujia, la verga cruzada bien a proa y el trapo
-- abombado a los dos lados.
--
-- Las medidas salen de MEDIR assets/sails1.png, y eso no es pereza: el trapo
-- largado viene de archivo y el arrizado se genera aqui, asi que si el palo no
-- cae en el mismo sitio tomar rizos parece cambiar de barco. El dia que exista
-- assets/sails_reef1.png esta funcion deja de dibujarse y da igual.
local function sails(w, h, reefed)
    local c = newCanvas(w, h)
    local cx = math.floor((w - 1) / 2)
    local top   = math.floor(h * 0.135)   -- perilla
    local yard  = math.floor(h * 0.188)   -- verga
    local rail  = math.floor(h * 0.521)   -- fogonadura
    local heel  = math.floor(h * 0.573)   -- coz del palo
    local thick = math.max(1, math.floor(w * 0.031))

    -- El trapo visto desde arriba es una lente: la verga por el eje y el pano
    -- panzudo a los dos lados. Arrizar no mueve el palo ni la verga de sitio,
    -- solo recoge y aplana la lente, que es lo que hace que el boton de rizos
    -- se lea como una maniobra.
    -- La verga NO se acorta al arrizar: lo que se recoge es el trapo. Por eso
    -- la envergadura es la misma con los dos aparejos y lo unico que cambia es
    -- la lente; una verga que se encoge parece un barco distinto.
    local arm    = math.floor(w * 0.375)
    local spread = math.floor(arm * (reefed and 0.55 or 1))
    local belly  = math.floor(h * (reefed and 0.021 or 0.047))
    local mid    = yard + belly
    c:disc(cx, mid, spread, belly, Palette.sail)
    -- Sombra a sotavento: una fila, no un degradado.
    c:hline(mid + belly, cx - spread + 1, cx + spread - 1, Palette.sailShade)
    c:hline(mid, cx - arm, cx + arm, Palette.woodDark)

    -- El palo va por ENCIMA del trapo: es lo que se ve desde la cofa.
    c:rect(cx - thick, top, thick * 2 + 1, heel - top + 1, Palette.wood)
    c:vline(cx - thick, top, heel, Palette.woodDark)
    c:vline(cx + thick, top, heel, Palette.woodDark)
    c:disc(cx, top, thick + 1, thick + 1, Palette.woodDark)
    -- Fogonadura: el ensanche donde el palo entra en cubierta. Sin el, el palo
    -- parece pegado encima en vez de plantado.
    c:hline(rail, cx - thick * 2 - 1, cx + thick * 2 + 1, Palette.woodLite)
    c:hline(rail + 1, cx - thick * 2, cx + thick * 2, Palette.woodDark)
    return c
end

function gen.shipSailsFull(w, h) return sails(w, h, false) end
function gen.shipSailsReef(w, h) return sails(w, h, true) end

-- Mar: crestas orientadas, rachas, espuma y bigote de proa.
--
-- Las crestas son lo unico del mundo que TIENE una orientacion: el viento
-- sopla hacia algun sitio y el mar se peina en su contra. Como la camara gira
-- con el barco, la misma cresta se ve a un angulo distinto en cada rumbo, y la
-- salida es la que manda la regla 1: no rotar en el dibujo, sino tener el trazo
-- ya pintado en SEA_DIRS orientaciones y elegir la mas cercana. La cuenta esta
-- en el registro, al final del archivo.

-- Un trazo de cresta, centrado en el lienzo y a un angulo dado.
--
-- Tiene GROSOR y tiene sombra, y las dos cosas costaron una tarde. Con un
-- trazo de un pixel y la sombra puesta debajo a secas, una cresta vertical se
-- encontraba la sombra en su propia linea y salia un palo fino; una pantalla
-- de palos finos, todos iguales de largos y todos separados por agua lisa, no
-- se lee como mar: se lee como LLUVIA, y con el viento por el traves --que es
-- cuando las crestas caen verticales en pantalla-- se leia como un chaparron.
--
-- Lo que lo arregla es que la marca sea un trozo de agua y no una raya: dos
-- filas de cresta y una de seno oscuro al lado, asi que tiene cara iluminada y
-- valle. El lado se elige con la componente hacia abajo del perpendicular, no
-- con el angulo de la cresta: asi el cielo alumbra siempre desde arriba y
-- virar no cambia la iluminacion del mar, que es justo lo que delata a un
-- sprite girado.
local function stroke(c, angle, len, color, shade, cap)
    local cx, cy = (c.w - 1) / 2, (c.h - 1) / 2
    local dx, dy = math.cos(angle), math.sin(angle)
    local hx, hy = dx * len / 2, dy * len / 2
    -- Perpendicular "hacia abajo": el lado de la sombra.
    local px, py = -dy, dx
    if py < 0 then px, py = -px, -py end
    px, py = Util.round(px), Util.round(py)
    if shade then
        c:line(cx - hx + px, cy - hy + py, cx + hx + px, cy + hy + py, shade)
    end
    c:line(cx - hx, cy - hy, cx + hx, cy + hy, color)
    if shade then
        -- La segunda fila va del lado de la luz. Es lo que le da cuerpo.
        c:line(cx - hx - px, cy - hy - py, cx + hx - px, cy + hy - py, color)
    end
    if cap then
        -- La cabeza rompiente no va en el centro exacto: repetida en todas las
        -- crestas del mar, un pico centrado se lee como una costura.
        local t = 0.20
        c:px(cx + hx * t, cy + hy * t, cap)
        c:px(cx + hx * t - dx, cy + hy * t - dy, cap)
        c:px(cx + hx * t - px, cy + hy * t - py, cap)
    end
end

function gen.crestRipple(w, h, angle)
    -- Rizo: el grano del agua. Un trazo de un pixel del color del bajio, sin
    -- espuma y sin sombra -- el mar en calma es esto y nada mas, y con viento
    -- fresco es lo que llena el hueco entre ola y ola.
    local c = newCanvas(w, h)
    stroke(c, angle, w - 2, Palette.shallow)
    return c
end

-- Ola corriente: NO lleva espuma. Es agua somera sobre agua honda, y por eso
-- casi no contrasta. Fue lo ultimo que se entendio: mientras la ola normal
-- era clara, el mar entero era un campo de marcas brillantes iguales, y da
-- igual como de cortas fueran. El blanco tiene que ser raro para que signifique
-- algo -- solo rompen las de sea.swell.
function gen.crestWave(w, h, angle)
    local c = newCanvas(w, h)
    stroke(c, angle, w - 2, Palette.shallow, Palette.deep)
    return c
end

function gen.crestSwell(w, h, angle)
    -- Ola hecha: la unica que rompe, y por eso la unica que lleva blanco. Sale
    -- solo con viento fresco y en las manchas de mar picado (ver src/sea.lua).
    local c = newCanvas(w, h)
    stroke(c, angle, w - 2, Palette.foam, Palette.deep, Palette.white)
    return c
end

function gen.gustStreak(w, h, angle)
    -- Racha: a diferencia de la cresta, corre A FAVOR del viento y no contra
    -- el, asi que en pantalla cruza las olas en angulo recto. Va en tres
    -- tramos porque una raya entera de trece pixeles se lee como un cable.
    local c = newCanvas(w, h)
    local cx, cy = (c.w - 1) / 2, (c.h - 1) / 2
    local dx, dy = math.cos(angle), math.sin(angle)
    local len = w - 2
    local segs = { { -0.50, -0.30 }, { -0.06, 0.16 }, { 0.34, 0.50 } }
    for _, s in ipairs(segs) do
        c:line(cx + dx * len * s[1], cy + dy * len * s[1],
               cx + dx * len * s[2], cy + dy * len * s[2], Palette.foam)
    end
    return c
end

function gen.drop(w, h)
    -- La gota que la roda dispara a sotavento. Es lo mas pequeno del mar a
    -- proposito: lo que se despega del casco se deshace.
    local c = newCanvas(w, h)
    c:rect(0, 0, w, h, Palette.white)
    return c
end

-- Bigote de proa: las dos alas de agua que la roda levanta al abrirse paso.
--
-- Es lo unico del mar que se dibuja pegado a la pantalla y no al mundo, y es
-- legal por la misma razon que el barco: la proa apunta SIEMPRE arriba, asi
-- que el bigote no tiene angulo que elegir. Hay tres tamanos y la velocidad
-- decide cual; sin el, un barco parado y uno a cinco nudos se ven igual.
local function bowWave(w, h)
    local c = newCanvas(w, h)
    local cx = (w - 1) / 2
    c:line(cx, 1, 0, h - 1, Palette.foam)
    c:line(cx, 1, w - 1, h - 1, Palette.foam)
    c:line(cx, 0, 0, h - 2, Palette.white)
    c:line(cx, 0, w - 1, h - 2, Palette.white)
    return c
end

-- Un solo generador para los tres: el tamano lo pone el registro.
function gen.bowWave(w, h) return bowWave(w, h) end

-- Arco de estela: el MISMO bigote, pero para la popa y en un solo trazo.
--
-- La estela de un barco vista desde arriba no es una fila de puntos: son las
-- crestas transversales, arcos como el de la roda que van quedando atras y
-- abriendose. Asi que el bigote no se copio, se ESTIRO: la misma uve, en una
-- escalera de tamanos, sembrada por el espejo de popa.
--
-- Va en blanco puro y de un pixel a proposito. En pantalla se tine con
-- Palette.white / foam / shallow segun se deshace (foamColor en src/sea.lua),
-- y multiplicar por blanco devuelve el color de la paleta EXACTO -- que es lo
-- que permite apagar la espuma sin inventar un color que no esta en ella. Con
-- el arco a dos tonos como el bigote, la tinta daria un tercer color.
local function wakeArc(w, h)
    local c = newCanvas(w, h)
    local cx = (w - 1) / 2
    c:line(cx, 0, 0, h - 1, Palette.white)
    c:line(cx, 0, w - 1, h - 1, Palette.white)
    return c
end

function gen.wakeArc(w, h) return wakeArc(w, h) end

-- Mancha de calma: agua honda y lisa, sin rizos encima. El mar de un solo azul
-- es lo que hace que un fondo plano se lea como papel pintado; estas manchas
-- son la variacion grande, la que se ve venir desde lejos. Van difuminadas al
-- borde -- una fila si y otra no -- porque un disco de canto duro a este grano
-- de pixel se lee como una isla sumergida.
local function calmPatch(w, h, salt)
    local c = newCanvas(w, h)
    local cx, cy = (w - 1) / 2, (h - 1) / 2
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            -- Radio irregular: un ovalo perfecto se reconoce repetido.
            local ang = math.atan2(y - cy, x - cx)
            local wob = 0.80 + 0.30 * Util.hash01(math.floor(ang * 4), salt, 3)
            local nx = (x - cx) / ((w / 2) * wob)
            local ny = (y - cy) / ((h / 2) * wob)
            local d = nx * nx + ny * ny
            -- Todo tramado y nada macizo: un disco relleno de agua honda se
            -- lee como un agujero, o como una isla sumergida. Tramado, el ojo
            -- lo mezcla y sale un mar mas oscuro, que es lo que se queria.
            if d <= 0.60 then
                if (x + y) % 2 == 0 then c:px(x, y, Palette.deep) end
            elseif d <= 1 and (x + y) % 4 == 0 then
                c:px(x, y, Palette.deep)
            end
        end
    end
    return c
end

function gen.calmBig(w, h)   return calmPatch(w, h, 1) end
function gen.calmSmall(w, h) return calmPatch(w, h, 2) end

function gen.island(w, h)
    local c = newCanvas(w, h)
    local cx, cy = (w - 1) / 2, (h - 1) / 2
    -- Contorno irregular: radio modulado por hash en 16 sectores, interpolado.
    local sectors = 16
    local radii = {}
    for i = 0, sectors - 1 do
        radii[i] = 0.62 + 0.30 * Util.hash01(i, 11, 3)
    end
    local function radiusAt(ang)
        local f = (ang / Util.TAU) * sectors
        local i0 = math.floor(f) % sectors
        local i1 = (i0 + 1) % sectors
        local t = f - math.floor(f)
        return Util.lerp(radii[i0], radii[i1], t)
    end

    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local dx, dy = (x - cx) / (w / 2), (y - cy) / (h / 2)
            local ang = Util.wrapAngle(math.atan2(dy, dx))
            local d = math.sqrt(dx * dx + dy * dy)
            local r = radiusAt(ang)
            if d <= r then
                if d > r - 0.16 then
                    c:px(x, y, Palette.sand)
                elseif d > r - 0.30 then
                    c:px(x, y, Palette.mix(Palette.sand, Palette.grass, 0.5))
                else
                    c:px(x, y, Palette.grass)
                end
            elseif d <= r + 0.10 then
                c:px(x, y, Palette.shallow)
            end
        end
    end

    -- Cuatro rocas fijas por hash, para que la isla no sea un huevo liso.
    for i = 1, 4 do
        local a = Util.hash01(i, 5, 1) * Util.TAU
        local rr = 0.25 + 0.35 * Util.hash01(i, 6, 2)
        c:disc(cx + math.cos(a) * rr * w / 2, cy + math.sin(a) * rr * h / 2, 1, 1, Palette.rock)
    end
    return c
end

function gen.rock(w, h)
    local c = newCanvas(w, h)
    c:disc((w - 1) / 2, (h - 1) / 2, (w - 1) / 2, (h - 1) / 2 - 0.5, Palette.rock)
    c:hline(math.floor(h / 2) - 1, 1, w - 2, Palette.mix(Palette.rock, Palette.white, 0.25))
    return c
end

function gen.port(w, h)
    local c = newCanvas(w, h)
    -- Espigon: un muelle de madera con dos casetas y un fanal.
    c:disc((w - 1) / 2, (h - 1) / 2 + 2, w / 2 - 1, h / 2 - 3, Palette.sand)
    c:rect(math.floor(w / 2) - 2, 2, 4, h - 6, Palette.wood)
    for y = 2, h - 5, 3 do
        c:hline(y, math.floor(w / 2) - 3, math.floor(w / 2) + 3, Palette.woodDark)
    end
    -- Casetas.
    c:rect(2, h - 12, 8, 7, Palette.woodLite)
    c:frame(2, h - 12, 8, 7, Palette.woodDark)
    c:rect(w - 11, h - 10, 8, 6, Palette.woodLite)
    c:frame(w - 11, h - 10, 8, 6, Palette.woodDark)
    -- Fanal: lo unico dorado del sprite, para localizarlo de un vistazo.
    c:rect(math.floor(w / 2) - 1, 0, 3, 3, Palette.gold)
    return c
end

--== Tripulacion (8x8) =====================================================

-- La tripulacion es una RESERVA de caras, no un monigote por gremio.
--
-- Antes habia siete figuras, una por puesto, y el color decia el oficio. Con
-- caras dibujadas eso sobra y estorba: el oficio ya se lee por donde esta
-- plantado el tripulante en cubierta, y lo que no se leia era QUIEN es cada
-- uno. Ahora cada tripulante saca su cara del hash de su nombre
-- (Crew.face), asi que el gaviero de tu partida tiene siempre la misma cara y
-- no cambia al mudarlo de puesto.
--
-- El sitio de estas es assets/crew_pjNN.png; lo de aqui abajo es el respaldo
-- para cuando assets/ esta vacio, que es un contrato del proyecto: el juego
-- tiene que arrancar sin un solo PNG. Se parece a lo que sustituye, no lo
-- imita: media docena de gorros y chaquetones combinados dan catorce siluetas
-- distinguibles a este tamano, que es todo lo que hace falta.
local COATS = {
    Palette.wood, Palette.rope, Palette.woodDark, Palette.sailShade,
    Palette.rock, Palette.red, Palette.green, Palette.deep,
}
local CAPS = {
    Palette.ink, Palette.red, Palette.gold, Palette.sail,
    Palette.shallow, Palette.woodLite,
}

-- Tripulante en cenital: hombros, cabeza y gorro. 8x8.
local function crewFace(index)
    local coat = COATS[(index - 1) % #COATS + 1]
    local cap  = CAPS[(index * 3 - 1) % #CAPS + 1]
    return function(w, h)
        local c = newCanvas(w, h)
        local cx = (w - 1) / 2
        c:disc(cx, h - 3, 3, 2.5, coat)                   -- hombros
        c:px(cx - 3, h - 2, Palette.ink)                  -- manos
        c:px(cx + 3, h - 2, Palette.ink)
        c:disc(cx, 2.5, 2, 2, Palette.skin)               -- cabeza desde arriba
        c:hline(1, cx - 2, cx + 2, cap)                   -- gorro
        c:px(cx, 0, cap)
        return c
    end
end

--== Iconos (11x11) ========================================================

function gen.iconCoin(w, h)
    local c = newCanvas(w, h)
    local r = (w - 1) / 2
    c:disc(r, r, r, r, Palette.ink)
    c:disc(r, r, r - 1, r - 1, Palette.gold)
    c:ring(r, r, r - 2.5, r - 2.5, Palette.mix(Palette.gold, Palette.white, 0.45))
    return c
end

function gen.iconFish(w, h)
    local c = newCanvas(w, h)
    local cy = (h - 1) / 2
    c:disc(w / 2 - 0.5, cy, w / 2 - 1.5, h / 2 - 2.5, Palette.shallow)
    c:disc(w / 2 - 0.5, cy - 1, w / 2 - 2.5, h / 2 - 3.5, Palette.foam)
    -- Cola.
    c:line(1, cy, 1, cy - 2, Palette.shallow)
    c:line(1, cy, 1, cy + 2, Palette.shallow)
    c:line(1, cy - 2, 3, cy, Palette.shallow)
    c:line(1, cy + 2, 3, cy, Palette.shallow)
    c:px(w - 3, cy - 1, Palette.ink)
    return c
end

function gen.iconWood(w, h)
    local c = newCanvas(w, h)
    for i = 0, 1 do
        local y = 2 + i * 4
        c:rect(1, y, w - 2, 3, Palette.wood)
        c:hline(y, 1, w - 2, Palette.woodDark)
        c:hline(y + 2, 1, w - 2, Palette.woodDark)
        c:px(2, y + 1, Palette.woodLite)
        c:px(w - 3, y + 1, Palette.woodLite)
    end
    return c
end

function gen.iconRation(w, h)
    local c = newCanvas(w, h)
    c:rect(1, 2, w - 2, h - 4, Palette.woodLite)
    c:frame(1, 2, w - 2, h - 4, Palette.woodDark)
    c:hline(math.floor(h / 2), 1, w - 2, Palette.woodDark)
    c:vline(math.floor(w / 2), 2, h - 3, Palette.woodDark)
    return c
end

function gen.iconMorale(w, h)
    -- Corazon: dos discos y un triangulo, sin arte autorizado.
    local c = newCanvas(w, h)
    c:disc(w / 2 - 2, 4, 2.2, 2.2, Palette.red)
    c:disc(w / 2 + 1, 4, 2.2, 2.2, Palette.red)
    for y = 4, h - 2 do
        local half = math.max(0, (h - 2 - y) * 0.9 + 1)
        c:hline(y, w / 2 - 0.5 - half, w / 2 - 0.5 + half, Palette.red)
    end
    c:px(w / 2 - 3, 3, Palette.mix(Palette.red, Palette.white, 0.5))
    return c
end

function gen.iconHull(w, h)
    -- Un casco en miniatura, con la MISMA formula que el barco grande: si
    -- cambias la silueta, el icono la sigue solo.
    local c = newCanvas(w, h)
    local cx = (w - 1) / 2
    for y = 0, h - 1 do
        local half = hullHalf(y / (h - 1), (w - 1) / 2)
        if half >= 0.5 then
            c:hline(y, math.floor(cx - half + 0.5), math.floor(cx + half + 0.5), Palette.wood)
            c:px(math.floor(cx - half + 0.5), y, Palette.woodDark)
            c:px(math.floor(cx + half + 0.5), y, Palette.woodDark)
        end
    end
    c:vline(math.floor(cx), 3, h - 3, Palette.deck)
    return c
end

function gen.iconWind(w, h)
    local c = newCanvas(w, h)
    c:hline(3, 1, w - 4, Palette.foam)
    c:hline(5, 1, w - 2, Palette.foam)
    c:hline(7, 1, w - 5, Palette.foam)
    c:px(w - 3, 2, Palette.foam)
    c:px(w - 2, 3, Palette.foam)
    c:px(w - 3, 4, Palette.foam)
    return c
end

function gen.iconCrew(w, h)
    local c = newCanvas(w, h)
    c:disc(w / 2 - 0.5, 3, 2.2, 2.2, Palette.skin)
    c:disc(w / 2 - 0.5, h - 1, 4, 4, Palette.sail)
    return c
end

function gen.iconAnchor(w, h)
    local c = newCanvas(w, h)
    local cx = math.floor(w / 2)
    c:ring(cx, 2, 1.6, 1.6, Palette.rock)
    c:vline(cx, 3, h - 3, Palette.rock)
    c:hline(4, cx - 3, cx + 3, Palette.rock)
    c:line(cx - 4, h - 5, cx, h - 2, Palette.rock)
    c:line(cx + 4, h - 5, cx, h - 2, Palette.rock)
    return c
end

function gen.iconSail(w, h)
    local c = newCanvas(w, h)
    c:vline(math.floor(w / 2), 1, h - 2, Palette.woodDark)
    for y = 2, h - 3 do
        local hw = math.floor((y - 1) * 0.45) + 1
        c:hline(y, math.floor(w / 2) - hw, math.floor(w / 2) - 1, Palette.sail)
        c:hline(y, math.floor(w / 2) + 1, math.floor(w / 2) + hw, Palette.sailShade)
    end
    return c
end

function gen.iconHold(w, h)
    -- Cajas estibadas: dos abajo, una encima. Es el icono de la bodega y de
    -- la barra de carga del HUD.
    local c = newCanvas(w, h)
    local function crate(x, y, s)
        c:rect(x, y, s, s, Palette.woodLite)
        c:frame(x, y, s, s, Palette.woodDark)
    end
    crate(0, h - 5, 5)
    crate(6, h - 5, 5)
    crate(3, h - 10, 5)
    return c
end

function gen.iconChart(w, h)
    -- Carta de marear: una hoja con una demora cruzada y una rosa minima.
    local c = newCanvas(w, h)
    c:rect(0, 1, w, h - 2, Palette.sand)
    c:frame(0, 1, w, h - 2, Palette.woodDark)
    c:line(1, h - 3, w - 2, 3, Palette.red)
    c:px(w - 2, 3, Palette.gold)
    c:px(2, 3, Palette.uiLine)
    c:px(2, 4, Palette.uiLine)
    c:px(3, 3, Palette.uiLine)
    return c
end

function gen.dial(w, h)
    -- Bisel del timon, y nada mas. Las marcas de rumbo (N, viento, rumbo
    -- pedido) NO van en el sprite: giran con el barco y un sprite no puede
    -- girar, asi que las plotea src/compass.lua punto a punto. Lo que queda
    -- aqui es lo que se ve igual desde cualquier rumbo: dos aros y una corona
    -- de puntos.
    local c = newCanvas(w, h)
    local cx, cy = (w - 1) / 2, (h - 1) / 2
    local r = math.min(cx, cy)
    c:ring(cx, cy, r, r, Palette.uiLine)
    c:ring(cx, cy, r - 5, r - 5, Palette.uiPanel)
    for i = 0, 47 do
        local a = i * Util.TAU / 48
        c:px(cx + math.sin(a) * (r - 2.5), cy - math.cos(a) * (r - 2.5), Palette.dim)
    end
    return c
end

--==========================================================================
-- Registro
--==========================================================================

-- id, ancho, alto, archivo en assets/, generador (opcional).
--
-- Las capas del barco van primero y todas al mismo tamano: son la pila que
-- describe SHIP_W arriba. El numero del final del archivo es la prioridad que
-- les dio el dibujante -- 1 arriba, 3 abajo --, y el orden real de dibujo esta
-- en drawShip() de src/screens/voyage.lua.
--
-- Las que no llevan generador son opcionales: sin PNG no existen. Los canones
-- van con subindice 3 porque se dibujan DEBAJO del casco y de fuera de la
-- borda solo asoman las bocas; todavia no hay artilleria que los use.
local SPRITES = {
    { "ship.cannons",   SHIP_W, SHIP_H, "cannons3.png",    nil },
    { "ship.hull",      SHIP_W, SHIP_H, "ship2.png",       gen.shipHull },
    { "ship.hold",      SHIP_W, SHIP_H, "bodega1.png",     gen.shipHold },
    { "ship.galley",    SHIP_W, SHIP_H, "cook1.png",       nil },
    { "ship.nets",      SHIP_W, SHIP_H, "fish1.png",       nil },
    { "ship.sails",     SHIP_W, SHIP_H, "sails1.png",      gen.shipSailsFull },
    { "ship.sailsReef", SHIP_W, SHIP_H, "sails_reef1.png", gen.shipSailsReef },
    { "ship.anchor",    SHIP_W, SHIP_H, "anchor1.png",     nil },

    { "sea.drop",         2,  2, "sea_drop.png",        gen.drop },
    { "sea.calm",        56, 44, "sea_calm.png",        gen.calmBig },
    { "sea.calmet",      38, 30, "sea_calmet.png",      gen.calmSmall },
    { "sea.bow1",         9,  3, "sea_bow1.png",        gen.bowWave },
    { "sea.bow2",        13,  4, "sea_bow2.png",        gen.bowWave },
    { "sea.bow3",        17,  5, "sea_bow3.png",        gen.bowWave },
    -- La escalera de la estela. Los anchos suben de seis en seis porque el
    -- abanico entero (WAKE_SPAN de src/sea.lua) son unos cuarenta y cinco
    -- pixeles: seis por escalon sobre cinco escalones abren la uve a los
    -- diecinueve grados de una estela de verdad. El primero mide lo que el
    -- espejo de popa (26 px de manga ahi atras) para que nazca pegado a el.
    { "sea.wake1",       23,  6, "sea_wake1.png",       gen.wakeArc },
    { "sea.wake2",       29,  7, "sea_wake2.png",       gen.wakeArc },
    { "sea.wake3",       35,  8, "sea_wake3.png",       gen.wakeArc },
    { "sea.wake4",       41,  9, "sea_wake4.png",       gen.wakeArc },
    { "sea.wake5",       47, 10, "sea_wake5.png",       gen.wakeArc },
    { "sea.island",      40, 32, "sea_island.png",      gen.island },
    { "sea.rock",        10,  8, "sea_rock.png",        gen.rock },
    { "sea.port",        32, 26, "sea_port.png",        gen.port },

    { "icon.coin",       11, 11, "icon_coin.png",       gen.iconCoin },
    { "icon.fish",       11, 11, "icon_fish.png",       gen.iconFish },
    { "icon.wood",       11, 11, "icon_wood.png",       gen.iconWood },
    { "icon.ration",     11, 11, "icon_ration.png",     gen.iconRation },
    { "icon.morale",     11, 11, "icon_morale.png",     gen.iconMorale },
    { "icon.hull",       11, 11, "icon_hull.png",       gen.iconHull },
    { "icon.wind",       11, 11, "icon_wind.png",       gen.iconWind },
    { "icon.crew",       11, 11, "icon_crew.png",       gen.iconCrew },
    { "icon.anchor",     11, 11, "icon_anchor.png",     gen.iconAnchor },
    { "icon.sail",       11, 11, "icon_sail.png",       gen.iconSail },
    { "icon.hold",       11, 11, "icon_hold.png",       gen.iconHold },
    { "icon.chart",      11, 11, "icon_chart.png",      gen.iconChart },

    { "ui.dial",         44, 44, "ui_dial.png",         gen.dial },
}

-- Las cuatro familias orientadas del mar. Cada una es el MISMO trazo pintado
-- en SEA_DIRS angulos, y src/sea.lua elige el que toca segun donde caiga el
-- viento en pantalla. Es la primera de las dos salidas que deja la regla 1
-- ("ocho sprites de rumbo, o primitivas"), y aqui gana porque el mar son
-- doscientos trazos por fotograma: un sprite ya hecho se dibuja de un tiron y
-- doscientas lineas de Bresenham en vivo no.
--
-- Doce pasos son quince grados. Es el grano al que un trazo de trece pixeles
-- cambia UN pixel de punta entre una orientacion y la siguiente, asi que al
-- virar el mar se repeina sin que se vea saltar; con ocho ya se nota.
local SEA_DIRS = 12
Art.SEA_DIRS = SEA_DIRS

for _, fam in ipairs({
    { "sea.ripple",  3, gen.crestRipple },
    { "sea.wave",    6, gen.crestWave },
    { "sea.swell",   8, gen.crestSwell },
    { "sea.gust",    9, gen.gustStreak },
}) do
    local id, len, make = fam[1], fam[2], fam[3]
    -- El lienzo es cuadrado y del largo del trazo: en diagonal ocupa menos, y
    -- de sobra para la fila de sombra.
    local box = len + 2
    local file = id:gsub("%.", "_")
    for d = 1, SEA_DIRS do
        local angle = (d - 1) * math.pi / SEA_DIRS
        SPRITES[#SPRITES + 1] = {
            id .. d, box, box, file .. "_" .. d .. ".png",
            function(w, h) return make(w, h, angle) end,
        }
    end
end

--== La reserva de caras ===================================================

-- Se registran en bucle y no a mano porque son catorce filas identicas salvo
-- el numero, y porque cuantas hay lo manda Crew.FACES: la simulacion reparte
-- caras con ese tope (Crew.face) y una lista escrita a mano se le
-- desincronizaria en cuanto se anadiera un PNG.
--
-- Van al final de la lista, detras de los iconos, porque la lista es tambien
-- el orden de carga del arranque y lo ultimo que se genera es lo que menos se
-- echa de menos si la barra de progreso se corta.
local function faceId(index)
    return string.format("crew.pj%02d", index)
end

for i = 1, Crew.FACES do
    SPRITES[#SPRITES + 1] = {
        faceId(i), 8, 8, string.format("crew_pj%02d.png", i), crewFace(i),
    }
end

-- Sprite de un tripulante, a partir del indice que devuelve Crew.face.
function Art.crewFace(index)
    return faceId(index)
end

Art.SPRITES = SPRITES
Art.count = #SPRITES

local cursor = 0

-- Construye un sprite por llamada. La pantalla de arranque llama a esto en
-- bucle para poder pintar la barra de progreso entre uno y otro en vez de
-- congelarse en negro mientras se genera todo.
function Art.step()
    cursor = cursor + 1
    local entry = SPRITES[cursor]
    if not entry then return true, 1 end

    local id, w, h, file, generator = entry[1], entry[2], entry[3], entry[4], entry[5]
    local path = "assets/" .. file

    if love.filesystem.getInfo(path) then
        local img = love.graphics.newImage(path)
        img:setFilter('nearest', 'nearest')
        Art.images[id] = img
        Art.sizes[id] = { w = img:getWidth(), h = img:getHeight() }
        Art.fromFile[id] = true
    elseif generator then
        local canvas = generator(w, h)
        Art.images[id] = canvas:image()
        Art.sizes[id] = { w = w, h = h }
        Art.fromFile[id] = false
    else
        -- Capa opcional y sin PNG: no existe, y quien la dibuje con
        -- Art.drawIfAny se callara. No entra en Art.list porque no hay nada
        -- que listar, pero si en Art.absent, que es lo que imprime el
        -- arranque para que se vea que falta.
        Art.absent[id] = true
        return cursor >= #SPRITES, cursor / #SPRITES
    end

    Art.list[#Art.list + 1] = id
    return cursor >= #SPRITES, cursor / #SPRITES
end

function Art.loadAll()
    local done = false
    repeat done = Art.step() until done
end

function Art.get(id)
    local img = Art.images[id]
    if not img then
        error("sprite desconocido: " .. tostring(id))
    end
    return img
end

function Art.size(id)
    local s = Art.sizes[id]
    return s.w, s.h
end

-- Dibuja en espacio de arte con la esquina superior izquierda en (x, y).
-- Redondea siempre: medio pixel de arte son dos de pantalla y se ve.
function Art.draw(id, x, y)
    love.graphics.draw(Art.get(id), math.floor(x), math.floor(y))
end

-- Como Art.draw, pero se calla si la capa no existe. Solo para las capas
-- opcionales del barco: el resto del arte SI tiene que petar si falta, que es
-- como se encuentra una errata en un id.
function Art.drawIfAny(id, x, y)
    if Art.images[id] then Art.draw(id, x, y) end
end

-- Dibuja centrado en (x, y).
function Art.drawCentered(id, x, y)
    local w, h = Art.size(id)
    love.graphics.draw(Art.get(id), math.floor(x - w / 2), math.floor(y - h / 2))
end

-- Lista lo que salio de assets/ y lo que se genero. La imprime el arranque:
-- es la forma rapida de comprobar que tu PNG se esta cogiendo.
function Art.manifest()
    local mine, generated, absent = {}, {}, {}
    for _, id in ipairs(Art.list) do
        table.insert(Art.fromFile[id] and mine or generated, id)
    end
    -- En orden de registro, no el del hash: una lista que baila cada arranque
    -- no sirve para comparar dos ejecuciones.
    for _, entry in ipairs(SPRITES) do
        if Art.absent[entry[1]] then absent[#absent + 1] = entry[1] end
    end
    return mine, generated, absent
end

return Art
