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
-- Eso obligaba a que nada del mundo tuviera una orientacion propia -- islas y
-- puertos siguen siendo manchas, que se leen igual desde cualquier demora --,
-- pero el MAR si la tiene, y esconderla costaba caro: un oleaje que siempre
-- cruzaba la pantalla en horizontal no decia de donde soplaba el viento, se
-- veia igual con racha que en calma, y en una rejilla regular de trazos
-- iguales se leia la rejilla. Aqui las crestas se peinan contra el viento --
-- asi que van en diagonal cuando el viento va en diagonal --, y se dibujan por
-- la primera de las dos salidas que deja la regla: doce sprites, uno por
-- orientacion, elegidos por el angulo (ver SEA_DIRS en src/art.lua). Ni una
-- llamada de este archivo pasa rotacion.
--
-- El bigote de proa es la excepcion contraria y por eso es facil: va pegado a
-- la pantalla y no al mundo, y la proa apunta siempre arriba, asi que no tiene
-- angulo que elegir.
--
-- Ademas, nada del mar se guarda: olas, rachas, islas, escollos, estela y
-- salpicaduras son funcion pura de la posicion del mundo, de la semilla y del
-- tiempo. El mar es infinito y ocupa cero bytes.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Art       = require('src.art')
local Ports     = require('src.ports')
local Ship      = require('src.ship')

local Sea = {}

Sea.WAVE_CELL    = 10   -- una ola por celda de mundo, si el mar da para ella
Sea.SWELL_CELL   = 96   -- tamano de las manchas de mar picado y de mar llano
Sea.GUST_CELL    = 46
Sea.CALM_CELL    = 110  -- manchas de agua honda
Sea.SCENERY_CELL = 250  -- islas y escollos

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

-- Angulo en PANTALLA de una direccion del mundo. Es lo unico que hace falta
-- para elegir sprite orientado: la misma direccion del mundo cae a un angulo
-- distinto en cada rumbo, y eso es exactamente lo que hace que virar repeine
-- el mar.
function Sea.screenAngle(state, ux, uy)
    local sinH, cosH = math.sin(state.heading), math.cos(state.heading)
    return math.atan2(-(ux * sinH - uy * cosH), ux * cosH + uy * sinH)
end

-- Sprite de una familia orientada. Un trazo no tiene punta, asi que su
-- orientacion vive en media vuelta: doce sprites cubren los 180 grados.
function Sea.orient(id, angle)
    local d = math.floor(angle / math.pi * Art.SEA_DIRS + 0.5) % Art.SEA_DIRS
    return id .. (d + 1)
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

-- Recorre las celdas de tamano `cell` que cubren la pantalla alrededor de un
-- punto. Todo el mar se dibuja con esto, y va aparte porque los campos que
-- DESFILAN (olas, rachas) no se barren alrededor del barco sino alrededor del
-- barco menos el desplazamiento del campo: asi el campo avanza sin saltos, en
-- vez del tiron que daba reciclar el desfile con un modulo.
local function forEachCell(bx, by, cell, extra, fn)
    local radius = Sea.viewRadius() + (extra or 0)
    local c0x = math.floor((bx - radius) / cell)
    local c1x = math.floor((bx + radius) / cell)
    local c0y = math.floor((by - radius) / cell)
    local c1y = math.floor((by + radius) / cell)
    for cy = c0y, c1y do
        for cx = c0x, c1x do fn(cx, cy) end
    end
end

-- Ruido de valor: hash en las esquinas de una rejilla e interpolado suave por
-- dentro. Es lo que da MANCHAS -- un trozo de mar picado, otro liso -- en vez
-- de una rugosidad uniforme, que es lo que delataba la rejilla de olas.
local function noise(x, y, salt)
    local x0, y0 = math.floor(x), math.floor(y)
    local fx, fy = x - x0, y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    local a = Util.hash01(x0,     y0,     salt)
    local b = Util.hash01(x0 + 1, y0,     salt)
    local c = Util.hash01(x0,     y0 + 1, salt)
    local d = Util.hash01(x0 + 1, y0 + 1, salt)
    return Util.lerp(Util.lerp(a, b, fx), Util.lerp(c, d, fx), fy)
