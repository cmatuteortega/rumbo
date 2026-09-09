-- La simulacion.
--
-- Todo el estado de la partida vive en una tabla plana de datos: sin
-- funciones, sin referencias circulares, sin nada que love no pueda escribir
-- a disco. Eso es lo que permite que src/save.lua sea veinte lineas y que la
-- vuelta a la partida (World.catchUp) reutilice exactamente el mismo paso de
-- simulacion que el juego en vivo, en vez de una formula aparte que se
-- desincroniza en cuanto se toca el balance.
--
-- Dos decisiones sostienen eso y conviene no romperlas:
--
--   * El viento es una FUNCION PURA del tiempo de travesia y de la semilla.
--     No se guarda ni se integra. Simular ocho horas de golpe da el mismo
--     viento que haberlas navegado.
--   * Ningun ritmo depende del tamano del paso. World.step es correcto con
--     dt = 1/30 y con dt = 2, que es como se ponen al dia las horas ausente.
--
-- Lo que NO es determinista a proposito: nada. Si algo tiene que ser
-- aleatorio, sale de Util.hash01 con el tiempo o la posicion como entrada.

local Util     = require('src.util')
local Ship     = require('src.ship')
local Stations = require('src.stations')
local Crew     = require('src.crew')
local Ports    = require('src.ports')

local World = {}

-- Version 2: bodega, soldada devengada (owed) y contadores de sucesos
-- (tally). Una partida de la version 1 no los tiene, y World.migrate los pone.
World.VERSION = 2
World.SCAN_EVERY = 2.0        -- cada cuanto se busca puerto a la vista
World.OFFLINE_CAP = 8 * 3600  -- se simulan como mucho 8 horas de ausencia
World.OFFLINE_STEP = 2.0
-- Por debajo de esto se simula igual, pero no se ensena la hoja de "mientras
-- no estabas": cerrar la app un minuto y volver a una pantalla modal que dice
-- "+0 monedas, -1 pescado" es ruido, no informacion.
World.REPORT_MIN = 300
World.LOG_MAX = 8

--==========================================================================
-- Estado
--==========================================================================

-- Valor por defecto de cada campo del estado que NO sea una lista dinamica.
-- Existe para que World.migrate pueda rellenar lo que una partida antigua no
-- tenga, y es la razon de que anadir un campo al estado no rompa las partidas
-- guardadas: se anade aqui a la vez y se rellena solo.
--
-- Las listas (crew, log) quedan fuera a proposito. Rellenarlas desde una
-- plantilla anadiria elementos fantasma — una tripulacion de la que se
-- despidio a alguien acabaria recuperandolo — asi que de esas solo se
-- garantiza que existan.
local DEFAULTS = {
    time = 0,
    x = 0, y = 0, heading = 0, target = 0,
    trim = "full",
    hull = 100, morale = 90,
    owed = 0,
    distance = 0, salvage = 0, scanTimer = 0,
    hove = false,
    quiet = false,
    wind       = { from = 0, strength = 1 },
    res        = { coin = 0, fish = 0, wood = 0, ration = 0 },
    stats      = { hired = 0, ports = 0, sold = 0 },
    tally      = { wrecks = 0, barrels = 0, ports = 0 },
    discovered = {},
    taken      = {},
}

local function fillMissing(target, template)
    for key, value in pairs(template) do
        if target[key] == nil then
            if type(value) == "table" then
                local copy = {}
                fillMissing(copy, value)
                target[key] = copy
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            fillMissing(target[key], value)
        end
    end
end

-- Pone al dia una partida guardada por una version anterior. Solo rellena lo
-- que falta: nunca pisa nada de la partida.
--
-- Se llama al cargar (src/session.lua) y antes de tocar el estado para nada
-- mas. Sin esto, una partida de la version 1 reventaba en World.step nada mas
-- entrar, al leer un campo que entonces no existia.
function World.migrate(state)
    fillMissing(state, DEFAULTS)

    state.crew = state.crew or {}
    state.log  = state.log  or {}

    -- Los puestos nuevos entran a nivel 1, como si el barco los hubiera
    -- tenido siempre. Uno que ya no exista se queda en la tabla sin molestar.
    state.stations = state.stations or {}
    for _, def in ipairs(Stations.list) do
        state.stations[def.id] = state.stations[def.id] or { level = 1 }
    end

    -- La bandera de silencio no es historia de la partida: si se guardo
    -- puesta (imposible hoy, pero una version futura podria), dejarla puesta
    -- haria una partida muda para siempre.
    state.quiet = false

    state.version = World.VERSION
    return state
