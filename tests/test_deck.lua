-- Prueba de la gente de cubierta, sin ventana.
--
--     lua5.1 tests/test_deck.lua      (o lua / luajit)
--
-- Corre sin love porque src/art.lua no llama a love hasta que se le pide un
-- sprite: al cargarlo solo se construye la tabla de registro y la geometria
-- del casco, que es justo lo que se mide aqui.
--
-- Esta prueba existe porque los dos fallos de la tripulacion que pasea no se
-- ven mirando la pantalla un rato:
--
--   * un tripulante sin destino que sale por la borda y anda sobre el agua.
--     Pasa cada varios minutos, en la punta de un seno, y con el trapo largo
--     tapando media cubierta no se pilla ni queriendo. Aqui se barren mil
--     instantes de cada uno y se comprueba contra la MISMA silueta con la que
--     se dibuja el casco (Art.hullHalf), que es lo unico que lo demuestra.
--   * una cara fuera de la reserva, que en el juego es un sprite desconocido y
--     un crash al entrar en la travesia -- no al arrancar, que es lo peor de
--     todo, porque el arranque parece sano.
--
-- Y de propina la que sostiene a las dos: que el paseo sea funcion pura del
-- tiempo. En cuanto alguien le meta una velocidad y un dt, la vuelta a la
-- partida despues de ocho horas dejara de cuadrar y esto lo dira.

package.path = "./?.lua;" .. package.path

local World = require('src.world')
local Crew  = require('src.crew')
local Deck  = require('src.deck')
local Art   = require('src.art')

local failures = 0
local checks = 0

local function check(name, ok, detail)
    checks = checks + 1
    if ok then
        print("  ok   " .. name)
    else
        failures = failures + 1
        print("  FALLA " .. name .. (detail and ("  -> " .. detail) or ""))
    end
end

-- El lienzo del barco, tal como lo registra src/art.lua. No se lee de
-- Art.size porque eso pide una imagen y aqui no hay ventana.
local W, H = 80, 96

-- Media anchura del sprite de un tripulante: 8 px de ancho, contado desde su
-- centro. Es lo que no puede asomar por fuera de la borda.
local HALF_SPRITE = 4

--== Caras =================================================================

print("== caras ==")
do
    local out, seen = {}, {}
    for i = 1, 400 do
        local member = Crew.candidate(7, i % 13, math.floor(i / 13), i)
        local face = Crew.face(member)
        out[i] = face
        seen[face] = true
    end

    local inRange = true
    for _, face in ipairs(out) do
        if face < 1 or face > Crew.FACES or face ~= math.floor(face) then
            inRange = false
        end
    end
    check("toda cara cae dentro de la reserva", inRange)

    local used = 0
    for _ in pairs(seen) do used = used + 1 end
    check("se usan todas las caras", used == Crew.FACES,
          used .. "/" .. Crew.FACES)

    -- Lo que hace que no haga falta guardar la cara: el mismo nombre da
    -- siempre la misma. Si esto falla, la tripulacion se cambia de cara al
    -- cargar la partida.
    local member = Crew.candidate(7, 3, 1, 9)
    local twin = { name = member.name, role = "cook", skill = 1 }
    check("la cara sale del nombre y de nada mas",
          Crew.face(member) == Crew.face(twin))

    -- Y toda la reserva esta registrada: sin esto, Art.crewFace devuelve un id
    -- que Art.get no conoce y la travesia revienta al pintar.
    local registered = {}
    for _, entry in ipairs(Art.SPRITES) do registered[entry[1]] = entry end
    local missing
    for i = 1, Crew.FACES do
        local entry = registered[Art.crewFace(i)]
        -- El generador es obligatorio: una cara es la unica capa que no puede
        -- faltar, porque no hay tripulacion opcional.
        if not (entry and entry[5]) then missing = i end
    end
    check("la reserva entera esta registrada, con respaldo generado",
          missing == nil, "falta la cara " .. tostring(missing))
end

--== El paseo ==============================================================

