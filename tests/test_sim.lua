-- Prueba de la simulacion, sin ventana.
--
--     lua5.1 tests/test_sim.lua      (o lua / luajit)
--
-- Cubre lo que no se ve mirando la pantalla y es lo primero que se rompe al
-- tocar el balance:
--
--   * el mundo es determinista con la misma semilla;
--   * el viento es funcion pura del tiempo, no de como se llego a el;
--   * simular una hora de golpe (vuelta a la partida) da practicamente lo
--     mismo que haberla jugado en pasos de 1/30;
--   * los puertos existen donde el hash dice y en ningun otro sitio.
--
-- Ningun modulo que toque aqui puede requerir love: esa es justo la razon de
-- que la simulacion viva separada del dibujo.

package.path = "./?.lua;" .. package.path

local World    = require('src.world')
local Ship     = require('src.ship')
local Ports    = require('src.ports')
local Stations = require('src.stations')
local Util     = require('src.util')

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

local function near(a, b, tolerance)
    return math.abs(a - b) <= tolerance
end

local function run(state, seconds, dt)
    local left = seconds
    while left > 0 do
        local step = math.min(dt, left)
        World.step(state, step)
        left = left - step
    end
end

print("== determinismo ==")
do
    local a = World.new(1234)
    local b = World.new(1234)
    World.setHeading(a, 1.2)
    World.setHeading(b, 1.2)
    World.undock(a); World.undock(b)
    run(a, 600, 1 / 30)
    run(b, 600, 1 / 30)
    check("misma posicion", near(a.x, b.x, 1e-6) and near(a.y, b.y, 1e-6),
          string.format("%.4f,%.4f vs %.4f,%.4f", a.x, a.y, b.x, b.y))
    check("mismos recursos", near(a.res.coin, b.res.coin, 1e-6)
                          and near(a.res.fish, b.res.fish, 1e-6))
    check("misma moral", near(a.morale, b.morale, 1e-6))

    local c = World.new(99)
    run(c, 600, 1 / 30)
    check("otra semilla, otro mundo", not near(a.x, c.x, 0.01) or not near(a.y, c.y, 0.01))
end

print("== viento puro ==")
do
    local a = World.new(7)
    local b = World.new(7)
    run(a, 300, 1 / 30)
    run(b, 300, 7.5)          -- mismo tiempo, pasos muy distintos
    check("mismo viento", near(a.wind.from, b.wind.from, 1e-9)
                       and near(a.wind.strength, b.wind.strength, 1e-9),
          string.format("%.6f vs %.6f", a.wind.from, b.wind.from))
end

print("== vuelta a la partida ==")
do
    local live = World.new(42)
    local away = World.new(42)
    World.undock(live); World.undock(away)

    run(live, 3600, 1 / 30)
    local summary = World.catchUp(away, 3600)

    check("catchUp devuelve resumen", summary ~= nil)
    -- Una ausencia corta se simula pero no se reporta.
    local brief = World.new(43)
    World.undock(brief)
    local pos = brief.x
    check("una ausencia corta no da resumen", World.catchUp(brief, 60) == nil)
    check("pero si se simula", brief.x ~= pos)
    -- Los pasos gruesos no dan el bit exacto (la integracion del rumbo no es
    -- lineal), pero tienen que quedarse muy cerca o el jugador nota que
    -- desconectar le cuesta dinero.
    local drift = math.abs(live.distance - away.distance) / math.max(1, live.distance)
    check("distancia dentro del 3%", drift < 0.03, string.format("%.2f%%", drift * 100))

    local coinDrift = math.abs(live.res.coin - away.res.coin)
    check("monedas dentro de 15", coinDrift < 15, tostring(coinDrift))

    local fishDrift = math.abs(live.res.fish - away.res.fish)
    check("pescado dentro de 5", fishDrift < 5, tostring(fishDrift))

    check("el tope de ausencia se aplica",
          World.catchUp(World.new(1), 99999) ~= nil)
end

print("== economia ==")
do
    local s = World.new(5)
    World.undock(s)
    local before = s.res.fish
    run(s, 300, 1 / 30)
    check("las redes producen", s.res.fish + s.res.ration > before)

    -- Un barco de serie se alimenta solo: las redes y la cocina de nivel 1 dan
    -- mas de lo que come la tripulacion inicial, y eso es a proposito. Para
    -- ver el hambre hay que apagar la produccion.
    local hungry = World.new(6)
    World.undock(hungry)
    hungry.res.ration, hungry.res.fish = 0, 0
    hungry.stations.nets.level = 0
    hungry.stations.galley.level = 0
    for _, m in ipairs(hungry.crew) do m.station = nil end
    run(hungry, 120, 1 / 30)
    check("sin rancho baja la moral", hungry.morale < 90, tostring(hungry.morale))

    -- El casco se gasta navegando; lo que lo mantiene es la carpinteria. Sin
    -- ella tiene que caer aproximadamente HULL_WEAR por segundo. (Con ella no
    -- basta con vaciar la bodega: el vigia va encontrando madera a la deriva.)
    local worn = World.new(8)
    World.undock(worn)
    worn.stations.carpentry.level = 0
    run(worn, 1800, 1)
    local expected = 100 - Ship.HULL_WEAR * 1800
    check("sin carpinteria el casco se desgasta", near(worn.hull, expected, 1.5),
          string.format("%.1f, se esperaba %.1f", worn.hull, expected))

    local kept = World.new(8)
    World.undock(kept)
    kept.res.wood = 200
    run(kept, 1800, 1)
    check("con madera el carpintero lo aguanta", kept.hull > 95, tostring(kept.hull))
