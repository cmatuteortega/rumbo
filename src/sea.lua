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
-- cruzaba la pantalla en horizontal no decia de donde soplaba el viento y se
-- veia igual con racha que en calma. La superficie es hoy la tercera salida a
-- ese apuro, y esta en `src/surface.lua`: un shader. No hay sprite que girar
-- porque no hay sprite -- el agua se calcula por pixel --, asi que el mar
-- puede peinarse en cualquier direccion sin tocar la regla. Antes de eso
-- fueron doce sprites por trazo, uno cada quince grados, que es la primera
-- salida que deja la regla y sigue siendo la buena para todo lo que si sea un
-- dibujo.
--
-- Lo que queda en este archivo es la camara y todo lo que el shader no puede
-- saber por su cuenta: las islas y los puertos, que tienen sitio fijo en el
-- mundo; las salpicaduras, que estan en el AIRE y no en el agua; y la DERROTA
-- del barco, que es memoria -- por donde se ha pasado -- y que se le pasa al
-- shader para que abra el surco y la V dentro del propio campo de espuma en
-- vez de pintarlos encima.
--
-- Ademas, nada del mar se guarda: superficie, islas, escollos, derrota y
-- salpicaduras son funcion de la posicion del mundo, de la semilla y del
-- tiempo. El mar es infinito y ocupa cero bytes.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Art       = require('src.art')
local Ports     = require('src.ports')
local Ship      = require('src.ship')
local Surface   = require('src.surface')

local Sea = {}

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

-- Angulo en PANTALLA de una direccion del mundo. La misma direccion del mundo
-- cae a un angulo distinto en cada rumbo, y eso es exactamente lo que hace que
-- virar repeine el mar. No lo usa el dibujo -- el shader lleva la direccion en
-- sus ejes --, pero es la contrapartida de Sea.project y es con lo que
-- tests/test_sea.lua comprueba hacia donde ha quedado peinada la superficie.
function Sea.screenAngle(state, ux, uy)
    local sinH, cosH = math.sin(state.heading), math.cos(state.heading)
    return math.atan2(-(ux * sinH - uy * cosH), ux * cosH + uy * sinH)
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
-- punto. Es como se siembra todo lo que esta CLAVADO en el mundo -- islas y
-- escollos --, que es lo unico que queda de sembrar por celdas desde que el
-- agua la pinta un shader.
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

-- Velocidad del barco como fraccion de lo que da una buena singladura. No se
-- mide contra Ship.BASE_SPEED, que es la velocidad de un barco perfecto en el
-- traves y no la ve nadie: contra eso, la estela de una partida nueva no se
-- veia nunca.
local REF_SPEED = 4.5
-- Por debajo de esto la roda no levanta agua: ni espuma de proa ni
-- salpicaduras. Un barco que apenas se mueve con espuma en la proa miente, y
-- en el ojo del viento -- donde se anda al diez por ciento -- se pasa un buen
-- rato asi.
local WORKING = 0.30
local function speedFraction(state)
    if state.docked then return 0 end
    return Util.clamp(Ship.speed(state) / REF_SPEED, 0, 1)
end

-- La roda rompe agua: contado desde WORKING, asi que en el ojo del viento vale
-- cero y no hay bigote. Manda por DELANTE del espejo de popa.
local function bowFraction(state)
    local f = speedFraction(state)
    if f <= WORKING then return 0 end
    return (f - WORKING) / (1 - WORKING)
end

-- La estela de popa: se llena mucho antes, porque un barco deja rastro a
-- cualquier velocidad a la que se mueva de verdad. Ponerle la regla de la roda
-- fue un error que costo verse: la estela desaparecia justo cuando mas falta
-- hace -- virando, o con viento flojo --, que es cuando el barco va despacio y
-- cuando mas se agradece ver que sigue andando. A 1,6 px/s ya esta al maximo.
local WASH = 0.35
local function washFraction(state)
    return Util.clamp(speedFraction(state) / WASH, 0, 1)
end

