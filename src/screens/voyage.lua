-- Travesia: la pantalla principal.
--
-- Tres capas, y el orden importa:
--
--   1. El mar y el barco, en espacio de arte (escala entera). Aqui todo son
--      pixeles enteros y ningun sprite gira: la camara va con la proa.
--   2. La cabecera, timon incluido, en espacio virtual, donde el texto tiene
--      la resolucion de la fuente.
--   3. Los botones y las hojas, abajo, que es donde llega el pulgar.
--
-- El barco no es un sprite sino una pila de capas sobre el mismo lienzo
-- (casco, escotilla, cocina, redes, velas, ancla): ver drawShip() mas abajo.
--
-- La cubierta es tocable: cada puesto de src/stations.lua tiene un ancla en
-- ese lienzo y abre su hoja. El resto de la pantalla es mar, salvo la
-- cabecera y las dos columnas de botones de abajo.
--
-- Tres puestos no abren su hoja al primer toque, porque sacan un MANDO: el
-- timon larga la rueda de `src/helm.lua` en la esquina de estribor, el
-- velamen larga la driza de `src/halyard.lua` por la esquina de arriba a
-- babor y las redes largan el redal de `src/reel.lua` por el bajo de la
-- pantalla. Los tres dejan su hoja para el segundo toque. Es el orden de la
-- frecuencia: se corrige el rumbo, se cambia el trapo y se pesca cien veces
-- por cada vez que se destina a alguien a esos puestos, asi que lo que se hace
-- a menudo se cobra el toque corto.
--
-- Los tres mandos no salen a la vez, y no porque se estorben en pantalla --
-- aunque la rueda y el redal nacen de la misma esquina, y solo por esto pueden
-- hacerlo -- sino porque mientras uno esta fuera un toque en cualquier otro
-- sitio lo recoge: con dos fuera, tocar uno guardaria el otro. El toque que
-- recoge un mando NO dispara lo que hubiera bajo el dedo, y ahi la rueda tapa
-- justo lo que no conviene disparar sin querer: recogerla zarparia de propina.
--
-- Lo que tapa cada uno es lo que mide: la rueda se lleva la columna de
-- botones de estribor, que cae debajo de ella, y el redal se lleva TODO el
-- bajo -- las dos columnas y la bitacora -- porque cruza de banda a banda.
--
-- Los botones van en DOS columnas y no en una: con el timon fuera de la
-- esquina de estribor la mitad derecha de abajo quedaba vacia, y una sola
-- pila subia tanto que se comia el mar por babor. Repartidos, cada columna
-- mide dos filas, el barco puede bajar al centro de la pantalla
-- (`Constants.shipAnchor`) y la bitacora cabe encima. A la izquierda lo que se
-- consulta (carta, tripulacion) y a la derecha lo que se le hace al barco
-- (atracar, zarpar). El trapo NO tiene boton: se cambia con la driza, tirando
-- de la cuerda, y por eso el velamen tampoco abre su hoja al primer toque.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Art       = require('src.art')
local UI        = require('src.ui')
local Hud       = require('src.hud')
local Sea       = require('src.sea')
local Compass   = require('src.compass')
local Helm      = require('src.helm')
local Halyard   = require('src.halyard')
local Reel      = require('src.reel')
local Ship      = require('src.ship')
local Deck      = require('src.deck')
local Stations  = require('src.stations')
local Crew      = require('src.crew')
local World     = require('src.world')
local Ports     = require('src.ports')
local Session   = require('src.session')
local ScreenManager = require('lib.screen_manager')

local Voyage = {}

local sheet
local steering = nil       -- "dial" (la rosa de arriba) o "rueda" (el timon grande)
local selected = nil       -- id del puesto abierto
local wheel = false        -- rueda del timon fuera, en la esquina de estribor
local rope = false         -- driza del velamen fuera, por la esquina de babor
local hauling = false      -- se esta tirando de la driza
local spool = false        -- redal de las redes fuera, por el bajo de la pantalla
local cranking = false     -- se esta rodando el carrete
local TOUCH_R = 9          -- radio de toque de un puesto, en pixeles de arte

