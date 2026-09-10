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
-- angulo que elegir. La estela es el mismo arco sembrado por popa, y tampoco
-- lo tiene: se queda en su punto del mundo, pero se dibuja siempre derecho,
-- porque una cresta transversal cruza la derrota y la derrota apunta arriba.
--
-- Ademas, nada del mar se guarda EN LA PARTIDA: islas, escollos, puertos y el
-- reparto de las olas salen de la posicion del mundo y de la semilla, y la
-- estela, las salpicaduras y lo andado por el desfile viven en este modulo y se
-- ponen a cero al entrar (Sea.reset). El mar es infinito y ocupa cero bytes del
-- fichero de guardado.

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

-- Lo que se mueve el agua POR SI SOLA, en pixeles de mundo por segundo:
-- {calma, lo que suma el viento duro}. Es la animacion del mar, y hay que
-- separarla de lo otro que se ve moverse en pantalla, que es el barco cruzando
-- el campo: eso ultimo son otros diez pixeles por segundo y no sale de aqui.
--
-- El mar viejo desfilaba a treinta y uno y las rachas a noventa y seis --
-- cuatro y catorce veces lo que anda el barco. Ahora la ola hace siete
-- decimas y la racha dos y pico: el agua esta practicamente quieta y lo que
-- desfila es el barco pasando por ella, que es como se ve el mar desde una
-- cubierta. Un campo de agua corriendo por su cuenta no se lee como viento --
-- se lee como que el barco cia a toda maquina.
--
-- La factura de tenerlo tan bajo hay que saberla: el desfile ya no dice HACIA
-- DONDE sopla, porque a siete decimas contra los diez del barco no se aprecia.
-- De donde sopla lo siguen diciendo las orientaciones -- la cresta peinada
-- contra el viento y la racha a favor, a noventa grados una de otra --, que es
-- la lectura buena y la que vigila la prueba. Si algun dia hace falta
-- recuperar la otra, se sube esto, no se toca el barco.
--
-- La racha va mas deprisa que la ola porque es el viento TOCANDO la
-- superficie, no la superficie moviendose. El techo de las dos sigue siendo
-- Ship.BASE_SPEED, y ahi las ata tests/test_sea.lua.
Sea.WAVE_DRIFT = { 0.15, 0.55 }
Sea.GUST_DRIFT = { 0.8, 2.0 }

-- Y a que ritmo respira el tren de olas, en radianes por segundo, con el mismo
-- reparto {calma, lo que suma el viento}. Medio minuto por vaiven con viento
-- duro: una mar de fondo tarda en pasar y no tiembla.
Sea.SURGE_RATE = { 0.09, 0.11 }