end

function World.new(seed)
    seed = seed or math.floor((os.time() % 100000))

    local state = {
        version = World.VERSION,
        seed = seed,
        time = 0,
        savedAt = os.time(),

        x = 0, y = 0,
        heading = 0, target = 0,
        trim = "full",

        wind = { from = 0, strength = 1 },

        res = { coin = 60, fish = 6, wood = 10, ration = 12 },
        hull = 100, morale = 90,

        -- Las soldadas se DEVENGAN, no se cobran sobre la marcha: en alta mar
        -- no hay donde pagar. Esto es lo que se debe, y se liquida al atracar.
        owed = 0,

        -- Puerto al que se va con rumbo fijado desde la carta, o nil.
        bound = nil,

        stations = {},
        crew = {},
        discovered = {},
        taken = {},        -- candidatos ya contratados: puerto/dia/indice
        docked = nil,

        distance = 0,
        salvage = 0,
        scanTimer = 0,
        log = {},
        stats = { hired = 0, ports = 0, sold = 0 },

        -- Contadores acumulados de sucesos. Existen para que World.catchUp
        -- pueda contar lo que paso mientras no estabas exactamente igual que
        -- cuenta los recursos: restando el antes del despues. Sin ellos habria
        -- que leer la bitacora, que solo guarda ocho lineas y en ocho horas se
        -- llena doscientas veces.
        tally = { wrecks = 0, barrels = 0, ports = 0 },
    }

    for _, def in ipairs(Stations.list) do
        state.stations[def.id] = { level = 1 }
    end

    -- Se empieza amarrado en Puerto Madre con dos manos a bordo, para que la
    -- primera pantalla tenga algo que tocar en vez de un barco vacio.
    local home = Ports.get(seed, 0, 0)
    state.x, state.y = home.x, home.y + 40
    state.discovered[home.key] = true
    state.docked = home.key

    local first = Crew.candidate(seed, 0, 0, 101)
    first.role, first.station = "sail", "sails"
    local second = Crew.candidate(seed, 0, 0, 202)
    second.role, second.station = "net", "nets"
    state.crew = { first, second }

    World.updateWind(state)
    state.heading = Util.wrapAngle(state.wind.from + math.pi * 0.6)
    state.target = state.heading

    World.log(state, "Zarpas de " .. home.name .. ".")
    return state
end

-- Con state.quiet puesto no se escribe nada. Lo usa la puesta al dia: ocho
-- horas generan cientos de lineas y la bitacora tiene ocho, asi que sin esto
-- lo unico que sobrevive son los ultimos barriles y se pierde lo que importa
-- (los puertos nuevos). Los sucesos se cuentan igual en state.tally.
function World.log(state, text)
    if state.quiet then return end
    table.insert(state.log, 1, { t = state.time, text = text })
    while #state.log > World.LOG_MAX do table.remove(state.log) end
end

function World.day(state)
    return math.floor(state.time / Ship.DAY)
end

--==========================================================================
-- Viento
--==========================================================================

-- Suma de dos senos de periodo distinto: rola despacio pero nunca cae en un
-- ciclo que se pueda memorizar, y al ser puro no hay que guardarlo.
function World.updateWind(state)
    local t = state.time
    local phase = (state.seed % 997) * 0.01
    local from = math.sin(t / 240 + phase) * 1.25
              + math.sin(t / 97 + phase * 3) * 0.45
              + phase * 7
    state.wind.from = Util.wrapAngle(from)
    state.wind.strength = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t / 173 + phase * 2))
end

--==========================================================================
-- Paso de simulacion
--==========================================================================

local function spend(state, key, amount)
    local have = state.res[key]
    local paid = math.min(have, amount)
    state.res[key] = have - paid
    return paid, paid >= amount - 1e-9
end