local function state() return Session.state end

--==========================================================================
-- Geometria de la cubierta
--==========================================================================

-- Esquina superior izquierda del lienzo del barco, en pixeles de arte.
--
-- Se cuenta desde el centro del CASCO, no del lienzo: el lienzo lleva aire de
-- sobra para que las vergas y las bocas de los canones asomen por fuera de la
-- borda, y centrarlo por el lienzo dejaria el barco un par de pixeles a proa
-- de su posicion real, con la estela saliendo de dentro del espejo de popa.
local function shipOrigin()
    local cx, cy = Constants.shipAnchor()
    local w, h = Art.size("ship.hull")
    local box = Art.HULL_BOX
    return cx - (box.x + box.w / 2) * w, cy - (box.y + box.h / 2) * h, w, h
end

local function stationPoint(def)
    local ox, oy, w, h = shipOrigin()
    local dx, dy = Ship.deckPoint(def, w, h)
    return ox + dx, oy + dy
end

-- Puesto bajo un punto en coordenadas VIRTUALES, o nil.
local function stationAt(vx, vy)
    local ax, ay = vx / Constants.ART, vy / Constants.ART
    local best, bestDist
    for _, def in ipairs(Stations.list) do
        local px, py = stationPoint(def)
        local d = Util.dist(ax, ay, px, py)
        if d <= TOUCH_R and (not bestDist or d < bestDist) then
            best, bestDist = def, d
        end
    end
    return best
end

--==========================================================================
-- Dibujo del barco
--==========================================================================

-- Todas las capas del barco estan registradas sobre el mismo lienzo y con el
-- arte ya casado dentro (ver SHIP_W en src/art.lua), asi que se dibujan todas
-- en el mismo origen y encajan sin un solo offset a mano. Lo unico que hay
-- aqui es el ORDEN, de abajo arriba, que es el subindice del archivo al reves.
--
-- Falta una capa por debajo del casco: los canones (assets/cannons3.png,
-- subindice 3), de los que solo asomarian las bocas por fuera de la borda. No
-- se dibujan porque no hay artilleria todavia; el dia que la haya, la primera
-- linea de esta funcion es
--     Art.drawIfAny("ship.cannons", ox, oy)
local function drawShip(s)
    local ox, oy, w, h = shipOrigin()

    Art.draw("ship.hull", ox, oy)
    Art.drawIfAny("ship.hold", ox, oy)
    Art.drawIfAny("ship.galley", ox, oy)
    Art.drawIfAny("ship.nets", ox, oy)

    -- La tripulacion se cuela AQUI, entre la cubierta y el trapo, y no al
    -- final como estaba: la gente anda por cubierta y el aparejo esta por
    -- encima de su cabeza. Pintados despues de las velas se subian encima del
    -- pano y el barco dejaba de leerse como un barco.
    --
    -- Donde esta cada uno lo dice src/deck.lua: los destinados se remueven en
    -- su puesto y los que no tienen destino pasean el barco entero.
    Deck.draw(s, ox, oy, w, h)

    Art.draw((s.trim == "reef") and "ship.sailsReef" or "ship.sails", ox, oy)

    -- El ancla es la unica capa que dice algo del estado del barco en vez de
    -- decorarlo: solo esta a la vista cuando esta echada.
    if s.docked then Art.drawIfAny("ship.anchor", ox, oy) end

    -- Las marcas de puesto van por ENCIMA de todo, tripulacion y velas
    -- incluidas. No son parte del barco sino de la interfaz: un aro que dice
    -- "aqui falta gente" tapado por la verga no avisa de nada.
    for _, def in ipairs(Stations.list) do
        local px, py = stationPoint(def)
        local crew = Ship.crewAt(s, def.id)

        -- Marca del puesto: un aro cuando esta vacio, para que se vea donde
        -- falta gente sin abrir menus.
        if #crew == 0 then
            love.graphics.setColor(Palette.gold)
            love.graphics.rectangle("line", math.floor(px) - 2, math.floor(py) - 2, 5, 5)
            love.graphics.setColor(1, 1, 1, 1)
        end
        -- El puesto abierto se cerca en blanco. Y tambien el que tenga su
        -- mando fuera: es lo que ata la rueda de la esquina, o la driza de
        -- babor, al sitio de la cubierta que se ha tocado para sacarla.
        if selected == def.id or (wheel and def.id == "helm")
           or (rope and def.id == "sails") or (spool and def.id == "nets") then
            love.graphics.setColor(Palette.white)
            love.graphics.rectangle("line", math.floor(px) - 4, math.floor(py) - 4, 9, 9)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
