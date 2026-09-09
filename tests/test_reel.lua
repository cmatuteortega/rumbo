-- Prueba del redal, sin ventana.
--
--     lua5.1 tests/test_reel.lua
--
-- Va aparte de tests/test_sim.lua por lo mismo que la de la driza: la
-- simulacion no puede requerir love y por eso se prueba tal cual, pero el
-- redal es DIBUJO y hace falta un love de mentira. Lo que se mide aqui no es
-- balance, es la pelea.
--
-- Y hay una vuelta de tuerca respecto a la driza: el love de mentira apunta
-- tambien EL COLOR de cada rectangulo, y con eso el jugador de la prueba
-- --el bot de mas abajo-- pelea leyendo unicamente lo que se pinta: donde
-- esta el pez, si esta en la banda (se pinta de oro) y si la linea esta a
-- punto de romperse (el sedal se pinta de rojo). Si el bot cobra el pez sin
-- mirar ni una variable del modulo, entonces el dibujo lleva de verdad todo
-- lo que hace falta para jugar, que es la unica manera de comprobarlo: un
-- mando cuya lectura no esta en la pantalla se puede "ganar" desde el codigo
-- y perder con el pulgar.
--
-- Las tres cosas que se rompen aqui y no se ven mirando la pantalla un rato:
--
--   * que rodar como un poseso sea la estrategia buena. Es marginal por los
--     dos lados -- rodar acerca el pez y a la vez tensa la linea -- asi que
--     no se decide leyendo el codigo, se mide.
--   * que un jugador razonable no llegue a cobrar NINGUN pez, o que los cobre
--     todos. Las dos se ven igual de bien: mirando cuanto tarda el bot.
--   * que en reposo el aparejo tiemble. Es la leccion de la driza y aqui
--     vuelve entera, porque la cana y el sedal son de nuevo un trazo largo:
--     medio pixel de deriva repinta la pantalla de lado a lado.

package.path = "./?.lua;" .. package.path