-- Mete carga en bodega hasta donde quepa y devuelve lo que entro. Todo lo que
-- sube a bordo pasa por aqui; nada escribe state.res directamente para anadir.
-- La madera no va a la bodega: es pertrecho y tiene su propio tope, para que
-- una bodega llena de pescado no deje al carpintero sin material.
local function stow(state, key, amount)
    local added
    if key == "wood" then
        added = math.min(amount, math.max(0, Ship.WOOD_MAX - state.res.wood))
    else
        added = math.min(amount, Ship.room(state))
    end
    if added > 0 then state.res[key] = state.res[key] + added end
    return added
end

function World.step(state, dt)
    state.time = state.time + dt
    World.updateWind(state)

    local r = Ship.rates(state)

    -- Rumbo fijado desde la carta de marear. Se recalcula cada paso, asi que
    -- el barco corrige solo y llega aunque el rumbo se haya ido abriendo. Al
    -- entrar en el radio de atraque, atraca solo: esa es la mitad util de
    -- fijar rumbo, porque es lo que hace que volver despues de horas te
    -- encuentre amarrado y con la soldada liquidada en vez de pasando de
    -- largo. (Se comprueba la distancia al punto, no el segmento recorrido:
    -- vale mientras un paso de simulacion avance menos que DOCK_RADIUS, que
    -- con los 2 s de la puesta al dia da de sobra.)
    if state.bound and not state.docked then
        local port = Ports.fromKey(state.seed, state.bound)
        if not port then
            state.bound = nil
        else
            state.target = Util.wrapAngle(math.atan2(port.x - state.x, -(port.y - state.y)))
            if Util.dist(state.x, state.y, port.x, port.y) <= Ports.DOCK_RADIUS then
                state.bound = nil
                World.dock(state, port)
            end
        end
    end

    -- Caida al rumbo pedido. El timon limita cuanto se gira por segundo, asi
    -- que un rumbo nuevo tarda en cuajar: es lo que hace util al timonel.
    local diff = Util.angleDiff(state.heading, state.target)
    local maxTurn = r.turn * dt
    state.heading = Util.wrapAngle(state.heading + Util.clamp(diff, -maxTurn, maxTurn))

    if not state.docked then
        local fx, fy = Util.headingToVector(state.heading)
        local d = r.speed * dt
        state.x = state.x + fx * d
        state.y = state.y + fy * d
        state.distance = state.distance + d

        state.hull = Util.clamp(state.hull - r.wear * dt, 0, 100)
        stow(state, "fish", r.fish * dt)

        -- Restos a la deriva: el vigia los ve, no el barco. La madera ocupa
        -- bodega; las monedas del barril no, van al cofre.
        state.salvage = state.salvage + r.salvage * dt
        while state.salvage >= 1 do
            state.salvage = state.salvage - 1
            local roll = Util.hash01(state.seed, math.floor(state.time), 13)
            if roll < 0.55 then
                local n = stow(state, "wood", 1 + math.floor(roll * 5))
                if n > 0 then
                    state.tally.wrecks = state.tally.wrecks + 1
                    World.log(state, "Restos a la deriva: +" .. n .. " madera.")
                end
            else
                local n = 3 + math.floor(roll * 14)
                state.res.coin = state.res.coin + n
                state.tally.barrels = state.tally.barrels + 1
                World.log(state, "Un barril con " .. n .. " monedas.")
            end
        end
    end

    -- Aviso de bodega llena, una sola vez por vez que se llena.
    local full = Ship.hoveTo(state)
    if full and not state.hove then
        World.log(state, "Bodega llena: el barco se echa a la capa.")
    elseif not full and state.hove then
        World.log(state, "Queda sitio en bodega; a trabajar.")
    end
    state.hove = full

    -- Cocina: convierte pescado en raciones, y solo hasta donde llega el
    -- pescado guardado.
    local usedFish = spend(state, "fish", r.fishUsed * dt)
    state.res.ration = state.res.ration + usedFish / Ship.FISH_PER_RATION

    -- Rancho. Sin raciones la moral se hunde deprisa; con ellas sube despacio.
    local _, fed = spend(state, "ration", r.upkeep * dt)
    if #state.crew > 0 and not fed then
        state.morale = Util.clamp(state.morale - 0.9 * dt, 0, 100)
    else
        state.morale = Util.clamp(state.morale + 0.35 * dt, 0, 100)
    end

    -- Soldadas: se apuntan, no se cobran. Se liquidan al atracar
    -- (World.settleWages), que es cuando hay contaduria y cuando no poder
    -- pagar tiene consecuencias delante de todos.
    state.owed = state.owed + r.wages * dt

    -- Carpinteria: repara mientras haya madera.
    if r.repairs > 0 then
        local wood = spend(state, "wood", r.woodUsed * dt)
        if r.woodUsed > 0 then
            local fraction = wood / (r.woodUsed * dt)
            state.hull = Util.clamp(state.hull + r.repairs * dt * fraction, 0, 100)
        end
    end

    -- Vigia: descubrir puertos. Se hace a intervalos, no cada fotograma: es
    -- un barrido de celdas y a 60 Hz no aporta nada.
    state.scanTimer = state.scanTimer + dt
    if state.scanTimer >= World.SCAN_EVERY then
        state.scanTimer = 0
        World.scan(state, r.lookout)
    end