end

print("== navegacion ==")
do
    local s = World.new(3)
    check("proa al viento va lento", Ship.pointing(0, 0) < 0.2)
    check("traves es lo mas rapido", Ship.pointing(math.pi / 2, 0) > 0.9)
    check("popa cerrada no es lo optimo",
          Ship.pointing(math.pi, 0) < Ship.pointing(math.pi / 2, 0))

    World.undock(s)
    World.setHeading(s, Util.wrapAngle(s.heading + 1.5))
    local before = s.heading
    run(s, 5, 1 / 30)
    check("el timon hace caer el barco", math.abs(Util.angleDiff(before, s.heading)) > 0.1)
end

print("== bodega ==")
do
    local s = World.new(21)
    World.undock(s)
    local cap = Ship.capacity(s)
    check("la bodega tiene tope", cap > 0 and cap == Stations.holdCapacity(1), tostring(cap))

    run(s, 6 * 3600, 2)
    check("la carga nunca pasa del tope", Ship.cargo(s) <= cap + 1e-6,
          string.format("%.1f de %d", Ship.cargo(s), cap))
    check("la bodega acaba llena", Ship.hoveTo(s))

    -- La madera es pertrecho: si compitiera por la bodega, una bodega llena de
    -- pescado dejaria al carpintero sin material y el casco se caeria a cero.
    check("la madera no compite con la carga", s.res.wood > 20, tostring(s.res.wood))
    check("el casco aguanta la ausencia", s.hull > 95, tostring(s.hull))

    local bigger = World.new(21)
    bigger.stations.hold.level = 5
    check("subir la bodega sube el tope", Ship.capacity(bigger) > cap)
end

print("== soldadas ==")
do
    local s = World.new(31)
    World.undock(s)
    local coins = s.res.coin
    run(s, 900, 1 / 30)
    check("navegando no se cobra en monedas", s.res.coin >= coins, tostring(s.res.coin))
    check("navegando se devenga deuda", s.owed > 0, string.format("%.1f", s.owed))

    -- Con la bodega llena la soldada se para: es lo que impide que una
    -- ausencia larga acumule coste sin techo mientras el ingreso si lo tiene.
    local full = World.new(31)
    World.undock(full)
    run(full, 6 * 3600, 2)
    local owedAtFull = full.owed
    run(full, 3600, 2)
    check("con bodega llena la deuda casi no crece", full.owed - owedAtFull < 5,
          string.format("%+.1f en una hora", full.owed - owedAtFull))

    local port = Ports.get(s.seed, 0, 0)
    s.res.coin = 10000
    local owed = s.owed
    World.dock(s, port)
    check("atracar liquida la soldada", s.owed < 1 and s.res.coin < 10000,
          string.format("debia %.0f, quedan %.0f", owed, s.res.coin))

    local broke = World.new(32)
    World.undock(broke)
    run(broke, 1800, 2)
    broke.res.coin = 0
    local moraleBefore = broke.morale
    World.dock(broke, Ports.get(broke.seed, 0, 0))
    check("no poder pagar cuesta moral", broke.morale < moraleBefore)
    check("lo impagado sigue debiendose", broke.owed > 0)
end

print("== en puerto no corre la singladura ==")
do
    local s = World.new(41)          -- empieza amarrada
    s.res.ration = 4
    local snapshot = { hull = s.hull, ration = s.res.ration, owed = s.owed,
                       morale = s.morale, x = s.x, y = s.y }
    run(s, 4 * 3600, 2)
    check("amarrado no se come la despensa", s.res.ration == snapshot.ration)
    check("amarrado no se devenga soldada", s.owed == snapshot.owed)
    check("amarrado no se gasta el casco", s.hull == snapshot.hull)
    check("amarrado no se mueve", s.x == snapshot.x and s.y == snapshot.y)
    check("amarrado se descansa", s.morale >= snapshot.morale)
end

print("== rumbo fijado ==")

-- No todas las celdas tienen puerto (la densidad es 0.55), asi que un test no
-- puede escribir unas coordenadas a mano: busca el primero que haya.
local function somePort(seed)
    for r = 1, 4 do
        for cy = -r, r do
            for cx = -r, r do
                if not (cx == 0 and cy == 0) then
                    local p = Ports.get(seed, cx, cy)
                    if p then return p end
                end
            end
        end
    end
end