end

--==========================================================================
-- Lecturas de puesto
--==========================================================================

-- Que aporta este puesto ahora mismo, en las unidades en las que se piensa
-- (por minuto, no por segundo).
local function readout(s, id)
    local r = Ship.rates(s)
    local p = Ship.power(s, id)
    if id == "nets" then
        return string.format("+%.1f pescado/min", r.fish * 60)
    elseif id == "galley" then
        return string.format("+%.1f raciones/min (-%.1f pescado)", r.rations * 60, r.fishUsed * 60)
    elseif id == "carpentry" then
        return string.format("+%.1f casco/min (-%.1f madera)", r.repairs * 60, r.woodUsed * 60)
    elseif id == "sails" then
        return string.format("%.1f nudos con este trapo", r.speed / 2)
    elseif id == "helm" then
        return string.format("cae %d grados por segundo", math.floor(r.turn * 180 / math.pi))
    elseif id == "hold" then
        return string.format("%d de %d en bodega", math.floor(r.cargo), r.capacity)
    elseif id == "crowsnest" then
        return string.format("vista %d · restos cada %s", math.floor(r.lookout),
                             r.salvage > 0 and Util.duration(1 / r.salvage) or "nunca")
    end
    return string.format("potencia %.1f", p)
end

--==========================================================================
-- Hojas
--==========================================================================