end

--==========================================================================
-- Cola de trazos
--==========================================================================

-- El mar no se pinta segun se recorre: se APUNTA por sprite y se pinta al
-- final, todos los trazos de un sprite seguidos.
--
-- Es la unica factura que pasa tener el mar orientado. LÖVE junta en un solo
-- envio los dibujos consecutivos de la MISMA imagen, y con doce orientaciones
-- por tres tamanos entremezcladas al azar cada trazo rompia el envio del
-- anterior: trescientos y pico envios por cuadro donde antes habia dos. Con la
-- cola son una docena, que es lo que habia. Las colas se reutilizan de un
-- cuadro para otro (solo se pone n a cero) para no dar de comer al recolector
-- treinta veces por segundo.
--
-- De propina fija el ORDEN: rizos debajo, olas encima, rompientes despues y
-- rachas al final, que es la unica capa que cruza a las demas.
local ORDER = { "sea.ripple", "sea.wave", "sea.swell", "sea.gust" }
local queue = {}

local function enqueue(id, x, y)
    local q = queue[id]
    if not q then q = { n = 0 }; queue[id] = q end
    local n = q.n
    q[n + 1], q[n + 2] = x, y
    q.n = n + 2
end

local function flushStrokes()
    for _, fam in ipairs(ORDER) do
        for d = 1, Art.SEA_DIRS do
            local id = fam .. d
            local q = queue[id]
            if q and q.n > 0 then
                for i = 1, q.n, 2 do Art.drawCentered(id, q[i], q[i + 1]) end
                q.n = 0
            end
        end
    end
end

--==========================================================================
-- Estado del mar
--==========================================================================

-- El viento sopla entre 0.55 y 1.0 (World.updateWind), que como fuerza de mar
-- es un rango corto y sin fondo: con 0.55 el mar se veia igual de picado que
-- con 1.0. Aqui se estira a [0, 1] para que la calma sea calma de verdad --
-- rizos sueltos, agua quieta, ni una rompiente -- y la racha se note.
function Sea.state(state)
    return Util.clamp((state.wind.strength - 0.50) / 0.50, 0, 1)
end

-- Direccion HACIA la que sopla, en el mundo. Es la del desfile de todo el mar.
local function windVector(state)
    return Util.headingToVector(Util.wrapAngle(state.wind.from + math.pi))
end

-- Velocidad del barco como fraccion de lo que da una buena singladura. No se
-- mide contra Ship.BASE_SPEED, que es la velocidad de un barco perfecto en el
-- traves y no la ve nadie: contra eso, la estela de una partida nueva no se
-- veia nunca.
local REF_SPEED = 4.5
-- Por debajo de esto la roda no levanta agua: ni bigote ni salpicaduras. Un
-- barco que apenas se mueve con espuma en la proa miente, y en el ojo del
-- viento -- donde se anda al diez por ciento -- se pasa un buen rato asi.
local WORKING = 0.30
local function speedFraction(state)
    if state.docked then return 0 end
    return Util.clamp(Ship.speed(state) / REF_SPEED, 0, 1)
end

--==========================================================================
-- Estela y salpicaduras
--==========================================================================
--
-- Nada de esto se guarda: es adorno, y al volver a la partida el barco aparece
-- con el mar limpio detras (Sea.reset).
--
-- La estela son dos cosas distintas y por eso no basta con una fila de puntos:
--
--   * el REMOLINO de popa, que se queda donde se solto y se deshace. Es lo que
--     habia antes, y solo, contaba una mentira: se veia igual a dos nudos que
--     a seis, y en una virada quedaba una raya recta que no era la derrota.
--   * los BRAZOS -- la V de Kelvin --, que se abren detras del barco a un
--     angulo fijo. El angulo es fijo pero la V se abre a lo largo de lo que el
--     barco AVANZA, asi que un barco parado no tiene V, uno rapido la tiene
--     larga, y virando se dobla sola porque cada punto guarda su propia
--     travesia. Eso es lo que hace que la estela diga el rumbo y la velocidad.
--
-- La apertura se mide con state.distance y no con el tiempo a proposito: es la
-- misma cuenta que hace el agua, y sale bien aunque la velocidad cambie a
-- mitad de estela.