do
    local s = World.new(51)
    local target = somePort(s.seed)
    World.setCourse(s, target)
    check("fijar rumbo larga amarras", s.docked == nil and s.bound == target.key)

    World.catchUp(s, 8 * 3600)
    check("el barco llega solo", s.docked == target.key, tostring(s.docked))
    check("al llegar se suelta el rumbo", s.bound == nil)
    check("al llegar se liquida la soldada", s.owed < 1, string.format("%.1f", s.owed))

    -- Tocar el timon a mano tiene que soltar el rumbo, o el barco corregiria
    -- en el paso siguiente y el timon pareceria roto.
    local other = World.new(52)
    World.setCourse(other, somePort(other.seed))
    World.setHeading(other, 2.0)
    check("el timon cancela el rumbo fijado", other.bound == nil)
end

print("== vuelta a la partida: sucesos ==")
do
    local s = World.new(61)
    World.undock(s)
    local o = World.catchUp(s, 4 * 3600)
    check("cuenta hallazgos", (o.wrecks + o.barrels) > 0,
          string.format("%d restos, %d barriles", o.wrecks, o.barrels))
    check("nombra los puertos nuevos", #o.ports > 0, tostring(#o.ports))
    check("los nombres no vienen vacios", type(o.ports[1]) == "string" and #o.ports[1] > 4,
          tostring(o.ports[1]))
    -- La bitacora tiene ocho lineas y una ausencia larga genera cientos: si no
    -- se silenciara, lo unico que sobreviviria serian los ultimos barriles.
    check("la ausencia deja una sola linea de bitacora", #s.log <= 4, tostring(#s.log))
end

print("== nombres de puerto ==")
do
    local seen, dup = {}, 0
    local count = 0
    for cy = -20, 19 do
        for cx = -20, 19 do
            local p = Ports.get(3, cx, cy)
            if p then
                count = count + 1
                if seen[p.name] then dup = dup + 1 else seen[p.name] = p.key end
            end
        end
    end
    check("ningun nombre se repite en 40x40 celdas", dup == 0,
          string.format("%d repetidos de %d puertos", dup, count))
    -- El nombre es funcion de la celda y solo de la celda: la semilla decide
    -- que celdas tienen puerto, no como se llaman.
    check("el nombre no depende de la semilla", Ports.name(4, 7) == Ports.name(4, 7))
    check("celdas distintas, nombres distintos", Ports.name(4, 7) ~= Ports.name(5, 7)
                                             and Ports.name(4, 7) ~= Ports.name(4, 8))
end

print("== partidas guardadas de otra version ==")
do
    -- Una partida de la version 1: sin nada de lo que anadio la 2.
    local old = World.new(71)
    World.undock(old)
    old.res.coin = 123
    old.stations.nets.level = 4
    local crewCount = #old.crew
    old.tally, old.owed, old.taken, old.hove, old.bound = nil, nil, nil, nil, nil
    old.stations.hold = nil
    old.version = 1

    World.migrate(old)
    check("migrar pone la version al dia", old.version == World.VERSION)
    check("los puestos nuevos entran a nivel 1", old.stations.hold.level == 1)
    check("no se pisa lo que ya habia",
          old.res.coin == 123 and old.stations.nets.level == 4)
    check("no se inventa tripulacion", #old.crew == crewCount, tostring(#old.crew))
    check("y simula sin reventar", (pcall(World.catchUp, old, 3600)))

    -- Falte el campo que falte, la partida tiene que arrancar. Es lo que hace
    -- que anadir un campo al estado no rompa las partidas ya guardadas, y solo
    -- se cumple mientras el campo nuevo entre tambien en DEFAULTS.
    local fields = {
        "time", "x", "y", "heading", "target", "trim", "hull", "morale",
        "owed", "distance", "salvage", "scanTimer", "hove", "wind", "res",
        "stats", "tally", "discovered", "taken", "stations", "crew", "log",
    }
    local broken
    for _, field in ipairs(fields) do
        local s = World.new(72)
        World.undock(s)
        s[field] = nil
        World.migrate(s)
        local ok = pcall(run, s, 120, 2)
        if not ok then broken = field; break end
    end
    check("falte el campo que falte, se puede simular", broken == nil,
          "revienta sin " .. tostring(broken))
end

print("== puertos ==")
do
    local home = Ports.get(11, 0, 0)
    check("siempre hay puerto de origen", home ~= nil and home.name == "Puerto Madre")

    local same = Ports.get(11, 0, 0)
    check("un puerto es siempre el mismo", same.x == home.x and same.y == home.y)

    local found = Ports.near(11, home.x, home.y, 10)
    check("near encuentra el de casa", #found == 1 and found[1].key == home.key)

    local count = 0
    for cy = -3, 3 do
        for cx = -3, 3 do
            if Ports.get(11, cx, cy) then count = count + 1 end
        end
    end
    check("densidad razonable de puertos", count > 10 and count < 45, tostring(count) .. "/49")

    local s = World.new(11)
    check("la partida empieza amarrada", s.docked == home.key)
    check("el puerto de origen esta descubierto", s.discovered[home.key] == true)
end

print(string.format("\n%d comprobaciones, %d fallos", checks, failures))
os.exit(failures == 0 and 0 or 1)
