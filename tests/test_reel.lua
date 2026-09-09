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
    return (x0 + x1) / 2, gold
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

--== Reposo =================================================================
--
-- La leccion de la driza, otra vez: entre pique y pique NO se mueve un solo
-- pixel. Aqui es mas facil de cumplir --sin pez no se integra nada-- y por
-- eso mismo la prueba es barata: dos cuadros seguidos tienen que ser
-- IDENTICOS, rectangulo a rectangulo.

print("== reposo ==")
do
    local state = sea(3)
    local before
    local moved, when = false, nil
    for i = 1, 120 do                          -- dos segundos, antes de BITE_MIN
        Reel.update(DT, true, state)
        World.step(state, DT)
        local now = frame(state)
        if before then
            local same = #now == #before
            if same then
                for j = 1, #now do
                    local a, b = now[j], before[j]
                    if a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3] or a[4] ~= b[4] then
                        same = false; break
                    end
                end
            end
            if not same and not moved then moved, when = true, i end
        end
        before = now
    end
    check("sin pique no se mueve un pixel", not moved,
          "cambio en el cuadro " .. tostring(when))
    check("y hay algo pintado", #before > 100, tostring(#before) .. " rectangulos")
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

    -- Con la bodega llena el pez no cabria, asi que no pica: cobrar para nada
    -- es peor que no cobrar.
    local full = sea(13)
    full.res.fish = Ship.capacity(full)
    check("con la bodega llena no pica", bite(full, 25) == nil)

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

    local sum, worst = 0, 0
    for _, t in ipairs(times) do sum = sum + t; worst = math.max(worst, t) end
    local mean = (#times > 0) and (sum / #times) or 0
    check("y la pelea dura lo que tiene que durar", mean > 6 and mean < 30,
          string.format("media %.1f s, la peor %.1f s", mean, worst))

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
end

print("")
print(string.format("%d comprobaciones, %d fallos", checks, failures))
os.exit(failures == 0 and 0 or 1)