-- Recoge a todo el mundo en un instante. Deck.each no construye tablas a
-- proposito, asi que aqui se hace una para poder mirarla.
local function snapshot(state, t)
    state.time = t
    local out = {}
    Deck.each(state, W, H, function(id, x, y)
        out[#out + 1] = { id = id, x = x, y = y }
    end)
    return out
end

print("== nadie se cae al agua ==")
do
    local state = World.new(31)
    World.undock(state)

    -- Una tripulacion gorda y toda suelta: los que pasean son los que pueden
    -- salirse, asi que se les quita el destino a todos.
    for i = 1, 12 do
        local member = Crew.candidate(31, i, 0, i * 5)
        table.insert(state.crew, member)
    end
    for _, member in ipairs(state.crew) do member.station = nil end

    local bx, by, bw, bh = Art.hullRect(W, H)
    local maxHalf = (bw - 1) / 2
    local centre = bx + maxHalf

    local worst, worstAt = -1, nil
    for step = 0, 2000 do
        local t = step * 0.7
        for _, f in ipairs(snapshot(state, t)) do
            local along = (f.y - by) / (bh - 1)
            local half = Art.hullHalf(along, maxHalf)
            -- Cuanto se sale por la banda: negativo es que sobra borda.
            local over = math.abs(f.x - centre) + HALF_SPRITE - half
            if over > worst then worst, worstAt = over, t end
            if along < 0 or along > 1 then worst, worstAt = 999, t end
        end
    end
    check("ningun paseante asoma por fuera de la borda", worst <= 0,
          string.format("se sale %.2f px hacia el segundo %.0f", worst, worstAt or -1))

    -- Y pasean de verdad: si alguien deja el paseo clavado, esto lo canta.
    local a, b = snapshot(state, 0), snapshot(state, 45)
    local moved = 0
    for i, f in ipairs(a) do
        if math.abs(f.x - b[i].x) + math.abs(f.y - b[i].y) > 3 then
            moved = moved + 1
        end
    end
    check("y se mueven", moved == #a, moved .. "/" .. #a)
end

print("== los destinados no se van del puesto ==")
do
    local Ship = require('src.ship')
    local Stations = require('src.stations')

    -- Un puesto lleno del todo: nivel maximo, que es cuando mas plazas hay y
    -- cuando el reparto separa mas a los de las puntas.
    local plazas = Stations.capacity(Stations.MAX_LEVEL)
    local state = World.new(52)
    World.undock(state)
    state.crew = {}
    for i = 1, plazas do
        local member = Crew.candidate(52, i, 0, i * 3)
        member.station = "sails"
        table.insert(state.crew, member)
    end

    local ax, ay = Ship.deckPoint(Stations.byId.sails, W, H)

    local far = 0
    for step = 0, 1500 do
        for _, f in ipairs(snapshot(state, step * 0.4)) do
            local d = math.max(math.abs(f.x - ax), math.abs(f.y - ay))
            if d > far then far = d end
        end
    end

    -- El limite es un numero escrito a mano y NO derivado de Deck.POSTED_R: si
    -- se saca de la constante que se quiere vigilar, subirla se aprueba sola.
    --
    -- Diez pixeles son los ocho del reparto de la ultima plaza mas los dos del
    -- vaiven. Es tambien lo que se puede gastar: pasado eso el tripulante se
    -- planta en el puesto de al lado, y en esta cubierta el puesto se lee por
    -- donde esta la gente.
    check("nadie se aleja de su puesto mas de 10 px", far <= 10,
          string.format("%.2f px con %d plazas", far, plazas))
end

print("== el paseo es funcion pura del tiempo ==")
do
    local state = World.new(88)
    World.undock(state)
    table.insert(state.crew, Crew.candidate(88, 1, 0, 4))
    state.crew[#state.crew].station = nil

    -- Mismo instante, dos formas de llegar a el: de un salto y a saltitos.
    local direct = snapshot(state, 900)
    snapshot(state, 0)
    for step = 1, 30 do snapshot(state, step * 30) end
    local walked = snapshot(state, 900)

    local same = true
    for i, f in ipairs(direct) do
        if f.x ~= walked[i].x or f.y ~= walked[i].y or f.id ~= walked[i].id then
            same = false
        end
    end
    check("el mismo state.time da el mismo sitio", same)
end

print(string.format("\n%d comprobaciones, %d fallos", checks, failures))
os.exit(failures == 0 and 0 or 1)