local function offlineSheet()
    local s = state()
    local x, y, w = sheet:frame("Mientras no estabas")
    local o = Session.offline

    UI.text("Has navegado " .. Util.duration(o.elapsed) .. ".", x, y, Palette.dim, Fonts.small)
    y = y + 34

    local lines = {
        { "icon.coin",   string.format("%+d", math.floor(o.coin)) },
        { "icon.fish",   string.format("%+d", math.floor(o.fish)) },
        { "icon.wood",   string.format("%+d", math.floor(o.wood)) },
        { "icon.ration", string.format("%+d", math.floor(o.ration)) },
    }
    for i, line in ipairs(lines) do
        local rx = x + ((i - 1) % 2) * (w / 2)
        local ry = y + math.floor((i - 1) / 2) * 34
        UI.icon(line[1], rx, ry, 2)
        UI.text(line[2], rx + 30, ry + 2, Palette.text, Fonts.small)
    end
    y = y + 76

    UI.text(string.format("Singladura: %d millas · %d hallazgos",
                          math.floor(o.distance / 10), o.wrecks + o.barrels),
            x, y, Palette.dim, Fonts.small)
    y = y + 28

    -- Los puertos nuevos son lo mejor de volver, asi que se nombran. La
    -- bitacora no puede hacerlo: guarda ocho lineas y una ausencia larga
    -- genera cientos.
    if #o.ports > 0 then
        UI.text(string.format("Tierra a la vista: %d puertos nuevos", #o.ports),
                x, y, Palette.gold, Fonts.small)
        y = y + 26
        for i = 1, math.min(3, #o.ports) do
            UI.text("  " .. o.ports[i], x, y, Palette.text, Fonts.tiny)
            y = y + 20
        end
        if #o.ports > 3 then
            UI.text(string.format("  y %d mas, en la carta", #o.ports - 3),
                    x, y, Palette.dim, Fonts.tiny)
            y = y + 20
        end
    end

    if o.arrived then
        UI.text("Amarrado en " .. o.arrived.name .. ".", x, y, Palette.green, Fonts.small)
        y = y + 26
    end
    if o.hoveTo then
        UI.text("Bodega llena: el barco esta a la capa.", x, y, Palette.red, Fonts.small)
        y = y + 26
    end
    if o.owed > 1 then
        UI.text(string.format("Se deben %d monedas de soldada.", math.floor(o.owed)),
                x, y, Palette.dim, Fonts.tiny)
        y = y + 22
    end
    if o.hull < -1 then
        UI.text(string.format("El casco ha sufrido %d puntos.", math.floor(-o.hull)),
                x, y, Palette.red, Fonts.small)
    end

    if UI.button(x, sheet:actionY(), w, 46, "A cubierta", { tone = Palette.gold }) then
        Session.offline = nil
        sheet:hide()
    end
end

local function stationSheet()
    local s = state()
    local def = Stations.byId[selected]
    local slot = s.stations[selected]
    local x, y, w = sheet:frame(def.name)

    UI.text(def.desc, x, y, Palette.dim, Fonts.tiny)
    y = y + 24
    UI.text(string.format("Nivel %d · %s · potencia %.1f", slot.level,
                          Crew.roleName(def.role), Ship.power(s, selected)),
            x, y, Palette.text, Fonts.small)
    y = y + 28
    UI.text(readout(s, selected), x, y, Palette.foam, Fonts.small)
    y = y + 34

    -- Destinados. Tocar a uno lo retira del puesto.
    local crew = Ship.crewAt(s, selected)
    local capacity = Stations.capacity(slot.level)
    UI.text(string.format("Destinados %d/%d", #crew, capacity), x, y, Palette.dim, Fonts.tiny)
    y = y + 22
    for _, member in ipairs(crew) do
        if UI.row(x, y, w, 34, member.name,
                  string.format("%s %d ·  retirar", Crew.roleName(member.role), member.skill)) then
            World.assign(s, member, nil)
        end
        y = y + 38
    end

    -- Disponibles.
    if #crew < capacity then
        local free = {}
        for _, member in ipairs(s.crew) do
            if not member.station then free[#free + 1] = member end
        end
        if #free == 0 then
            UI.text("Nadie libre a bordo.", x, y, Palette.dim, Fonts.tiny)
            y = y + 26
        else
            for i = 1, math.min(3, #free) do
                local member = free[i]
                local fits = (member.role == def.role)
                if UI.row(x, y, w, 34, "destinar  " .. member.name,
                          string.format("%s %d", Crew.roleName(member.role), member.skill),
                          { rightInk = fits and Palette.green or Palette.dim }) then
                    World.assign(s, member, selected)
                end
                y = y + 38
            end
        end
    end

    -- Mejora: solo en puerto. Es lo que hace que atracar valga la pena.
    local cost = Stations.upgradeCost(slot.level)
    local maxed = slot.level >= Stations.MAX_LEVEL
    local canPay = s.res.coin >= cost.coin and s.res.wood >= cost.wood
    local label = maxed and "Al maximo"
        or string.format("Mejorar  %d monedas  %d madera", cost.coin, cost.wood)
    if UI.button(x, sheet:actionY(), w, 46, s.docked and label or "Mejoras solo en puerto", {
        enabled = (s.docked ~= nil) and not maxed and canPay,
        tone = Palette.gold,
    }) then
        World.upgrade(s, selected)
    end
end

local function crewSheet()
    local s = state()
    local x, y, w = sheet:frame("Tripulacion")

    local wages = 0
    for _, m in ipairs(s.crew) do wages = wages + m.wage end
    UI.text(string.format("%d a bordo · %d monedas/min de soldada", #s.crew, wages),
            x, y, Palette.dim, Fonts.tiny)
    y = y + 26

    if #s.crew == 0 then
        UI.text("El barco va solo. Busca una taberna.", x, y, Palette.dim, Fonts.small)
    end

    for i = 1, math.min(7, #s.crew) do
        local member = s.crew[i]
        local post = member.station and Stations.byId[member.station].name or "sin destino"
        if UI.row(x, y, w, 36, member.name,
                  string.format("%s %d · %s", Crew.roleName(member.role), member.skill, post),
                  { rightInk = member.station and Palette.foam or Palette.dim }) then
            World.assign(s, member, nil)
        end
        y = y + 40
    end
end

--==========================================================================
-- Ciclo de pantalla
--==========================================================================

function Voyage.enter()
    sheet = UI.newSheet()
    selected = nil
    steering = nil
    wheel, rope, hauling = false, false, false
    spool, cranking = false, false
    Helm.reset()
    Halyard.reset()
    Reel.reset()
    Sea.reset()
    if Session.offline then
        sheet:show("offline", 460)
    end
end

function Voyage.update(dt)
    local s = state()
    World.advance(s, dt)
    Sea.update(s, dt)
    Session.update(dt)
    sheet:update(dt)
    Helm.update(dt, wheel)
    Halyard.update(dt, rope, s)

    -- El redal no pide nada a la simulacion mientras se pelea: devuelve el
    -- resultado y aqui se traduce. Ver la cabecera de src/reel.lua sobre por
    -- que la pelea no vive en el estado guardado.
    local caught = Reel.update(dt, spool, s)
    if caught then
        if caught.kind == "catch" then
            World.landFish(s, caught.fish)
        else
            World.lostFish(s, caught.kind == "snap")
        end
    end

    -- Cerrar el resumen de la ausencia por la X tambien lo da por leido.
    if Session.offline and not sheet.open then Session.offline = nil end
end

function Voyage.press(x, y)
    if sheet:blocks(x, y) then return end

    -- Con el redal fuera manda el redal y solo el redal: se agarra el
    -- carrete, no la cana, porque lo que se hace es rodarlo.
    if spool then
        if Reel.contains(x, y) then
            cranking = true
            Reel.grab(x, y)
        end
        return
    end

    -- Con la driza fuera manda la driza y solo la driza, igual que con la
    -- rueda: se agarra la cuerda donde se ve (cualquier nodo, el nudo con mas
    -- margen) y cualquier otro toque la recoge.
    if rope then
        if Halyard.contains(x, y) then
            hauling = true
            Halyard.grab(x, y)
        end
        return
    end

    -- Con la rueda fuera, gobierna la rueda y solo la rueda. La rosa de
    -- arriba se queda inerte a proposito: dos mandos de rumbo vivos a la vez
    -- es como se acaba pidiendo un rumbo con el pulgar que sujeta el movil.
    if wheel then
        if Helm.contains(x, y) then
            steering = "rueda"
            Helm.grab(x, y)
        end
        return
    end

    -- El timon esta ahora en la cabecera, es decir POR ENCIMA de la hoja en
    -- vez de debajo: `sheet:blocks` ya no lo tapa y sin esto se gobernaria a
    -- traves del velo.
    if not sheet:visible() and Compass.contains(x, y) then
        steering = "dial"
        local h = Compass.headingAt(state(), x, y)
        if h then World.setHeading(state(), h) end
    end
end

function Voyage.move(x, y)
    if cranking then
        Reel.roll(x, y)
        return
    end
    if hauling then
        Halyard.haul(x, y)
        return
    end
    if steering == "rueda" then
        local h = Helm.steer(state(), x, y)
        if h then World.setHeading(state(), h) end
    elseif steering == "dial" then
        local h = Compass.headingAt(state(), x, y)
        if h then World.setHeading(state(), h) end
    end
end

function Voyage.release(x, y)
    -- Soltar el carrete lo deja rodando con el giro que llevaba, que es como
    -- se escapa el pez: la travesia no decide nada aqui, solo suelta.
    if cranking then
        cranking = false
        Reel.drop()
        return
    end

    -- Soltar la driza es lo que cambia el trapo, y solo si el tiron llego. La
    -- cuerda se queda fuera despues: es el indicador de cuanto trapo se lleva
    -- y desde donde se tira la vez siguiente.
    if hauling then
        hauling = false
        local trim = Halyard.drop(state())
        if trim then World.setTrim(state(), trim) end
        return
    end

    if steering then
        steering = nil
        Helm.drop()
        return
    end
    if sheet:blocks(x, y) or UI.pointer.moved then return end

    local def = stationAt(x, y)
    if def then
        -- Primer toque en el timon o en el velamen: su mando. Segundo (o
        -- toque en otro puesto): la hoja, y el mando se recoge porque la hoja
        -- lo taparia. El que sale guarda al otro (ver la cabecera).
        if def.id == "helm" and not wheel then
            wheel, rope, spool = true, false, false
        elseif def.id == "sails" and not rope then
            wheel, rope, spool = false, true, false
        elseif def.id == "nets" and not spool then
            wheel, rope, spool = false, false, true
        else
            wheel, rope, spool = false, false, false
            selected = def.id
            sheet:show("station", 420)
        end
        UI.pointer.released = false
        return
    end

    -- Tocar fuera del mando que este fuera es recogerlo, y nada mas: el toque
    -- se consume aqui para que no dispare tambien el boton que haya debajo.
    if wheel or rope or spool then
        wheel, rope, spool = false, false, false
        UI.pointer.released = false
    end
end

function Voyage.keypressed(key)
    if key == "escape" then
        if wheel or rope or spool then
            wheel, rope, spool = false, false, false
        else
            sheet:hide()
        end
    end
end

function Voyage.draw()
    local s = state()

    -- Capa de arte.
    love.graphics.push()
    love.graphics.scale(Constants.ART, Constants.ART)
    Sea.draw(s)
    drawShip(s)
    love.graphics.pop()

    -- Capa de interfaz. El timon va justo detras de la cabecera porque es
    -- parte de ella: se pinta despues para quedar encima del fondo de la
    -- franja, y antes que la hoja para que el velo lo cubra como a todo.
    Hud.draw(s)
    Compass.draw(s)

    -- La bitacora se lee de reojo cuando no pasa nada, y con el redal fuera
    -- pasa algo: se quita en cuanto asoma la cana, que le cruza por encima.
    -- Se mira si se VE y no si esta pedido, por lo mismo que la columna de
    -- estribor con la rueda: volviendo en cuanto se suelta el toque, el texto
    -- parpadearia bajo la cana justo mientras se guarda.
    if not Reel.showing() then Hud.drawLog(s) end

    -- Con una hoja abierta los botones de cubierta se siguen viendo (bajo el
    -- velo) pero no responden: el toque es de la hoja. Con un mando fuera,
    -- igual: el unico toque que cuenta es el del mando, y el resto lo recoge
    -- (ver Voyage.release).
    UI.lock(sheet:visible() or wheel or rope or spool)

    -- Dos columnas pegadas a los margenes seguros. El ancho se reparte lo que
    -- hay, con tope: en un movil las dos columnas llenan el bajo de la
    -- pantalla, y en una ventana de escritorio no salen dos botones de medio
    -- metro sino los mismos de siempre, uno en cada esquina.
    local bottom = Constants.GAME_HEIGHT - Constants.SAFE_BOTTOM
    local usable = Constants.GAME_WIDTH - Constants.SAFE_LEFT - Constants.SAFE_RIGHT - 24
    local bh, gap = 44, 16
    local bw = math.min(250, math.floor((usable - gap) / 2))
    local lx = Constants.SAFE_LEFT + 12
    local rx = Constants.GAME_WIDTH - Constants.SAFE_RIGHT - 12 - bw
    local row1, row2 = bottom - 60, bottom - 112

    -- Babor: lo que se consulta. Con el redal fuera tampoco se dibuja: la
    -- cana llega hasta esta banda y el sedal cae al agua por delante de los
    -- botones, asi que asomarian por debajo del aparejo.
    if not Reel.showing() then
        if UI.button(lx, row1, bw, bh, "Carta", { icon = "icon.chart" }) then
            ScreenManager.switch("chart")
        end

        if UI.button(lx, row2, bw, bh, "Tripulacion", { icon = "icon.crew" }) then
            sheet:show("crew", 380)
        end
    end

    -- Estribor: lo que se le hace al barco, y ya solo cosas de puerto. El
    -- trapo tenia aqui su boton y se lo ha quedado la driza: cambiarlo es una
    -- maniobra, se hace tirando de una cuerda, y tener las dos formas dejaba
    -- una diciendo "largar trapo" mientras la otra ya lo habia largado. Los de
    -- puerto bajan a ocupar el sitio: pegados al canto es donde llega el
    -- pulgar, y esta columna se queda con dos botones como la de babor.
    --
    -- Con la rueda delante esta columna no se dibuja: la rueda nace en esta
    -- misma esquina y los botones asomarian por los huecos entre las
    -- cabillas. Se pierde poco -- son cosas que se hacen una vez, no mientras
    -- se gobierna -- y el toque que recoge la rueda devuelve la columna a su
    -- sitio. Se mira si se VE y no si esta pedida: volviendo en cuanto se
    -- suelta el toque, los botones se verian por entre las cabillas justo
    -- mientras la rueda se va, que es el parpadeo que esto evita.
    if not Helm.showing() and not Reel.showing() then
        -- Boton contextual: lo que se puede hacer con el puerto que haya cerca.
        local port = World.canDock(s)
        if s.docked then
            if UI.button(rx, row1, bw, bh, "Bajar a tierra", { tone = Palette.gold }) then
                ScreenManager.switch("port")
            end
            if UI.button(rx, row2, bw, bh, "Zarpar", { tone = Palette.gold }) then
                World.undock(s)
                Sea.reset()
            end
        elseif port then
            if UI.button(rx, row1, bw, bh, "Atracar",
                         { tone = Palette.gold, icon = "icon.anchor" }) then
                World.dock(s, port)
            end
        end
    end

    -- Una sola linea de aviso arriba, y el rumbo fijado manda sobre el puerto
    -- a la vista: si vas a algun sitio, eso es lo que quieres leer.
    local bound = World.boundPort(s)
    if bound and not s.docked then
        UI.textCenter(string.format("Rumbo a %s · %d millas", bound.name,
                      math.floor(Util.dist(s.x, s.y, bound.x, bound.y) / 10)),
                      Constants.GAME_WIDTH / 2, Hud.topHeight() + 6, Palette.gold, Fonts.small)
    else
        local nearest, dist = World.nearestPort(s)
        if nearest and not s.docked and dist and dist < Ship.rates(s).lookout then
            UI.textCenter(string.format("%s a %d millas", nearest.name, math.floor(dist / 10)),
                          Constants.GAME_WIDTH / 2, Hud.topHeight() + 6, Palette.gold, Fonts.small)
        end
    end

    -- La rueda va lo ultimo de la capa de interfaz: por encima de los botones
    -- de babor (que no llega a tocar) y por debajo de la hoja, que la tapa
    -- con su velo como a todo lo demas. Se pinta mientras se VEA, que es mas
    -- de lo que esta pedida: al recogerla sigue en pantalla saliendo.
    if Helm.showing() then Helm.draw(s) end

    -- Y la driza con ella, por la esquina de arriba a babor. No se pisan
    -- nunca -- ni pueden estar las dos pedidas a la vez -- pero se pinta
    -- despues por el mismo motivo: mientras se VE, que es mas de lo que esta
    -- pedida, porque al recogerla sigue en pantalla saliendo.
    if Halyard.showing() then Halyard.draw(s) end

    -- Y el redal, por el bajo. Nace de la misma esquina que la rueda y por eso
    -- va detras de ella en el mismo sitio de la capa: no pueden verse los dos
    -- -- ni estar los dos pedidos -- pero el orden lo deja escrito.
    if Reel.showing() then Reel.draw(s) end

    UI.lock(false)
    if sheet:visible() then
        if sheet.key == "offline" and Session.offline then
            offlineSheet()
        elseif sheet.key == "station" and selected then
            stationSheet()
        elseif sheet.key == "crew" then
            crewSheet()
        end
    end
end

return Voyage
