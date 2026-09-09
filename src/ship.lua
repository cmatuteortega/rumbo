-- El barco: de estado a numeros.
--
-- Este modulo no guarda nada. Recibe el estado del mundo y devuelve los
-- ritmos con los que la simulacion avanza ese instante. Todo el balance del
-- juego esta en las constantes de arriba y en las cinco funciones de abajo;
-- src/world.lua solo las aplica.
--
-- Regla que conviene mantener: un puesto vale nivel + pericia destinada, y
-- nada mas. Ni bonus ocultos ni estados temporales guardados en el puesto. Si
-- algo tiene que durar en el tiempo, vive en el estado del mundo, no aqui,
-- porque estas funciones se llaman tambien para simular horas de golpe al
-- volver a la partida y tienen que dar lo mismo en un paso de 1/30 que en uno
-- de 2 segundos.

local Stations = require('src.stations')
local Crew     = require('src.crew')
local Util     = require('src.util')

local Ship = {}

-- La bodega es la valvula de todo el idle, y esta escrita con tres reglas que
-- costaron un par de intentos:
--
--   1. La bodega solo guarda MERCANCIA (pescado y raciones). La madera es
--      pertrecho y tiene su propio tope aparte. Al principio ocupaba bodega y
--      el resultado era que una bodega llena de pescado dejaba al carpintero
--      sin material y el casco se caia a cero mientras dormias.
--   2. La soldada se devenga PROPORCIONALMENTE AL SITIO LIBRE, no a secas.
--      Una tripulacion cobra por lo que estiba, y con la bodega llena no
--      estiba. Sin eso, el coste de una ausencia crecia sin techo mientras el
--      ingreso lo tenia, y ocho horas fuera salian a perder. Es proporcional y
--      no un interruptor porque el rancho va abriendo hueco continuamente: un
--      "llena / no llena" oscilaba y devengaba a ratos.
--   3. La cocina para cuando las raciones ocupan media bodega. No se cocina lo
--      que no se va a comer, y asi la otra mitad queda libre para pescado, que
--      es lo que se vende.
--
-- Juntas hacen que una ausencia rinda exactamente lo que quepa en bodega, y
-- que subir la bodega sea comprar horas de idle: la palanca que un idle
-- necesita tener.
Ship.BASE_SPEED     = 7.0    -- px de mundo por segundo con vela a tope
Ship.BASE_TURN      = 0.12   -- rad/s sin timonel
Ship.HULL_WEAR      = 0.012  -- puntos de casco por segundo, navegando
Ship.CREW_UPKEEP    = 0.0025 -- raciones por segundo y tripulante
Ship.FISH_PER_RATION = 2     -- pescado que se gasta por racion cocinada
Ship.WOOD_MAX       = 80     -- pertrechos: la madera no compite con la carga
Ship.DAY = 600               -- segundos de travesia que cuentan como un dia

--== Puestos ===============================================================