--==========================================================================
-- La derrota, y las salpicaduras
--==========================================================================
--
-- Nada de esto se guarda: es adorno, y al volver a la partida el barco aparece
-- con el mar limpio detras (Sea.reset).
--
-- Aqui NO se dibuja la estela. Lo que se lleva es la DERROTA -- por donde ha
-- pasado el espejo de popa, un punto cada pocos pixeles de mundo, con lo que
-- el barco llevaba andado en cada uno --, y de eso saca el shader el surco, el
-- hervor de popa y la V (ver `wakeTrack` y `src/surface.lua`).
--
-- La estela estuvo pintada encima con puntos sueltos y contaba una mentira: la
-- espuma se SUMABA al oleaje en vez de romperlo, asi que el mar seguia picado
-- por debajo del barco y la V se veia pegada por encima, como una calcomania.
-- Dentro del campo, en cambio, el casco quita mar: eso es lo que se lee como
-- que el barco rompe el agua.
--
-- Lo que si se guarda por punto es cuanto llevaba andado el barco al soltarlo
-- (`d`), porque la apertura de la V se mide con `state.distance` y no con el
-- tiempo: es la misma cuenta que hace el agua, y sale bien aunque la velocidad
-- cambie a mitad de estela.

local wake, spray = {}, {}
local WAKE_MAX  = 48
local SPRAY_MAX = 48
local SEED_STEP = 4      -- un punto de estela cada tantos pixeles de mundo

-- Cuanto dura la estela, en PIXELES ANDADOS. Es la misma leccion que la de la
-- V, aplicada a lo que faltaba: medida en segundos, un barco lento dejaba un
-- rabito de treinta pixeles que se apagaba antes de llegar al borde de la
-- pantalla, asi que con viento flojo o en mitad de una virada -- justo cuando
-- el barco pierde andar -- la estela no se veia. Medida en lo andado, la
-- estela mide siempre lo mismo por muy despacio que se vaya: lo que cambia es
-- lo que tarda en dejarla atras, que es lo que de verdad pasa en el agua.
local WAKE_RUN  = 110
-- Y un tope en segundos, que es el respaldo del barco PARADO: sin el, un barco
-- quieto conservaria su estela para siempre. Va holgado a proposito, porque en
-- cuanto el barco anda es lo andado quien manda; apretarlo volvia a acortar la
-- estela de los barcos lentos, que es el fallo que se queria quitar. Aun asi,
-- por debajo de unos cuatro pixeles por segundo la estela sale mas corta: un
-- barco que se arrastra deja menos rastro, y eso es verdad tambien en el agua.
local WAKE_LIFE = 30
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
    Surface.reset()
    wake, spray = {}, {}
    lastX, lastY, lastDist = nil, nil, nil
    sprayAcc, sprayN = 0, 0
end