-- love de mentira: apuntar lo que se pinta CON SU COLOR y tragarse el resto.
local painted = {}
local current = nil
local function nop() end
love = setmetatable({}, { __index = function()
    return setmetatable({}, { __index = function() return nop end })
end })
love.graphics = setmetatable({
    rectangle = function(mode, x, y, w, h)
        painted[#painted + 1] = { x, y, w, h, current }
    end,
    setColor = function(c) current = (type(c) == "table") and c or nil end,
    push = nop, pop = nop, scale = nop, draw = nop,
}, { __index = function() return nop end })

-- Fuentes de mentira: el motivo ("Amarrado no se pesca") se pinta con
-- UI.textCenter, que lee el global Fonts.
Fonts = setmetatable({}, { __index = function()
    return setmetatable({}, { __index = function() return function() return 0 end end })
end })

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Reel      = require('src.reel')
local World     = require('src.world')
local Ship      = require('src.ship')

local failures, checks = 0, 0

local function check(name, ok, detail)
    checks = checks + 1
    if ok then
        print("  ok   " .. name)
    else
        failures = failures + 1
        print("  FALLA " .. name .. (detail and ("  -> " .. detail) or ""))
    end
end

--== Lo que se puede LEER del dibujo =======================================
--
-- Todo en pixeles de ARTE, que es donde vive el aparejo.

-- Un cuadro pintado, y de el lo que ve un jugador.
local function frame(state)
    painted, current = {}, nil
    Reel.draw(state)
    return painted
end

-- El pez: lo unico que se pinta de blanco, y de oro cuando esta en la banda.
-- La manivela tambien se pone de oro con un pez enganchado, asi que se
-- descarta lo que caiga encima del carrete -- que es exactamente como lo
-- separa el ojo, por estar en la cana y no en la rueda.
local function fish()
    local cx, cy = Reel.center()
    local x0, x1, gold = nil, nil, false
    for _, p in ipairs(painted) do
        local c = p[5]
        if c == Palette.white or c == Palette.gold then
            local px, py = p[1], p[2]
            if Util.dist(px, py, cx, cy) > Reel.RADIUS + 4 then
                x0 = math.min(x0 or px, px)
                x1 = math.max(x1 or (px + p[3]), px + p[3])
                if c == Palette.gold then gold = true end
            end
        end
    end
    if not x0 then return nil end
    return (x0 + x1) / 2, gold, x1 - x0
end

-- Si el pez esta VUELTO (cediendo). Se lee de la FORMA y no de un color, que
-- es como lo lee el ojo: la fila de arriba de la silueta esta metida tres
-- pixeles por el morro y pegada al canto por la cola, asi que mirando de que
-- lado empieza se sabe hacia donde mira. Es la unica senal de la cedida.
local function turned()
    local cx, cy = Reel.center()
    local x0, top = nil, nil
    local rows = {}
    for _, p in ipairs(painted) do
        local c = p[5]
        if (c == Palette.white or c == Palette.gold)
           and Util.dist(p[1], p[2], cx, cy) > Reel.RADIUS + 4 then
            x0 = math.min(x0 or p[1], p[1])
            top = math.min(top or p[2], p[2])
            rows[p[2]] = math.min(rows[p[2]] or p[1], p[1])
        end
    end
    if not x0 then return nil end
    -- El morro deja la fila de arriba metida; la cola la deja al canto.
    return rows[top] <= x0 + 1
end

-- La banda, del color de la espuma: su centro en pixeles de arte.
local function bandCenter()
    local x0, x1
    for _, p in ipairs(painted) do
        if p[5] == Palette.foam then
            x0 = math.min(x0 or p[1], p[1])
            x1 = math.max(x1 or (p[1] + p[3]), p[1] + p[3])
        end
    end
    if not x0 then return nil end
    return (x0 + x1) / 2
end

-- Si el sedal se esta pintando en rojo, que es el aviso de que la linea va a
-- romperse. Se busca por color y no por contar pixeles: el sedal es lo unico
-- rojo del mando.
local function alarmed()
    for _, p in ipairs(painted) do
        if p[5] == Palette.red then return true end
    end
    return false
end

--== Manejar el redal =======================================================

-- Un punto sobre el carrete, por fuera de la nuez: es por donde se coge.
local function knob(a)
    local cx, cy = Reel.center()
    local r = (Reel.RADIUS - 6) * Constants.ART
    return cx * Constants.ART + math.sin(a) * r,
           cy * Constants.ART - math.cos(a) * r
end

local DT = 1 / 60

-- Un mundo navegando, con el redal ya fuera del todo.
local function sea(seed)
    local state = World.new(seed or 7)
    World.undock(state)
    Reel.reset()
    for _ = 1, 30 do Reel.update(DT, true, state); World.step(state, DT) end
    return state
end

-- Corre cuadros hasta que pase algo o se acabe el tiempo. `policy` devuelve
-- cuanto hay que rodar este cuadro, en radianes por segundo (0 = soltar).
local function play(state, seconds, policy)
    local held, a, t = false, 0, 0
    while t < seconds do
        local rate = policy and policy(state) or 0
        if rate > 0 then
            if not held then Reel.grab(knob(a)); held = true end
            a = a + rate * DT
            Reel.roll(knob(a))
        elseif held then
            Reel.drop(); held = false
        end
        local ev = Reel.update(DT, true, state)
        World.step(state, DT)
        frame(state)
        t = t + DT
        if ev then
            if held then Reel.drop() end
            return ev, t
        end
    end
    if held then Reel.drop() end
    return nil, t
end

-- Espera a que pique, y devuelve cuanto tardo.
local function bite(state, limit)
    local t = 0
    while t < (limit or 20) do
        Reel.update(DT, true, state)
        World.step(state, DT)
        frame(state)
        t = t + DT
        if fish() then return t end
    end
    return nil
end

--== Geometria ==============================================================
--
-- El aparejo entero tiene que caber en la pantalla, y la cana tiene que ir a
-- donde se dijo: desde la esquina de estribor hacia babor y hacia arriba.

print("== geometria ==")
do
    local cx, cy = Reel.center()
    local tx, ty = Reel.tip()
    check("el carrete cabe por estribor y por abajo",
          cx + Reel.RADIUS < Constants.ART_W and cy + Reel.RADIUS < Constants.ART_H,
          string.format("carrete en %d,%d de %dx%d", cx, cy, Constants.ART_W, Constants.ART_H))
    check("la cana apunta a babor y hacia arriba", tx < cx and ty < cy,
          string.format("punta en %d,%d", tx, ty))
    check("y es larga de verdad", (cx - tx) > Constants.ART_W * 0.5,
          string.format("%d px de arte", cx - tx))
end

-- LA COMBA ES DE CANA, NO DE CUERDA. Con la linea tensa la PUNTA es la que
-- baja y el arranque sale recto del puno, que es lo que hace una vara
-- empotrada por un extremo. Se mide del dibujo: se compara la cana en reposo
-- con la cana tensa y se mira cuanto ha bajado cada tercio.
do
    local state = sea(6)

    -- Las alturas de la cana (su madera) a lo ancho de la pantalla.
    local function profile()
        local col = {}
        for _, p in ipairs(painted) do
            if p[5] == Palette.wood then
                col[p[1]] = math.max(col[p[1]] or p[2], p[2])
            end
        end
        return col
    end
    frame(state)
    local rest = profile()

    -- Con un pez enganchado y la linea tensa hasta el aviso. Se toma la foto
    -- MIENTRAS esta tensa: rodando sin parar la linea se rompe en menos de un
    -- segundo, y rota la cana vuelve a estar recta.
    if bite(state) then
        local bent, held, a, t = nil, false, 0, 0
        while t < 5 do
            if not held then Reel.grab(knob(a)); held = true end
            a = a + 6 * DT
            Reel.roll(knob(a))
            local ev = Reel.update(DT, true, state)
            World.step(state, DT)
            frame(state)
            t = t + DT
            if alarmed() then bent = profile(); break end
            if ev then break end
        end
        Reel.drop()
        bent = bent or profile()
        local tx = select(1, Reel.tip())
        local cx = select(1, Reel.center())
        local function drop(at)
            local x = math.floor(tx + (cx - tx) * at)
            for dx = 0, 3 do
                if rest[x + dx] and bent[x + dx] then
                    return bent[x + dx] - rest[x + dx]
                end
            end
            return nil
        end
        local tip, mid, butt = drop(0.02), drop(0.5), drop(0.95)
        check("la punta de la cana es la que baja",
              tip and mid and butt and tip > mid and mid > butt,
              string.format("punta %s, medio %s, puno %s",
                            tostring(tip), tostring(mid), tostring(butt)))
        check("y el puno sale recto", butt and butt <= 1,
              string.format("el puno bajo %s px", tostring(butt)))
    end
end

-- FISH_W esta escrito en el modulo para saber cuando el CUERPO del pez toca la
-- banda, y aqui se comprueba contra el pez que de verdad se pinta: si la
-- silueta cambia y el numero no, la banda mentiria medio pez.
do
    local state = sea(5)
    if bite(state) then
        local _, _, w = fish()
        check("el ancho del pez es el que dice el modulo", w == 11,
              string.format("se pintan %s px, el modulo dice 11", tostring(w)))
    end
end

--== Reposo =================================================================
--
-- La leccion de la driza, y aqui hay que separar dos cosas que parecen la
-- misma. El APAREJO tiene que estar inmovil hasta el ultimo pixel entre pique
-- y pique: la cana no se comba sola y el carrete no gira solo, exactamente
-- como la driza cuelga quieta. Pero el CORCHO tiene que moverse, y no es una
-- excepcion de gusto: un corcho en el agua no esta quieto nunca, y uno que se
-- para esta roto. Ocho segundos de pantalla congelada no se leen como esperar
-- un pique, se leen como que el juego se ha colgado -- que es exactamente el
-- fallo que hubo que arreglar despues de probarlo con el pulgar.
--
-- Asi que se miden las dos cosas por separado, y por COLOR: la madera (cana y
-- carrete) tiene que repetirse identica cuadro a cuadro, y el corcho tiene que
-- haberse movido.

print("== reposo ==")

-- Los rectangulos de un color concreto, como una firma comparable.
local function stamp(list, ...)
    local want = { ... }
    local out = {}
    for _, p in ipairs(list) do
        for _, c in ipairs(want) do
            if p[5] == c then
                out[#out + 1] = string.format("%d,%d,%d,%d", p[1], p[2], p[3], p[4])
            end
        end
    end
    return table.concat(out, " ")
end

do
    local state = sea(3)
    local first, moved, bobbed = nil, nil, false
    local firstFloat
    for i = 1, 120 do                          -- dos segundos, antes de BITE_MIN
        Reel.update(DT, true, state)
        World.step(state, DT)
        local now = frame(state)
        local wood = stamp(now, Palette.wood, Palette.woodLite, Palette.woodDark)
        local cork = stamp(now, Palette.sand)
        if not first then first, firstFloat = wood, cork end
        if wood ~= first and not moved then moved = i end
        if cork ~= firstFloat then bobbed = true end
    end
    check("el aparejo no mueve un pixel", moved == nil,
          "la madera cambio en el cuadro " .. tostring(moved))
    check("pero el corcho cabecea", bobbed,
          "el corcho no se movio en dos segundos")
    check("y no hay pez todavia", fish() == nil)
end

--== Cuando pica ============================================================

print("== el pique ==")
do
    local state = sea(11)
    check("picando navegando", bite(state) ~= nil)

    -- Amarrado no corre la singladura: tampoco la cana.
    local port = World.new(12)
    Reel.reset()
    for _ = 1, 30 do Reel.update(DT, true, port); World.step(port, DT) end
    check("en puerto no pica", bite(port, 25) == nil)

    -- Con la bodega llena SI pica: es el estado en el que se vuelve de una
    -- ausencia larga, y apagar ahi la pesca a mano la apagaba justo cuando mas
    -- rato se lleva mirando la pantalla. Lo que no cabe lo dice la bitacora.
    local full = sea(13)
    full.res.fish = Ship.capacity(full)
    check("con la bodega llena se pesca igual", bite(full, 25) ~= nil)

    -- Y con el redal guardado no pasa nada de nada.
    local stowed = World.new(14)
    World.undock(stowed)
    Reel.reset()
    local seen = false
    for _ = 1, 60 * 25 do
        Reel.update(DT, false, stowed)
        World.step(stowed, DT)
        frame(stowed)
        if fish() then seen = true; break end
    end
    check("con el redal guardado no pica", not seen)
end

--== Decir por que no pasa nada ============================================
--
-- El fallo que se colo hasta el pulgar: amarrado se sacaba el redal, el sedal
-- caia al agua y ahi se quedaba para siempre, sin pique y sin una sola pista.
-- Y amarrado es donde EMPIEZA la partida. Un mando que no puede funcionar
-- tiene que decirlo; callarse es lo mismo que estar averiado.

print("== por que no pica ==")
do
    local docked = World.new(90)
    check("amarrado, el redal dice por que", Reel.idle(docked) ~= nil,
          tostring(Reel.idle(docked)))

    local sailing = World.new(90)
    World.undock(sailing)
    check("navegando no dice nada", Reel.idle(sailing) == nil,
          tostring(Reel.idle(sailing)))

    local loaded = World.new(90)
    World.undock(loaded)
    loaded.res.fish = Ship.capacity(loaded)
    check("y con la bodega llena tampoco: se pesca", Reel.idle(loaded) == nil,
          tostring(Reel.idle(loaded)))

    -- Amarrado el corcho se queda colgando de la punta, fuera del agua: la
    -- cana no esta pescando y se ve que no lo esta.
    Reel.reset()
    for _ = 1, 30 do Reel.update(DT, true, docked) World.step(docked, DT) end
    local high = frame(docked)
    Reel.reset()
    for _ = 1, 30 do Reel.update(DT, true, sailing) World.step(sailing, DT) end
    local wet = frame(sailing)
    local function corkY(list)
        local y for _, p in ipairs(list) do
            if p[5] == Palette.sand then y = math.max(y or p[2], p[2]) end
        end
        return y
    end
    check("y el corcho esta fuera del agua", corkY(high) and corkY(wet)
          and corkY(high) < corkY(wet) - 20,
          string.format("amarrado %s, navegando %s",
                        tostring(corkY(high)), tostring(corkY(wet))))
end

--== Dejarlo correr =========================================================

print("== se escapa solo ==")
do
    local state = sea(21)
    check("pica", bite(state) ~= nil)
    -- Se mide DESPUES del tiron del pique: mientras la cana esta combada el
    -- pez se pinta unos pixeles corrido, que es la comba y no el pez.
    play(state, 0.4)
    local x0 = fish()
    play(state, 1.5)
    local x1 = fish()
    check("soltado, el pez tira hacia babor", x1 and x1 < x0 - 2,
          string.format("%.0f -> %.0f", x0 or -1, x1 or -1))

    local under = true
    for _, p in ipairs(painted) do if p[5] == Palette.sand then under = false end end
    check("y al picar el corcho se ha hundido", under,
          "el corcho sigue pintado con un pez enganchado")

    local ev, t = play(state, 20)
    check("y acaba escapandose", ev and ev.kind == "gone",
          ev and ev.kind or "no paso nada")
    check("pero da tiempo a reaccionar", t > 3,
          string.format("%.1f s desde el pique", t + 0.5))
end

--== Rodar sin mirar ========================================================
--
-- La estrategia degenerada de todo mando que se rueda: rodar sin parar. Tiene
-- que perder, y tiene que perder ROMPIENDO LA LINEA, que es lo que ensena por
-- que ha perdido.

print("== rodar como un poseso ==")
do
    local snapped, caught = 0, 0
    for seed = 30, 37 do
        local state = sea(seed)
        if bite(state) then
            local ev = play(state, 25, function() return 9 end)
            if ev and ev.kind == "snap" then snapped = snapped + 1 end
            if ev and ev.kind == "catch" then caught = caught + 1 end
        end
    end
    check("rodar sin parar rompe la linea", snapped == 8,
          string.format("%d rotas, %d cobradas de 8", snapped, caught))

    -- Y avisa antes: el sedal se pone rojo con tiempo de soltar.
    local state = sea(41)
    bite(state)
    local warned = 0
    play(state, 25, function()
        if alarmed() then warned = warned + 1 end
        return 9
    end)
    check("y avisa antes de romperse", warned > 12,
          string.format("%d cuadros de aviso", warned))
end

--== Un jugador que mira la pantalla ========================================
--
-- El bot no lee una sola variable del modulo: mira donde esta el pez, si esta
-- de oro (en la banda) y si el sedal esta rojo, que es lo mismo que ve
-- cualquiera. Con eso tiene que cobrar, y tiene que costarle un rato: si
-- cobra en tres segundos el mando no es un mando, y si no cobra nunca es que
-- la pelea no se puede ganar mirando la pantalla.

print("== se puede pescar mirando la pantalla ==")
do
    local RATE = 3.5      -- radianes por segundo: un pulgar rodando con ganas

    -- Las tres senales que da el dibujo, y nada mas: el pez (esta o no esta),
    -- su color (oro = en la banda, o sea rodar sale gratis) y el sedal rojo
    -- (la linea se va a romper). Con eso basta para pelear, y eso es lo que
    -- comprueba la prueba.
    local function player(state)
        local x, gold = fish()
        if not x then return 0 end
        if alarmed() then return 0 end          -- el aviso: soltar y dejar aflojar
        if gold then return RATE end            -- en la banda: rodar sale gratis
        return RATE * 0.75                      -- fuera: rodar con tiento, se paga
    end

    local landed, times, lost = 0, {}, {}
    for seed = 50, 61 do
        local state = sea(seed)
        if bite(state) then
            local ev, t = play(state, 60, player)
            if ev and ev.kind == "catch" then
                landed = landed + 1
                times[#times + 1] = t
            else
                lost[#lost + 1] = ev and ev.kind or "nada"
            end
        end
    end

    check("un jugador atento cobra casi siempre", landed >= 10,
          string.format("%d de 12 (%s)", landed, table.concat(lost, ",")))
    print(string.format("       [%d de 12 cobrados]", landed))

    local sum, worst = 0, 0
    for _, t in ipairs(times) do sum = sum + t; worst = math.max(worst, t) end
    local mean = (#times > 0) and (sum / #times) or 0
    check("y la pelea dura lo que tiene que durar", mean > 6 and mean < 30,
          string.format("media %.1f s, la peor %.1f s", mean, worst))
    print(string.format("       [media %.1f s, la peor %.1f s]", mean, worst))

    -- Y no de casualidad: rodar en el momento que toca tiene que ganarle a
    -- rodar siempre, que es lo que separa el mando de un boton.
    local hammer = 0
    for seed = 50, 61 do
        local state = sea(seed)
        if bite(state) then
            local ev = play(state, 60, function() return RATE end)
            if ev and ev.kind == "catch" then hammer = hammer + 1 end
        end
    end
    check("y mirando se pesca mas que sin mirar", landed > hammer,
          string.format("mirando %d, sin mirar %d", landed, hammer))
end

--== La cedida =============================================================
--
-- Cortarle una arrancada al pez -- que entre en la banda HUYENDO y se recoja
-- de verdad en las decimas siguientes -- tiene premio: el pez cede unos
-- segundos, tira mucho menos y el freno aguanta mas. Es lo unico de la pelea
-- que paga por estar mirando, asi que hay que comprobar dos cosas: que ocurre
-- y que SE VE, porque un premio invisible no ensena a jugar.

print("== la cedida ==")
do
    local RATE = 3.5
    local seen, gainOn, gainOff, framesOn, framesOff = false, 0, 0, 0, 0

    for seed = 70, 81 do
        local state = sea(seed)
        if bite(state) then
            local held, a, t = false, 0, 0
            local last = fish()
            while t < 30 do
                local x, gold = fish()
                local rate = 0
                if x and not alarmed() then rate = gold and RATE or RATE * 0.75 end
                if rate > 0 then
                    if not held then Reel.grab(knob(a)); held = true end
                    a = a + rate * DT
                    Reel.roll(knob(a))
                elseif held then Reel.drop(); held = false end

                local ev = Reel.update(DT, true, state)
                World.step(state, DT)
                frame(state)
                t = t + DT

                -- Lo que avanza el pez con la misma mano, cediendo y sin ceder.
                local now, _ = fish()
                if now and last and rate > 0 then
                    if turned() then
                        seen = true
                        gainOn = gainOn + (now - last); framesOn = framesOn + 1
                    else
                        gainOff = gainOff + (now - last); framesOff = framesOff + 1
                    end
                end
                last = now
                if ev then if held then Reel.drop() end break end
            end
        end
    end

    check("el pez llega a ceder", seen, "no cedio ni una vez en doce peleas")
    local on = (framesOn > 0) and (gainOn / framesOn) or 0
    local off = (framesOff > 0) and (gainOff / framesOff) or 0
    check("y cediendo se le gana mas terreno", on > off * 1.15,
          string.format("cediendo %.4f px/cuadro, peleando %.4f", on, off))
    print(string.format("       [cediendo %.3f px/cuadro contra %.3f peleando, %.0f%% del tiempo]",
          on, off, 100 * framesOn / math.max(1, framesOn + framesOff)))
end

--== Guardar el redal =======================================================

print("== guardar el redal ==")
do
    local state = sea(70)
    check("pica", bite(state) ~= nil)
    local ev = Reel.update(DT, false, state)
    check("guardarlo con un pez enganchado lo pierde",
          ev and ev.kind == "gone", ev and ev.kind or "no paso nada")
    check("y no lo pierde dos veces", Reel.update(DT, false, state) == nil)
    frame(state)
    check("y deja de pintarse el pez", fish() == nil)
end

--== Lo que llega a la bodega ===============================================

print("== el pez a bordo ==")
do
    local state = World.new(80)
    World.undock(state)
    local before = state.res.fish
    local added = World.landFish(state, 10)
    check("un pez cobrado entra en bodega", added == 10 and state.res.fish == before + 10,
          string.format("+%d", added))

    -- Y respeta el tope como todo lo que sube a bordo.
    state.res.fish = Ship.capacity(state) - 3
    local squeezed = World.landFish(state, 10)
    check("y no revienta el tope de bodega", squeezed <= 3.0001,
          string.format("entraron %.1f", squeezed))

    -- Pelear un pez y que no pase nada visible es la misma averia que un mando
    -- que se calla: con la bodega llena la bitacora tiene que decirlo.
    state.res.fish = Ship.capacity(state)
    local lines = #state.log
    local none = World.landFish(state, 10)
    check("un pez que no cabe tambien se cuenta",
          none == 0 and #state.log > lines,
          string.format("entraron %.1f, %d lineas nuevas", none, #state.log - lines))
end

print("")
print(string.format("%d comprobaciones, %d fallos", checks, failures))
os.exit(failures == 0 and 0 or 1)