function Ship.crewAt(state, stationId)
    local out = {}
    for _, member in ipairs(state.crew) do
        if member.station == stationId then out[#out + 1] = member end
    end
    return out
end

-- Potencia de un puesto: su nivel mas la pericia de quien esta destinado.
-- Es el unico numero que la simulacion mira de un puesto.
function Ship.power(state, stationId)
    local def = Stations.byId[stationId]
    local slot = state.stations[stationId]
    if not (def and slot) then return 0 end
    local p = slot.level
    for _, member in ipairs(Ship.crewAt(state, stationId)) do
        p = p + Crew.contribution(member, def)
    end
    return p
end

--== Bodega ================================================================

-- Mercancia a bordo. Las monedas no ocupan (caben en un cofre) y la madera
-- tampoco (es pertrecho, ver WOOD_MAX).
function Ship.cargo(state)
    return state.res.fish + state.res.ration
end

function Ship.capacity(state)
    return Stations.holdCapacity(Ship.power(state, "hold"))
end

function Ship.room(state)
    return math.max(0, Ship.capacity(state) - Ship.cargo(state))
end

-- Fraccion de bodega libre, en [0, 1]. Es lo que escala la soldada.
function Ship.roomFraction(state)
    local capacity = Ship.capacity(state)
    if capacity <= 0 then return 0 end
    return Util.clamp(Ship.room(state) / capacity, 0, 1)
end

-- "A la capa": queda tan poco sitio que el barco ya no produce nada util.
-- Solo sirve para avisar y para pintar la barra; el freno de verdad es
-- continuo (roomFraction), no este umbral.
function Ship.hoveTo(state)
    return Ship.roomFraction(state) <= 0.02
end

function Ship.freeSlots(state, stationId)
    local slot = state.stations[stationId]
    return Stations.capacity(slot.level) - #Ship.crewAt(state, stationId)
end

--== Navegacion ============================================================

-- Curva de ceñida. b es el angulo entre el rumbo y la direccion de DONDE
-- viene el viento: 0 = proa al viento (parado), pi = viento en popa.
-- El pico esta en el traves largo, no en popa, que es como navega un barco
-- de vela de verdad y lo que hace que elegir rumbo sea una decision.
local POINTS = {
    { 0.00, 0.10 },  -- en el ojo del viento
    { 0.44, 0.42 },  -- ceñida
    { 0.79, 0.80 },  -- descuartelar
    { 1.57, 1.00 },  -- traves
    { 2.36, 0.94 },  -- largo
    { 3.14, 0.68 },  -- popa cerrada
}

function Ship.pointing(heading, windFrom)
    -- windFrom es el rumbo DE DONDE sopla, asi que apuntar a el es apuntar al
    -- ojo del viento: b = 0 es estar parado y b = pi es viento en popa.
    local b = math.abs(Util.angleDiff(heading, windFrom))
    for i = 1, #POINTS - 1 do
        local a0, v0 = POINTS[i][1], POINTS[i][2]
        local a1, v1 = POINTS[i + 1][1], POINTS[i + 1][2]
        if b <= a1 then
            return Util.lerp(v0, v1, (b - a0) / (a1 - a0))
        end
    end
    return POINTS[#POINTS][2]
end

function Ship.hullFactor(state)  return 0.55 + 0.45 * (state.hull / 100) end
function Ship.moraleFactor(state) return 0.70 + 0.30 * (state.morale / 100) end

function Ship.speed(state)
    local trim = (state.trim == "reef") and 0.55 or 1.0
    local sailFactor = 0.55 + 0.22 * Ship.power(state, "sails")
    return Ship.BASE_SPEED * sailFactor * trim
         * Ship.pointing(state.heading, state.wind.from)
         * state.wind.strength
         * Ship.hullFactor(state) * Ship.moraleFactor(state)
end

function Ship.turnRate(state)
    return Ship.BASE_TURN + 0.05 * Ship.power(state, "helm")
end

--== Produccion ============================================================

-- Todos los ritmos del instante actual, en unidades por segundo. La vista los
-- pinta tal cual y world.lua los integra; que sean lo mismo es lo que hace
-- que el HUD no mienta.
function Ship.rates(state)
    local crewCount = #state.crew
    local nets    = Ship.power(state, "nets")
    local galley  = Ship.power(state, "galley")
    local wright  = Ship.power(state, "carpentry")
    local watch   = Ship.power(state, "crowsnest")
    local free    = Ship.roomFraction(state)
    local capacity = Ship.capacity(state)

    -- EN PUERTO NO CORRE LA SINGLADURA. Amarrado no se pesca, no se cocina, no
    -- se come de la despensa, no se cobra y no se gasta el casco: la
    -- tripulacion esta en tierra. El puerto es una pausa, y el unico coste de
    -- quedarse es todo lo que no se produce mientras tanto.
    --
    -- Sin esta regla el juego tenia un agujero feo: fijar rumbo a un puerto y
    -- cerrar la app hacia que el barco atracara pronto y se pasara siete horas
    -- amarrado comiendose la despensa, asi que volvias a una tripulacion
    -- famelica por haber hecho justo lo que el juego te invita a hacer. Los
    -- ritmos se anulan AQUI y no en world.lua para que el HUD, que los pinta
    -- tal cual, siga sin mentir mientras estas en puerto.
    local under = state.docked and 0 or 1

    -- La cocina para con media bodega en raciones: la otra mitad es para el
    -- pescado, que es lo unico que se vende.
    if state.res.ration >= capacity * 0.5 then galley = 0 end

    local wages = 0
    for _, member in ipairs(state.crew) do wages = wages + member.wage end

    -- La cocina si trabaja con la bodega llena: convierte dos de pescado en
    -- una de racion, asi que es la unica cosa a bordo que HACE SITIO. Por eso
    -- un cocinero alarga una ausencia tanto como un estibador.
    local cooking = 0.030 * galley
    -- La cocina no puede cocinar mas pescado del que hay entrando y guardado;
    -- world.lua recorta si la despensa se queda seca.
    local repairing = (state.hull < 100) and (0.03 * wright) or 0

    return {
        speed    = Ship.speed(state),
        turn     = Ship.turnRate(state),
        pointing = Ship.pointing(state.heading, state.wind.from),

        cargo    = Ship.cargo(state),
        capacity = capacity,
        hoveTo   = Ship.hoveTo(state),
        room     = free,

        fish     = 0.060 * nets * under,
        rations  = cooking * under,
        fishUsed = cooking * Ship.FISH_PER_RATION * under,

        repairs   = repairing * under,
        woodUsed  = repairing * 0.25 * under,

        wages    = (wages / 60) * free * under,
        wageFull = wages / 60,   -- lo que costaria con la bodega vacia
        upkeep = Ship.CREW_UPKEEP * crewCount * under,
        wear   = Ship.HULL_WEAR * ((state.trim == "reef") and 0.6 or 1) * under,

        lookout = 170 + 55 * watch,
        salvage = 0.008 * watch * under,
    }
end

--== Cubierta ==============================================================

-- Punto de cubierta de un puesto, en pixeles del sprite del casco. Se guarda
-- como fraccion en src/stations.lua, asi que un casco tuyo de otro tamano
-- coloca los puestos donde toca sin tocar nada.
function Ship.deckPoint(def, hullW, hullH)
    return math.floor(def.deckX * hullW), math.floor(def.deckY * hullH)
end

return Ship