local function shedWake(state)
    local fx, fy = Util.headingToVector(state.heading)
    local sx = state.x - fx * STERN
    local sy = state.y - fy * STERN
    if lastX and Util.dist(lastX, lastY, sx, sy) <= SEED_STEP then return end
    lastX, lastY = sx, sy
    table.insert(wake, 1, {
        x = sx, y = sy,
        -- Lo que el barco llevaba andado al soltarlo. La resta contra el andar
        -- de ahora es lo que abre la V, y por eso la abre lo que se CORRE y no
        -- lo que se tarda.
        d = state.distance,
        age = 0,
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
        -- Tres numeros DISTINTOS de la misma gota, y por eso `hashGrid` y no
        -- `hash01`: a esta ultima el tercer argumento se le anula, asi que los
        -- tres salian el mismo numero y la gota tenia atados el costado, el
        -- tamano y la separacion del casco. Se veia sin saber que se estaba
        -- viendo: todas las gotas grandes por el mismo lado.
        local t = math.floor(state.time * 13)
        local r1 = Util.hashGrid(sprayN, t, 41)
        local r2 = Util.hashGrid(sprayN, t, 42)
        local r3 = Util.hashGrid(sprayN, t, 43)
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

    -- La superficie no guarda olas, pero si de donde las esta mirando: hay que
    -- arrastrarle el origen con lo que anda el barco y lo que desfila el agua.
    Surface.update(state, dt, Sea.state(state))

    -- La derrota se siembra con mucho menos andar del que hace falta para
    -- levantar espuma: un barco que apenas se mueve NO rompe agua por la proa,
    -- pero si deja un rastro detras, y sin el se ve quieto en un mar que
    -- desfila.
    local frac = speedFraction(state)
    if frac > 0.05 then
        shedWake(state)
        shedSpray(state, dt, frac, Sea.state(state))
    end

    -- Envejece SIEMPRE, tambien amarrado: el agua no se para porque tu si.
    for i = #wake, 1, -1 do
        local p = wake[i]
        p.age = p.age + dt
        if p.age > WAKE_LIFE or state.distance - p.d > WAKE_RUN then
            table.remove(wake, i)
        end
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

local function drawScenery(state)
    local cell = Sea.SCENERY_CELL
    forEachCell(state.x, state.y, cell, 40, function(cx, cy)
        local roll = Util.hash01(state.seed + cx, cy, 21)
        if roll <= 0.72 then return end
        -- Lo mismo aqui: con `hash01` los dos desplazamientos salian iguales
        -- y todas las islas caian clavadas en la diagonal de su casilla.
        local wx = (cx + Util.hashGrid(cx, cy, 22)) * cell
        local wy = (cy + Util.hashGrid(cx, cy, 23)) * cell
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

-- La derrota, tal y como la quiere el shader: en pixeles de arte, del barco
-- hacia atras, y con la eslora y la manga del casco con las que se dibuja.
--
-- Los dos primeros puntos SON el barco -- roda y espejo --, y van en
-- coordenadas de pantalla porque el barco esta siempre en el mismo pixel con
-- la proa arriba. Es lo que cierra la calle en punta por delante: la roda
-- cuenta como derrota "negativa" (`run = -eslora`), asi que la manga que
-- reparte el shader vale cero justo ahi y va abriendose a lo largo del casco
-- hasta la manga entera, que es la que deja por detras.
--
-- La derrota se REMUESTREA: en el shader caben veinticuatro puntos y en la
-- lista hay hasta ochenta, pero la distancia a un segmento es exacta por muy
-- separados que esten sus extremos, asi que se coge uno de cada tantos y la
-- estela no pierde ni un pixel de largo.
local function wakeTrack(state)
    local cx, cy = Constants.shipAnchor()
    local hullW, hullH = Art.size("ship.hull")
    local len  = Art.HULL_BOX.h * hullH
    local beam = Art.HULL_BOX.w * hullW / 2

    local track = {
        { x = cx, y = cy - len / 2, run = -len, left = 1 },
        { x = cx, y = cy + len / 2, run = 0,    left = 1 },
    }

    local room = Surface.TRACK - #track
    local stride = math.max(1, math.ceil(#wake / room))
    for i = 1, #wake, stride do
        local p = wake[i]
        local x, y = Sea.project(state, p.x, p.y)
        local run = state.distance - p.d
        track[#track + 1] = {
            x = x, y = y,
            run  = run,
            -- Se apaga por lo andado, y el reloj es solo el tope del barco
            -- parado. La raiz deja la estela con cuerpo casi hasta el final en
            -- vez de irse apagando desde el primer pixel.
            left = math.sqrt(Util.clamp(math.min(1 - run / WAKE_RUN,
                                                 1 - p.age / WAKE_LIFE), 0, 1)),
        }
        if #track >= Surface.TRACK then break end
    end

    return { track = track, beam = beam, hull = len,
             bow = bowFraction(state), wash = washFraction(state) }
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
    Surface.draw(state, Sea.state(state), wakeTrack(state))
    drawScenery(state)
    drawPorts(state)
    drawSpray(state)
    drawHeadingGuide(state)
end

return Sea
