-- La gente de cubierta.
--
-- Este modulo dice DONDE esta cada tripulante sobre el lienzo del barco y lo
-- pinta ahi. Nada mas: no aporta un solo numero a la simulacion y no guarda un
-- solo byte en la partida. Es adorno, como la estela de src/sea.lua, y por eso
-- vive aparte de src/world.lua.
--
-- La regla que lo ordena todo: el paseo es FUNCION PURA de state.time y del
-- nombre del tripulante. No hay velocidades, ni destinos, ni un update() que
-- integrar. Sale de ahi casi todo lo que importa:
--
--   * no hay estado que anadir a DEFAULTS ni que migrar;
--   * volver despues de ocho horas no encuentra a nadie donde lo dejaste,
--     porque state.time avanzo con la puesta al dia -- que es justo lo que
--     debe pasar, y sale gratis;
--   * un paso de 1/30 y uno de 2 s dan el mismo dibujo, igual que el viento.
--
-- Cada uno anda su Lissajous: dos senos de periodos que no casan, con la fase
-- y el compas sacados del hash de su nombre. Con periodos que no son multiplos
-- la figura no se cierra nunca y no se ve el bucle; con la fase por nombre,
-- catorce tripulantes no marchan a la vez.
--
-- DOS PASEOS, y la diferencia es la que pidio el juego:
--
--   * destinado -> se queda EN su puesto y se mueve dos pixeles alrededor. Un
--     tripulante clavado se lee como un icono, no como una persona, pero uno
--     que se aleja de su puesto rompe lo unico que la cubierta explica bien,
--     que es quien esta trabajando en que. Dos pixeles es el compromiso: a
--     este grano ya es un cuerpo que se remueve, y el aro del puesto le sigue
--     quedando debajo.
--   * sin destino -> pasea el barco entero. El ancho por el que puede andar
--     sale de Art.hullHalf, la misma silueta con la que se dibuja el casco, y
--     por eso el paseo se estrecha solo hacia la proa en vez de sacar a nadie
--     por encima de la borda.
--
-- A la velocidad de aqui abajo cada tripulante cambia de pixel mas o menos una
-- vez por segundo. Se andan de uno en uno porque Art.draw redondea, y un seno
-- lento redondeado son escalones limpios: no hay nada que amortiguar como en
-- la driza, porque un seno no cambia de sentido mas que en sus dos extremos, y
-- ahi se para en vez de temblar.

local Util     = require('src.util')
local Art      = require('src.art')
local Ship     = require('src.ship')
local Crew     = require('src.crew')
local Stations = require('src.stations')

local Deck = {}

-- Cuanto se remueve un tripulante en su puesto, en pixeles de arte.
Deck.POSTED_R = 2

-- Compases, en radianes por segundo. Los del que pasea son mucho mas lentos
-- porque recorre setenta pixeles y no cuatro: con el compas del destinado
-- cruzaria el barco de proa a popa en cinco segundos, que no es pasear.
local POSTED_RATE = 0.62   -- ~10 s por vaiven
local ROAM_RATE   = 0.10   -- ~63 s de proa a popa
local RATIO       = 0.61   -- lo que se desfasa el eje corto: la figura no cierra

-- Franja de eslora por la que se pasea, en fraccion del casco. No llega ni al
-- 0 ni al 1 porque el tripulante mide ocho pixeles y se cuenta por su centro:
-- pegado a la roda asomaria media cabeza por delante del barco.
local ROAM_BOW, ROAM_STERN = 0.14, 0.88

-- Cuanto se retira de la borda, en pixeles de arte. Cuatro son la mitad del
-- sprite y uno mas es la obra muerta: con menos, el hombro de babor se sube
-- encima de la regala.
local GUNWALE = 5

-- Compas propio de un tripulante: fase de cada eje y un ritmo dentro de un
-- margen del base. Sin ese margen dos tripulantes del mismo puesto se mueven
-- en paralelo y se lee como una cinta transportadora.
local function gait(member, rate)
    local seed = Crew.seed(member)
    return Util.hash01(seed, 1, 0) * Util.TAU,               -- fase del eje largo
           Util.hash01(seed, 2, 0) * Util.TAU,               -- fase del eje corto
           rate * (0.8 + Util.hash01(seed, 3, 0) * 0.4)
end

-- Donde esta un tripulante DESTINADO, en pixeles del lienzo del barco.
--
-- El reparto por plaza (slot) es el mismo que habia antes de que la gente se
-- moviera: cuatro pixeles entre uno y otro, centrados en el puesto, para que
-- dos gavieros se vean como dos cabezas y no como una.
local function postedSpot(member, slot, mates, ax, ay, t)
    local p1, p2, w = gait(member, POSTED_RATE)
    local x = ax + (slot - 1) * 4 - (mates - 1) * 2 + Deck.POSTED_R * math.sin(w * t + p1)
    local y = ay + Deck.POSTED_R * math.sin(w * RATIO * t + p2)
    return x, y
end

-- Donde esta un tripulante SIN DESTINO. La eslora la anda el seno; el ancho no
-- es un seno suelto sino una FRACCION de la manga que hay a esa altura, asi
-- que la silueta del casco es la que le pone los limites y no hay que
-- recortar nada despues.
local function roamSpot(member, t, w, h)
    local p1, p2, rate = gait(member, ROAM_RATE)
    local bx, by, bw, bh = Art.hullRect(w, h)
    local maxHalf = (bw - 1) / 2

    local along = ROAM_BOW + (ROAM_STERN - ROAM_BOW) * (math.sin(rate * t + p1) + 1) / 2
    local half = math.max(0, Art.hullHalf(along, maxHalf) - GUNWALE)

    local x = bx + maxHalf + half * math.sin(rate / RATIO * t + p2)
    local y = by + along * (bh - 1)
    return x, y
end

-- Recorre a toda la tripulacion llamando a fn(spriteId, x, y) con el centro
-- del tripulante en pixeles del lienzo del barco. No construye ninguna tabla:
-- esto se llama una vez por cuadro.
function Deck.each(state, w, h, fn)
    local t = state.time

    for _, def in ipairs(Stations.list) do
        local ax, ay = Ship.deckPoint(def, w, h)
        local mates = Ship.crewAt(state, def.id)
        for slot, member in ipairs(mates) do
            local x, y = postedSpot(member, slot, #mates, ax, ay, t)
            fn(Art.crewFace(Crew.face(member)), x, y)
        end
    end

    for _, member in ipairs(state.crew) do
        if not member.station then
            local x, y = roamSpot(member, t, w, h)
            fn(Art.crewFace(Crew.face(member)), x, y)
        end
    end
end

-- Pinta la tripulacion con la esquina del lienzo del barco en (ox, oy).
--
-- Quien llame a esto tiene que hacerlo ANTES de las velas: el trapo va por
-- encima de la cubierta y la gente anda por debajo. Con la gente encima del
-- pano el barco deja de leerse como un barco y parece una cubierta con el
-- aparejo pintado detras.
local paintX, paintY
local function paint(id, x, y)
    Art.drawCentered(id, paintX + x, paintY + y)
end

function Deck.draw(state, ox, oy, w, h)
    paintX, paintY = ox, oy
    Deck.each(state, w, h, paint)
end

return Deck