end

-- Avanza la simulacion en pasos fijos. El acumulador vive fuera del estado
-- guardado a proposito: no es historia de la partida.
local accumulator = 0
World.FIXED_DT = 1 / 30

function World.advance(state, dt)
    accumulator = accumulator + math.min(dt, 0.25)
    while accumulator >= World.FIXED_DT do
        accumulator = accumulator - World.FIXED_DT
        World.step(state, World.FIXED_DT)
    end
end

function World.scan(state, radius)
    for _, port in ipairs(Ports.near(state.seed, state.x, state.y, radius)) do
        if not state.discovered[port.key] then
            state.discovered[port.key] = true
            state.tally.ports = state.tally.ports + 1
            World.log(state, "Tierra a la vista: " .. port.name .. ".")
        end
    end
end

--==========================================================================
-- Vuelta a la partida
--==========================================================================

-- Simula el tiempo ausente con el mismo World.step, en pasos gruesos, y
-- devuelve el resumen que la pantalla ensena al volver.
function World.catchUp(state, seconds)
    seconds = math.min(seconds or 0, World.OFFLINE_CAP)
    if seconds <= 0 then return nil end

    local before = {
        coin = state.res.coin, fish = state.res.fish,
        wood = state.res.wood, ration = state.res.ration,
        distance = state.distance, morale = state.morale, hull = state.hull,
        owed = state.owed,
        wrecks = state.tally.wrecks, barrels = state.tally.barrels,
    }

    -- Que puertos habia descubiertos antes, para poder nombrar los nuevos.
    local known = {}
    for k in pairs(state.discovered) do known[k] = true end
    local wasDocked = state.docked

    -- Silencio: los sucesos se cuentan en tally, no se escriben.
    state.quiet = true
    local left = seconds
    while left > 0 do
        local dt = math.min(World.OFFLINE_STEP, left)
        World.step(state, dt)
        left = left - dt
    end
    state.quiet = false

    local found = {}
    for k in pairs(state.discovered) do
        if not known[k] then
            local port = Ports.fromKey(state.seed, k)
            if port then found[#found + 1] = port.name end
        end
    end
    table.sort(found)

    local summary = {
        elapsed  = seconds,
        coin     = state.res.coin - before.coin,
        fish     = state.res.fish - before.fish,
        wood     = state.res.wood - before.wood,
        ration   = state.res.ration - before.ration,
        distance = state.distance - before.distance,
        morale   = state.morale - before.morale,
        hull     = state.hull - before.hull,
        owed     = state.owed - before.owed,
        wrecks   = state.tally.wrecks - before.wrecks,
        barrels  = state.tally.barrels - before.barrels,
        ports    = found,
        hoveTo   = Ship.hoveTo(state),
        -- Si se atraco solo (rumbo fijado que llego), el resumen lo dice: es
        -- la diferencia entre volver a un puerto y volver a mitad del mar.
        arrived  = (not wasDocked and state.docked) and World.dockedPort(state) or nil,
    }

    -- Una ausencia corta se simula igual (no se pierde progreso) pero no se
    -- reporta: ni hoja ni linea de bitacora.
    if seconds < World.REPORT_MIN then return nil end

    -- Una linea, no doscientas.
    World.log(state, string.format("%s de travesia: %d hallazgos, %d puertos.",
              Util.duration(seconds), summary.wrecks + summary.barrels, #found))
    return summary
end

--==========================================================================
-- Acciones
--==========================================================================

-- Tocar el timon a mano cancela el rumbo fijado: si no, el barco corregiria
-- en el paso siguiente y el timon pareceria roto.
function World.setHeading(state, heading)
    state.target = Util.wrapAngle(heading)
    state.bound = nil
end

-- Hacer rumbo a un puerto de la carta. A partir de aqui el timonel corrige
-- solo y el barco atraca al llegar.
function World.setCourse(state, port)
    state.bound = port.key
    if state.docked then World.undock(state) end
    World.log(state, "Rumbo a " .. port.name .. ".")
end

function World.clearCourse(state)
    if not state.bound then return end
    state.bound = nil
    World.log(state, "Rumbo libre.")
end

function World.boundPort(state)
    if not state.bound then return nil end
    return Ports.fromKey(state.seed, state.bound)
end

-- El trapo se pide, no se alterna, y ahora es la unica forma que hay: quien lo
-- cambia es la driza (`src/halyard.lua`), que sabe lo que quiere dejar puesto
-- -- tirar hacia abajo desde los rizos larga trapo, y tirar dos veces no puede
-- volver a arrizarlo. Hubo un `toggleTrim` para el boton de la travesia, que
-- era el unico que pensaba en terminos de "el otro"; al quitar el boton se fue
-- con el. Es idempotente a proposito: la driza pide "largo" cada vez que
-- llega al tope, y sin esto la bitacora se llenaria de lineas repetidas.
function World.setTrim(state, trim)
    if state.trim == trim then return end
    state.trim = trim
    World.log(state, trim == "reef" and "Rizos tomados." or "Trapo largo.")
end

-- Lo que sube a bordo por el redal (`src/reel.lua`). Pasa por `stow` como
-- todo lo demas, asi que un pez cobrado con la bodega a rebosar no entra
-- entero, o no entra.
--
-- Y ESO SE DICE. Con la bodega llena se pesca igual -- es el estado en el que
-- se vuelve de una ausencia larga, y apagar ahi la pesca a mano la apagaba
-- justo cuando mas rato se lleva mirando -- asi que la pelea se puede ganar y
-- que no quepa el premio. Es mal negocio, pero es del jugador: lo que no puede
-- ser es que se pelee un pez y no pase nada visible, que es la misma averia
-- que un mando que se calla. Por eso hay linea de bitacora tambien cuando no
-- cabe, y dice cuanto se quedo fuera.
--
-- La pelea NO vive aqui: es cosa del mando y no se guarda. Lo unico que llega
-- a la simulacion es el resultado, que es tambien lo unico que sobrevive a
-- cerrar la app.
function World.landFish(state, amount)
    local added = stow(state, "fish", amount)
    if added >= amount - 1e-9 then
        World.log(state, string.format("Un buen pez a bordo: +%d pescado.",
                  math.floor(added)))
    elseif added > 0 then
        World.log(state, string.format("Un buen pez, y solo caben %d: bodega llena.",
                  math.floor(added)))
    else
        World.log(state, "Un buen pez, y no cabe: bodega llena.")
    end
    return added
end

-- Y lo que no sube. Se distingue romper la linea de que se suelte porque son
-- dos errores distintos -- haber tirado de mas y no haber tirado a tiempo --
-- y el que se lee en la bitacora es el que se corrige la vez siguiente.
function World.lostFish(state, snapped)
    World.log(state, snapped and "La linea se rompe." or "El pez se solto.")
end

function World.nearestPort(state)
    local best, bestDist
    for _, port in ipairs(Ports.near(state.seed, state.x, state.y, Ports.CELL)) do
        local d = Util.dist(state.x, state.y, port.x, port.y)
        if not bestDist or d < bestDist then best, bestDist = port, d end
    end
    return best, bestDist
end

function World.canDock(state)
    local port, d = World.nearestPort(state)
    if port and d <= Ports.DOCK_RADIUS then return port end
    return nil
end

-- Liquida la soldada devengada. Devuelve lo pagado y lo que se queda a deber.
-- Lo que no se paga NO se perdona: sigue apuntado y vuelve a intentarse en el
-- siguiente puerto. Lo que cuesta moral es el impago delante de todos, no ir
-- corto de monedas en alta mar.
function World.settleWages(state)
    local due = state.owed
    if due < 1 then return 0, 0 end

    local paid = math.min(due, state.res.coin)
    state.res.coin = state.res.coin - paid
    state.owed = due - paid

    if state.owed >= 1 then
        state.morale = Util.clamp(state.morale - math.min(25, state.owed / 4), 0, 100)
        World.log(state, string.format("Se deben %d monedas de soldada.", state.owed))
    else
        state.morale = Util.clamp(state.morale + 4, 0, 100)
        World.log(state, string.format("Soldadas al dia: %d monedas.", paid))
    end
    return paid, state.owed
end

function World.dock(state, port)
    state.docked = port.key
    state.bound = nil
    state.discovered[port.key] = true
    state.stats.ports = state.stats.ports + 1
    World.log(state, "Amarrado en " .. port.name .. ".")
    World.settleWages(state)
end

function World.undock(state)
    state.docked = nil
    World.log(state, "Largamos amarras.")
end

function World.dockedPort(state)
    return Ports.fromKey(state.seed, state.docked)
end

function World.assign(state, member, stationId)
    if stationId and Ship.freeSlots(state, stationId) <= 0 then return false end
    member.station = stationId
    return true
end

function World.hire(state, candidate)
    if state.res.coin < candidate.hire then return false, "No hay monedas." end
    state.res.coin = state.res.coin - candidate.hire
    local member = {
        name = candidate.name, role = candidate.role, skill = candidate.skill,
        wage = candidate.wage, station = nil,
    }
    table.insert(state.crew, member)
    state.stats.hired = state.stats.hired + 1
    World.log(state, "Se enrola " .. member.name .. ".")
    return true, member
end

function World.dismiss(state, member)
    for i, m in ipairs(state.crew) do
        if m == member then
            table.remove(state.crew, i)
            World.log(state, member.name .. " deja el barco.")
            -- Despedir sienta mal a los que se quedan.
            state.morale = Util.clamp(state.morale - 6, 0, 100)
            return true
        end
    end
    return false
end

function World.upgrade(state, stationId)
    local slot = state.stations[stationId]
    local def = Stations.byId[stationId]
    if slot.level >= Stations.MAX_LEVEL then return false, "Ya esta al maximo." end
    local cost = Stations.upgradeCost(slot.level)
    if state.res.coin < cost.coin then return false, "Faltan monedas." end
    if state.res.wood < cost.wood then return false, "Falta madera." end
    state.res.coin = state.res.coin - cost.coin
    state.res.wood = state.res.wood - cost.wood
    slot.level = slot.level + 1
    World.log(state, def.name .. " al nivel " .. slot.level .. ".")
    return true
end

function World.sell(state, key, amount, price)
    amount = math.min(math.floor(amount), math.floor(state.res[key]))
    if amount <= 0 then return 0 end
    state.res[key] = state.res[key] - amount
    local earned = amount * price
    state.res.coin = state.res.coin + earned
    state.stats.sold = state.stats.sold + amount
    return earned
end

-- Comprar esta limitado por dos cosas: las monedas y el sitio en bodega. Se
-- compra lo que quepa, no todo lo que se pueda pagar.
function World.buy(state, key, amount, price)
    local space = (key == "wood") and (Ship.WOOD_MAX - state.res.wood)
                                   or Ship.room(state)
    local affordable = math.min(amount, math.floor(state.res.coin / price),
                                math.floor(space))
    if affordable <= 0 then return 0 end
    state.res.coin = state.res.coin - affordable * price
    state.res[key] = state.res[key] + affordable
    return affordable
end

function World.repair(state, price)
    local missing = 100 - state.hull
    if missing <= 0.5 then return 0 end
    local affordable = math.min(missing, state.res.coin / price)
    if affordable <= 0.5 then return 0 end
    state.res.coin = state.res.coin - affordable * price
    state.hull = state.hull + affordable
    World.log(state, "Casco calafateado.")
    return affordable
end

return World