--==========================================================================
-- El desfile
--==========================================================================
--
-- Donde ha llegado el campo de olas y el de rachas, y por donde va el vaiven
-- del tren. Se INTEGRAN aqui, cuadro a cuadro, y ese es todo el motivo de que
-- existan estas cuatro variables.
--
-- Antes se sacaban de state.time por el ritmo del momento -- drift = t * v(t),
-- fase = t * w(t) -- y parecia lo mismo, pero no lo es: el viento rola y
-- refresca sin parar (World.updateWind), asi que multiplicar el tiempo VIVIDO
-- por el ritmo de AHORA reescribe hacia atras el desfile entero cada vez que
-- cambia el viento. Lo que se ve moverse no es v, es
--
--     d(t * v(t))/dt  =  v  +  t * dv/dt
--
-- y el segundo sumando crece con las horas de partida sin techo ninguno. Medido
-- en el juego: a la hora de travesia las olas iban a 3 px/s en vez de a 0,7; a
-- las dos, a 9,9; a las ocho, a 39,7 -- mas deprisa que el mar viejo que
-- llevabamos tres arreglos intentando calmar -- y las rachas a 146, con el
-- tren de olas hirviendo a 7,6 radianes por segundo. Y pasaba AMARRADO, que es
-- donde canta, porque en puerto el barco no cruza el campo y el desfile se
-- queda solo en pantalla.
--
-- Integrando, el ritmo es el ritmo: rolar el viento cambia hacia donde se
-- mueve el campo de aqui en adelante, no lo que ya habia andado.
--
-- El precio es que el mar deja de ser funcion pura de state.time y pasa a
-- depender de los cuadros que se han dibujado. No se guarda nada en la partida
-- (Sea.reset lo pone a cero al entrar a la travesia), asi que la regla de
-- "nada del mar se guarda" sigue en pie; lo que se pierde es que dos partidas
-- en el mismo instante vean la misma ola, y eso no lo miraba nadie.
local waveX, waveY = 0, 0
local gustX, gustY = 0, 0
local surge = 0

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
-- La estela ES EL BIGOTE DE PROA, estirado hacia atras.
--
-- Vista desde arriba, la estela de un barco no es una fila de puntos ni dos
-- brazos rectos: son crestas TRANSVERSALES, la misma uve que la roda levanta
-- delante, que van quedando por popa y abriendose. Asi que aqui no hay dos
-- dibujos distintos para la proa y para la popa -- hay uno, el arco, en una
-- escalera de cinco anchos (sea.wake1..5 en src/art.lua), sembrado por el
-- espejo de popa y elegido por lo LEJOS que ha quedado.
--
-- Antes eran un remolino de puntos por la crujia mas dos brazos de gotas. Los
-- puntos se leian como una fila de migas y los brazos, sueltos del arco que
-- tenian que cerrar, como dos rastros de espuma que no salian de ningun sitio.
-- Un arco entero se lee de golpe.
--
-- Lo que se conserva de aquello es lo unico que importaba: el ancho se elige
-- con state.distance y no con el reloj, que es la misma cuenta que hace el
-- agua. Un barco parado no abre estela; uno lanzado la tiene larga y ancha; y
-- en una virada se dobla sola, porque cada arco se queda en el punto de MUNDO
-- donde se solto y es la camara la que gira.
--
-- Los arcos se pintan ENCIMA del barco (Sea.drawWake, que llama voyage.lua
-- despues del casco). Es lo que deja que el primero muerda el espejo de popa
-- en vez de nacer despegado de el: el agua que revuelve la popa esta contra la
-- popa, y con la estela debajo del casco habia que sembrarla media eslora mas
-- atras para que asomara.

local wake, spray = {}, {}
local WAKE_MAX  = 16
local SPRAY_MAX = 48
local SEED_STEP = 6      -- un arco de estela cada tantos pixeles de mundo
local WAKE_SPAN = 45     -- hasta donde llega la estela por popa, en pixeles
local WAKE_ARCS = 5      -- escalones de la escalera de anchos
-- La estela nace PISANDO el espejo de popa (el casco mide 82 pixeles de proa a
-- popa, asi que el espejo cae a 41 del centro) y la salpicadura DELANTE de la
-- roda. Lo segundo si tiene que salir del casco: las gotas se pintan debajo
-- del barco, y sembradas mas adentro pasan media vida escondidas.
local STERN     = 38
local BOW       = 42

local lastX, lastY, lastDist
local sprayAcc, sprayN = 0, 0

function Sea.reset()
    wake, spray = {}, {}
    lastX, lastY, lastDist = nil, nil, nil
    sprayAcc, sprayN = 0, 0
    waveX, waveY, gustX, gustY, surge = 0, 0, 0, 0, 0
end

-- Lo andado por el campo, para tests/test_sea.lua: que el desfile no acelere
-- con las horas de partida no se ve mirando la pantalla -- se ve restando dos
-- medidas con ocho horas de diferencia.
function Sea.drift()
    return waveX, waveY, gustX, gustY, surge
end