local wake, spray = {}, {}
local WAKE_MAX  = 80
local SPRAY_MAX = 48
local SEED_STEP = 4      -- un punto de estela cada tantos pixeles de mundo
local SPREAD    = 0.32   -- tangente del semiangulo de la V
local ARM_MAX   = 30     -- hasta donde se abren los brazos, en pixeles
-- La estela nace DETRAS del espejo de popa y la salpicadura DELANTE de la
-- roda, y los dos numeros son media eslora larga por una razon que costo
-- verse: sembrados mas cerca del centro quedan debajo del casco, que mide 82
-- pixeles de proa a popa, y a poco andar la estela entera cabe ahi dentro sin
-- asomar. Con viento flojo no se veia ni un punto de espuma.
local STERN     = 44
local BOW       = 42

local lastX, lastY, lastDist
local sprayAcc, sprayN = 0, 0

function Sea.reset()
    wake, spray = {}, {}
    lastX, lastY, lastDist = nil, nil, nil
    sprayAcc, sprayN = 0, 0
end

local function shedWake(state, frac)
    local fx, fy = Util.headingToVector(state.heading)
    local sx = state.x - fx * STERN
    local sy = state.y - fy * STERN
    if lastX and Util.dist(lastX, lastY, sx, sy) <= SEED_STEP then return end
    lastX, lastY = sx, sy
    table.insert(wake, 1, {
        x = sx, y = sy,
        -- Estribor del barco EN EL MOMENTO de soltarlo: es lo que hace que los
        -- brazos se abran sobre la derrota vieja y no sobre el rumbo de ahora.
        nx = math.cos(state.heading), ny = math.sin(state.heading),
        d = state.distance,
        age = 0,
        -- Un barco lento deja un remolino corto; uno lanzado, uno largo. El
        -- numero se midio en pantalla y no en el reloj: la estela tiene que
        -- durar lo bastante para verse VARIAS ESLORAS por popa, o a media
        -- singladura no asoma del espejo y el barco parece estar parado.
        life = 3.5 + 6.5 * frac,
        -- Los brazos van uno de cada dos: la V son crestas sueltas, no una
        -- linea, y con todos puestos parecia un embudo pintado.
        arm = (frac > 0.35) and (#wake % 2 == 0) or false,
    })
    while #wake > WAKE_MAX do table.remove(wake) end
end

local function shedSpray(state, dt, frac, sea)
    if frac < WORKING then return end
    -- A pulsos, no a chorro: el barco cabecea y la proa entra y sale.
    local pulse = 0.45 + 0.55 * math.sin(state.time * 2.4) ^ 2
    sprayAcc = sprayAcc + (frac - WORKING) * (14 + 20 * sea) * pulse * dt

    local fx, fy = Util.headingToVector(state.heading)
    local nx, ny = math.cos(state.heading), math.sin(state.heading)
    -- Sotavento: el viento que entra por una banda tumba el barco hacia la
    -- otra, y es por la de sotavento por donde el agua sale disparada.
    local lee = (math.sin(Util.angleDiff(state.heading, state.wind.from)) > 0) and -1 or 1
    local speed = Ship.speed(state)

    while sprayAcc >= 1 do
        sprayAcc = sprayAcc - 1
        sprayN = sprayN + 1
        local r1 = Util.hash01(sprayN, math.floor(state.time * 13), 41)
        local r2 = Util.hash01(sprayN, math.floor(state.time * 13), 42)
        local r3 = Util.hash01(sprayN, math.floor(state.time * 13), 43)
        local side = (r1 < 0.68) and lee or -lee
        -- Nace YA fuera del casco, no en la crujia: la roda no tiene manga y
        -- una gota sembrada en el eje pasa la mitad de su vida escondida
        -- debajo del barco y de las velas, que se pintan encima del mar.
        local off  = 3 + 5 * r3
        local out  = (0.60 + 1.10 * r2) * speed
        local ahead = (0.25 + 0.45 * r3) * speed
        spray[#spray + 1] = {
            x = state.x + fx * (BOW - 5 * r2) + nx * side * off,
            y = state.y + fy * (BOW - 5 * r2) + ny * side * off,
            vx = nx * out * side + fx * ahead,
            vy = ny * out * side + fy * ahead,
            age = 0,
            life = 0.30 + 0.45 * r3,
        }
        if #spray > SPRAY_MAX then table.remove(spray, 1) end
    end
end

function Sea.update(state, dt)
    -- El mar se dibuja a golpe de fotograma; un dt de puesta al dia (segundos
    -- enteros) haria explotar el rozamiento de las gotas y abriria la V de una
    -- zancada. Se recorta aqui, que es donde vive el adorno.
    dt = math.min(dt, 1 / 20)

    -- Una vuelta de la partida mueve el barco horas de golpe: la estela vieja
    -- queda a mil pixeles de aqui y los brazos se abririan a lo ancho del mar.
    if lastDist and state.distance - lastDist > 200 then Sea.reset() end
    lastDist = state.distance

    -- La estela se siembra con mucho menos andar que el bigote: un barco que
    -- apenas se mueve NO levanta agua por la proa, pero si deja un rastro
    -- detras, y sin el se ve quieto en un mar que desfila.
    local frac = speedFraction(state)
    if frac > 0.12 then
        shedWake(state, frac)
        shedSpray(state, dt, frac, Sea.state(state))
    end

    -- Envejece SIEMPRE, tambien amarrado: el agua no se para porque tu si.
    for i = #wake, 1, -1 do
        local p = wake[i]
        p.age = p.age + dt
        if p.age > p.life then table.remove(wake, i) end
    end
    for i = #spray, 1, -1 do
        local q = spray[i]
        q.age = q.age + dt
        q.x, q.y = q.x + q.vx * dt, q.y + q.vy * dt
        -- El agua frena lo que sale de ella, y rapido.
        local drag = 1 - 3.0 * dt
        q.vx, q.vy = q.vx * drag, q.vy * drag
        if q.age > q.life then table.remove(spray, i) end
    end
end

--==========================================================================
-- Dibujo
--==========================================================================

-- La espuma se apaga bajando por la paleta, no con alpha: mezclar con
-- transparencia inventaria un color que no esta en la paleta.
local function foamColor(k)
    if k < 0.35 then return Palette.white end
    if k < 0.72 then return Palette.foam end
    return Palette.shallow
end

-- Manchas de agua honda. Van debajo de todo y se mueven con el mundo, no con
-- el viento: es el fondo lo que cambia, no la superficie. Solo salen donde el
-- mar esta LISO, que es cuando de verdad se ve el color del fondo; donde
-- rompe, la espuma lo tapa.
local function drawCalm(state)
    local cell = Sea.CALM_CELL
    forEachCell(state.x, state.y, cell, 40, function(cx, cy)
        local roll = Util.hash01(cx, cy, 31)
        if roll > 0.42 then return end
        local wx = (cx + Util.hash01(cx, cy, 32)) * cell
        local wy = (cy + Util.hash01(cx, cy, 33)) * cell
        if noise(wx / Sea.SWELL_CELL, wy / Sea.SWELL_CELL, 9) > 0.52 then return end
        local x, y = Sea.project(state, wx, wy)
        if onScreen(x, y, 40) then
            Art.drawCentered(roll < 0.20 and "sea.calm" or "sea.calmet", x, y)
        end
    end)
end

local function drawWaves(state)
    local sea = Sea.state(state)
    local tx, ty = windVector(state)
    -- Las crestas se peinan CONTRA el viento: la cresta cruza la direccion en
    -- la que corre la ola, que es la del viento. De ahi el cuarto de vuelta.
    local crest = Sea.screenAngle(state, tx, ty) + math.pi / 2

    -- El campo entero desfila a sotavento. No se recicla con un modulo -- eso
    -- da un tiron cada vuelta --: lo que se desplaza es el punto ALREDEDOR del
    -- cual se barren las celdas, asi que el mar avanza sin costura.
    local drift = state.time * (5 + 26 * sea)
    local ox, oy = tx * drift, ty * drift
    local cell = Sea.WAVE_CELL
    local t = state.time

    forEachCell(state.x - ox, state.y - oy, cell, 0, function(cx, cy)
        local wx = (cx + Util.hash01(cx, cy, 1)) * cell
        local wy = (cy + Util.hash01(cx, cy, 2)) * cell

        -- Mancha: un trozo de mar picado y el de al lado casi liso. Es la
        -- diferencia entre un oleaje y un papel pintado de olas.
        local rough = noise(wx / Sea.SWELL_CELL, wy / Sea.SWELL_CELL, 9)
        local density = 0.36 + 0.48 * sea * (0.30 + 0.70 * rough)
        if Util.hash01(cx, cy, 3) >= density then return end

        -- Que ola es, y la mezcla importa mas que cada una: la mayoria tienen
        -- que ser rizos -- trazo corto, color de agua, casi sin contraste --
        -- y solo unas pocas romper en blanco. Con la mayoria en espuma clara
        -- el mar se llena de marcas iguales y brillantes, y un campo de marcas
        -- iguales y brillantes no se lee como agua: se lee como lluvia.
        --
        -- El exponente concentra las olas hechas en las manchas picadas en vez
        -- de repartirlas: es lo que hace que se navegue de un trozo de mar a
        -- otro y no por un mar medio en todas partes.
        local grade = sea * (0.10 + 0.90 * rough) ^ 1.6
                          * (0.30 + 0.70 * Util.hash01(cx, cy, 4))
        local id = (grade > 0.50 and "sea.swell")
                or (grade > 0.24 and "sea.wave")
                or "sea.ripple"

        -- Tren de olas: la fase corre a lo largo del viento, asi que las
        -- crestas de una misma linea suben y bajan juntas y las de detras van
        -- un poco despues. Con una fase suelta por ola el mar hierve; con
        -- esta, respira.
        local along = wx * tx + wy * ty
        local surge = math.sin(along * 0.075 - t * (0.9 + 1.1 * sea)) * (0.5 + 2.2 * sea)

        local x, y = Sea.project(state,
                                 wx + ox + tx * surge,
                                 wy + oy + ty * surge)
        if not onScreen(x, y, 22) then return end

        -- Cada cresta se tuerce un poco de su cuenta. Un mar de trazos
        -- exactamente paralelos es un peine, no un mar: la mar corta de verdad
        -- va desordenada. Un paso de sprite arriba o abajo basta, y mas ya
        -- borra de donde sopla.
        local skew = (Util.hash01(cx, cy, 8) - 0.5) * 0.46
        local sprite = Sea.orient(id, crest + skew)

        -- Una cresta es larga y se rompe a trozos, asi que la ola corriente se
        -- pinta a veces DOS veces seguidas a lo largo de si misma: con hueco
        -- entre tramo y tramo, y escalonadas un pixel a un lado. Con hueco y
        -- escalon es una cresta rota; pegadas y en linea salia una raya larga,
        -- y una pantalla de rayas largas y finas no es un mar, es lluvia.
        --
        -- Se dobla SOLO la ola corriente, que es la oscura. El rizo es el grano
        -- del agua y encadenado vuelve a ser una raya; y la rompiente lleva
        -- blanco, asi que encadenada pinta una linea de puntos brillantes --
        -- que es, otra vez, exactamente lluvia. Lo blanco va siempre suelto.
        local ang = crest + skew
        local n = (id == "sea.wave" and Util.hash01(cx, cy, 10) > 0.45) and 2 or 1
        if n == 1 then
            enqueue(sprite, x, y)
        else
            local sw = Art.size(sprite)
            local ux, uy = math.cos(ang), math.sin(ang)
            local gap = sw + 1
            for i = 0, 1 do
                local k = i - 0.5
                local step = (Util.hash01(cx, cy, 40 + i) > 0.5) and 1 or -1
                enqueue(sprite, x + ux * gap * k - uy * step,
                                y + uy * gap * k + ux * step)
            end
        end
    end)
end

local function drawGusts(state)
    local sea = Sea.state(state)
    local tx, ty = windVector(state)
    -- Al reves que las crestas: la racha corre A FAVOR del viento, asi que en
    -- pantalla cruza las olas en angulo recto. Es lo que ensena de donde sopla.
    local streak = Sea.screenAngle(state, tx, ty)
    local drift = state.time * (26 + 70 * sea)
    local ox, oy = tx * drift, ty * drift
    local cell = Sea.GUST_CELL

    forEachCell(state.x - ox, state.y - oy, cell, 0, function(cx, cy)
        -- En calma no hay rachas que ver; con viento fresco, muchas.
        if Util.hash01(cx, cy, 5) <= 0.94 - 0.10 * sea then return end
        local wx = (cx + Util.hash01(cx, cy, 6)) * cell + ox
        local wy = (cy + Util.hash01(cx, cy, 7)) * cell + oy
        local x, y = Sea.project(state, wx, wy)
        if onScreen(x, y, 12) then
            enqueue(Sea.orient("sea.gust", streak), x, y)
        end
    end)
end

local function drawScenery(state)
    local cell = Sea.SCENERY_CELL
    forEachCell(state.x, state.y, cell, 40, function(cx, cy)
        local roll = Util.hash01(state.seed + cx, cy, 21)
        if roll <= 0.72 then return end
        local wx = (cx + Util.hash01(cx, cy, 22)) * cell
        local wy = (cy + Util.hash01(cx, cy, 23)) * cell
        local x, y = Sea.project(state, wx, wy)
        if onScreen(x, y, 40) then
            Art.drawCentered(roll > 0.88 and "sea.island" or "sea.rock", x, y)
        end
    end)
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
        local k = p.age / p.life
        love.graphics.setColor(foamColor(k))

        local x, y = Sea.project(state, p.x, p.y)
        if onScreen(x, y, 8) then Art.drawCentered("sea.foam", x, y) end

        -- Los brazos se abren a lo que el barco ha andado DESDE que se solto
        -- este punto, que es lo que hace la V de verdad: fija en angulo,
        -- larga o corta segun lo que corras.
        if p.arm then
            local open = math.min((state.distance - p.d) * SPREAD, ARM_MAX)
            if open > 2 then
                for _, s in ipairs({ -1, 1 }) do
                    local ax, ay = Sea.project(state,
                                               p.x + p.nx * open * s,
                                               p.y + p.ny * open * s)
                    if onScreen(ax, ay, 8) then
                        Art.drawCentered("sea.drop", ax, ay)
                    end
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawSpray(state)
    for _, q in ipairs(spray) do
        local x, y = Sea.project(state, q.x, q.y)
        if onScreen(x, y, 8) then
            love.graphics.setColor(foamColor(q.age / q.life))
            Art.drawCentered("sea.drop", x, y)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Bigote de proa. Va pegado a la pantalla y no al mundo -- la roda esta
-- siempre en el mismo pixel --, asi que no elige orientacion: la proa apunta
-- arriba por definicion. Los tres tamanos son la lectura de velocidad que la
-- estela sola no da: la estela cuenta de donde vienes, el bigote cuanto
-- corres AHORA.
local function drawBowWave(state)
    local frac = speedFraction(state)
    if frac < WORKING then return end
    local cx, cy = Constants.shipAnchor()
    local _, hullH = Art.size("ship.hull")
    local stem = cy - Art.HULL_BOX.h * hullH / 2
    local id = (frac > 0.70 and "sea.bow3")
            or (frac > 0.45 and "sea.bow2")
            or "sea.bow1"
    -- Cabeceo: la roda sube y baja, y con ella el bigote. Un pixel de arte son
    -- cinco de pantalla, asi que con esto basta y sobra.
    local heave = math.floor(math.sin(state.time * 2.4) * (0.6 + frac))
    Art.drawCentered(id, cx, stem + 3 + heave)
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

    drawCalm(state)
    drawWaves(state)
    drawGusts(state)
    flushStrokes()
    drawScenery(state)
    drawPorts(state)
    drawWake(state)
    drawSpray(state)
    drawBowWave(state)
    drawHeadingGuide(state)
end

return Sea