local function shedWake(state, frac)
    local fx, fy = Util.headingToVector(state.heading)
    local sx = state.x - fx * STERN
    local sy = state.y - fy * STERN
    if lastX and Util.dist(lastX, lastY, sx, sy) <= SEED_STEP then return end
    lastX, lastY = sx, sy
    table.insert(wake, 1, {
        x = sx, y = sy,
        d = state.distance,
        age = 0,
        life = 4 + 8 * frac,
        -- Hasta donde llega ESTE arco, y es lo unico que la velocidad decide.
        --
        -- El ANGULO de la uve no se toca: el escalon se elige por los pixeles
        -- que ha quedado atras, asi que la estela se abre siempre a los mismos
        -- diecinueve grados, como en el agua. Lo que cambia con lo que se
        -- corre es lo LARGA que es: a buen andar los arcos viven para recorrer
        -- la escalera entera y la uve sale hasta el borde de la pantalla; en el
        -- ojo del viento se deshacen en el segundo escalon y por popa no queda
        -- mas que un hervor pegado al codaste.
        --
        -- Se congela al soltarlo en vez de leerse del barco al dibujar porque
        -- si no, aflojar trapo ensancharia de golpe la estela ya sembrada: los
        -- arcos de atras saltarian de escalon sin haberse movido.
        reach = WAKE_SPAN * (0.30 + 0.70 * frac),
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

    -- El desfile, integrado: se suma lo que el campo anda EN ESTE cuadro, al
    -- ritmo de este cuadro. Ver el bloque "El desfile" mas arriba -- es la
    -- diferencia entre un mar que va a lo que dicen WAVE_DRIFT/GUST_DRIFT y uno
    -- que acelera segun se juega.
    local sea = Sea.state(state)
    local tx, ty = windVector(state)
    local vWave = (Sea.WAVE_DRIFT[1] + Sea.WAVE_DRIFT[2] * sea) * dt
    local vGust = (Sea.GUST_DRIFT[1] + Sea.GUST_DRIFT[2] * sea) * dt
    waveX, waveY = waveX + tx * vWave, waveY + ty * vWave
    gustX, gustY = gustX + tx * vGust, gustY + ty * vGust
    surge = surge + (Sea.SURGE_RATE[1] + Sea.SURGE_RATE[2] * sea) * dt

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

    -- Envejece SIEMPRE, tambien amarrado: el agua no se para porque tu si. Un
    -- arco se va por lo que tarda o por lo lejos que queda, lo que llegue
    -- antes: parado se deshace solo, y a buen andar se sale del abanico.
    for i = #wake, 1, -1 do
        local p = wake[i]
        p.age = p.age + dt
        if p.age > p.life or state.distance - p.d > p.reach then
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
    -- cual se barren las celdas, asi que el mar avanza sin costura. Lo andado
    -- se integra en Sea.update y no se saca de state.time; el porque, arriba.
    local ox, oy = waveX, waveY
    local cell = Sea.WAVE_CELL

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
        --
        -- Respira MUY despacio, medio minuto por vaiven (SURGE_RATE). Empezo
        -- en dos radianes por segundo -- tres subidas y bajadas cada diez
        -- segundos -- y era la otra mitad del agua nerviosa: el desfile ponia
        -- la carrera y esto ponia el hervor. La fase tambien se integra, y por
        -- lo mismo: multiplicada por state.time llegaba a 7,6 rad/s a las ocho
        -- horas, que es el mar entero hirviendo una vez por segundo.
        local along = wx * tx + wy * ty
        local lift = math.sin(along * 0.075 - surge) * (0.5 + 2.2 * sea)

        local x, y = Sea.project(state,
                                 wx + ox + tx * lift,
                                 wy + oy + ty * lift)
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
    local ox, oy = gustX, gustY
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

-- La estela, y va PUBLICA porque se pinta fuera de Sea.draw: voyage.lua la
-- llama despues del casco para que el primer arco pise el espejo de popa.
function Sea.drawWake(state)
    for _, p in ipairs(wake) do
        -- Lo lejos que ha quedado este arco, en fraccion del abanico. Se mide
        -- con lo ANDADO -- que es lo que hace el agua -- y por eso un barco
        -- parado deja de abrir la estela en el sitio, sin encogerla.
        local behind = Util.clamp((state.distance - p.d) / WAKE_SPAN, 0, 1)

        -- Se apaga por lo que llegue antes: por haberse acabado su alcance o
        -- por viejo. Lo segundo es lo unico que deshace la estela de un barco
        -- que se ha parado, que si no se quedaria clavada en el agua.
        local k = math.max((state.distance - p.d) / p.reach, p.age / p.life)
        k = Util.clamp(k, 0, 1)

        local x, y = Sea.project(state, p.x, p.y)
        if onScreen(x, y, 28) then
            love.graphics.setColor(foamColor(k))
            local step = math.min(math.floor(behind * WAKE_ARCS) + 1, WAKE_ARCS)
            Art.drawCentered("sea.wake" .. step, x, y)
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
    drawSpray(state)
    drawBowWave(state)
    drawHeadingGuide(state)
end

return Sea
