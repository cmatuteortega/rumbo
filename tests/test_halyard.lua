-- Prueba de la driza del velamen, sin ventana.
--
--     lua5.1 tests/test_halyard.lua
--
-- Va aparte de tests/test_sim.lua y por una razon: la simulacion no puede
-- requerir love y por eso se prueba tal cual, pero la driza es DIBUJO -- vive
-- en pixeles de arte y se mide en pantalla -- asi que hace falta un love de
-- mentira. Lo que se prueba aqui no es balance, es fisica y geometria.
--
-- Y esta aqui porque las dos cosas que salieron mal al escribirla no se veian
-- mirando la pantalla un rato, solo midiendo:
--
--   * la cuerda se DOBLABA sobre si misma en el rebote y se quedaba encogida
--     para siempre, ensenando un tercio del largo que decia tener. Un tramo
--     vuelto del reves es un equilibrio del solver, asi que no se arreglaba
--     solo. Se mira el invariante de una cuerda tensa: el arco que se dibuja
--     mide lo mismo que la recta del ancla al nudo.
--   * y no se estaba QUIETA en reposo. Temblaba un pixel de arte -- cinco de
--     pantalla -- indefinidamente, primero por el zumbido de los tramos
--     cortos y despues por la cola infinita del pendulo y del muelle. Se mira
--     que despues de asentarse no se mueva NADA.
--
-- Todo se lee del dibujo, que es lo unico que ve el jugador: el nudo son las
-- tiras mas anchas que se pintan (las filas centrales de su disco) y el arco
-- son los sellos de ROPExROPE de la cuerda, uno por pixel recorrido.
--
-- El grosor va aqui repetido a proposito: si cambia en el modulo, estas
-- medidas dejan de encontrar la cuerda y los tests fallan RUIDOSAMENTE en vez
-- de medir el contorno por accidente, que es lo que pasaria si se buscara "el
-- cuadrado mas comun". El nudo, en cambio, se busca sin numeros: la tira mas
-- ancha de una fila de alto es suya y de nadie mas, asi que su radio puede
-- cambiar sin tocar esto.
local ROPE = 2

package.path = "./?.lua;" .. package.path

-- love de mentira: apuntar lo que se pinta y tragarse todo lo demas.
local painted = {}
local function nop() end
love = setmetatable({}, { __index = function()
    return setmetatable({}, { __index = function() return nop end })
end })
love.graphics = setmetatable({
    rectangle = function(mode, x, y, w, h) painted[#painted + 1] = { x, y, w, h } end,
    push = nop, pop = nop, scale = nop, setColor = nop, draw = nop,
}, { __index = function() return nop end })

local Constants = require('src.constants')
local Compass   = require('src.compass')
local Halyard   = require('src.halyard')

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

--== Lo que se puede medir del dibujo =======================================

-- Nudo (centro), comba y arco, todo en pixeles de ARTE.
--
-- El nudo es un disco PAR: sus filas mas anchas son varias y quedan
-- simetricas alrededor del centro, asi que el centro se saca del medio de esas
-- filas y no de una sola. Medir "la primera fila que mida tanto" daba el borde
-- del disco de tinta, tres pixeles mas arriba, que es un error que ya se colo
-- una vez en un ayudante de depuracion.
local function shape()
    painted = {}
    Halyard.draw({ trim = "x" })
    local arc, wide = 0, 0
    for _, p in ipairs(painted) do
        if p[4] == 1 then wide = math.max(wide, p[3]) end
        if p[3] == ROPE and p[4] == ROPE then arc = arc + 1 end
    end
    local kx, top, bottom = nil, nil, nil
    for _, p in ipairs(painted) do
        if p[4] == 1 and p[3] == wide then
            kx = p[1] + wide / 2
            top = math.min(top or p[2], p[2])
            bottom = math.max(bottom or p[2], p[2])
        end
    end
    local ky = (top + bottom + 1) / 2
    local ax, ay = Halyard.anchor()
    local dx, dy = kx - ax, ky - ay
    local straight = math.sqrt(dx * dx + dy * dy)
    local bow = 0
    if straight > 1 then
        for _, p in ipairs(painted) do
            if p[3] == ROPE and p[4] == ROPE then
                local sx, sy = p[1] + ROPE / 2, p[2] + ROPE / 2
                local off = math.abs((sx - ax) * dy - (sy - ay) * dx)
                bow = math.max(bow, off / straight)
            end
        end
    end
    return kx, ky, straight, arc, bow
end

-- `out` es si la driza esta PEDIDA, que es lo que la saca o la guarda. Por
-- omision, pedida: es el estado en el que se mide todo lo demas.
local function run(state, seconds, out)
    if out == nil then out = true end
    local left = seconds
    while left > 0 do
        local step = math.min(1 / 60, left)
        Halyard.update(step, out, state)
        left = left - step
    end
end

-- Donde tiene que colgar el nudo, en virtual, segun el trapo.
local function restY(trim)
    if trim == "reef" then return Constants.GAME_HEIGHT / 2 end
    return select(2, Compass.center())
end

-- Una maniobra completa: agarrar, arrastrar y soltar.
local function pull(state, fromY, toX, toY)
    Halyard.grab(30, fromY)
    Halyard.haul(toX, toY)
    run(state, 0.2)
    local trim = Halyard.drop(state)
    if trim then state.trim = trim end
    return trim
end

-- El arco lleva un sello de mas por nodo y el nudo tapa un trozo, asi que la
-- igualdad con la recta es holgada. Doblada, el arco mide VARIAS veces.
local function taut(name)
    local _, _, straight, arc = shape()
    check(name, arc <= straight * 1.25 + 20,
          string.format("recta %.0f, arco %.0f", straight, arc))
end

--== Geometria ==============================================================

print("== donde cuelga ==")
Constants.updateResolution(540, 960)
local s = { trim = "full" }
Halyard.reset()
run(s, 0.5, false)
check("guardada no se ve", not Halyard.showing())
run(s, 1.0)
check("largada se ve", Halyard.showing())
run(s, 0.5, false)
check("y se recoge sola al guardarla", not Halyard.showing())
run(s, 1.0)

local _, ky = shape()
check("con trapo largo, el nudo a la altura de la rosa",
      math.abs(ky * Constants.ART - restY("full")) < 25,
      string.format("%.0f vs %.0f", ky * Constants.ART, restY("full")))

s.trim = "reef"
run(s, 2.0)
local kx
kx, ky = shape()
check("con rizos, el nudo a media pantalla",
      math.abs(ky * Constants.ART - restY("reef")) < 25,
      string.format("%.0f vs %.0f", ky * Constants.ART, restY("reef")))
check("y siempre por babor", kx * Constants.ART < 90,
      string.format("%.0f", kx * Constants.ART))

-- El lienzo no es 540x960: el alto cambia con la pantalla, y los dos largos de
-- driza salen de donde estan las cosas, no de numeros escritos a mano.
print("== y en cualquier lienzo ==")
for _, size in ipairs({ { 540, 960 }, { 540, 1215 }, { 562, 960 }, { 1493, 960 } }) do
    Constants.updateResolution(size[1], size[2])
    local st = { trim = "reef" }
    Halyard.reset()
    run(st, 2.0)
    local _, y = shape()
    local logTop = Constants.GAME_HEIGHT - Constants.SAFE_BOTTOM - 228
    check(string.format("%dx%d: cuelga a media pantalla",
                        Constants.GAME_WIDTH, Constants.GAME_HEIGHT),
          math.abs(y * Constants.ART - restY("reef")) < 25)
    -- Tirando a fondo no puede llegar a la bitacora, que esta abajo a babor.
    pull(st, y * Constants.ART, 34, Constants.GAME_HEIGHT * 3)
    run(st, 0.3)
    local _, deep = shape()
    check(string.format("%dx%d: ni tirando a fondo llega a la bitacora",
                        Constants.GAME_WIDTH, Constants.GAME_HEIGHT),
          deep * Constants.ART < logTop,
          string.format("%.0f vs %.0f", deep * Constants.ART, logTop))
end

--== Las dos maniobras ======================================================
--
-- No son simetricas: recoger cuesta un arrastre largo y largar un tiron corto.

print("== tomar rizos: arrastre largo ==")
Constants.updateResolution(540, 960)
s = { trim = "full" }
Halyard.reset()
run(s, 1.5)
check("un arrastre corto no toma rizos",
      pull(s, restY("full"), 34, restY("full") + 100) == nil)
run(s, 1.5)
check("un arrastre largo si",
      pull(s, restY("full"), 34, restY("full") + 300) == "reef")
run(s, 2.5)

print("== largar trapo: tiron corto ==")
check("medio tiron no larga trapo",
      pull(s, restY("reef"), 34, restY("reef") + 50) == nil)
run(s, 1.5)
check("el tiron entero si",
      pull(s, restY("reef"), 34, restY("reef") + 120) == "full")

-- El rebote: el nudo tiene que pasarse del reposo (si no, no es un rebote) sin
-- llegar al tope de cuerda, porque un tope que se ve es una mentira.
local highest = 1e9
for _ = 1, 90 do
    Halyard.update(1 / 60, true, s)
    highest = math.min(highest, select(2, shape()) * Constants.ART)
end
check("y la cuerda rebota por encima del reposo", highest < restY("full") - 20,
      string.format("sube a %.0f, reposo %.0f", highest, restY("full")))
check("pero no hasta el tope", highest > 30, string.format("%.0f", highest))
run(s, 2.0)
check("y acaba a la altura de la rosa",
      math.abs(select(2, shape()) * Constants.ART - restY("full")) < 25)

--== Se agarra donde se ve ==================================================

print("== agarre ==")
s.trim = "reef"
run(s, 2.5)
local _, ry = shape()
check("el nudo se agarra", Halyard.contains(30, ry * Constants.ART))
check("y la cuerda por el medio", Halyard.contains(30, ry * Constants.ART / 2))
check("no se agarra desde la rosa", not Halyard.contains(270, 122))
check("ni desde la esquina de la rueda",
      not Halyard.contains(Constants.GAME_WIDTH - 20, Constants.GAME_HEIGHT - 20))

--== Tensa siempre, y quieta en reposo ======================================

print("== ni se dobla ni tiembla ==")
taut("colgada esta tensa")

-- Treinta maniobras agarrando a distintas alturas y tirando en diagonal. Lo
-- que se exige es lo de despues de asentarse: combarse un instante al soltar
-- es legitimo -- la cuerda va floja y se comba -- doblarse y quedarse asi, no.
local worstBow, worstRest, worstMove = 0, 0, 0
for i = 1, 30 do
    local _, y0 = shape()
    pull(s, y0 * Constants.ART * (0.2 + 0.7 * ((i % 5) / 5)),
         30 + (i % 4) * 90, (s.trim == "full") and 520 or 640)
    run(s, 5.0)          -- un zarandeo lateral tarda unos segundos en morirse
    local _, y, straight, arc, bow = shape()
    worstBow  = math.max(worstBow, arc - (straight * 1.25 + 20))
    worstRest = math.max(worstRest, math.abs(y * Constants.ART - restY(s.trim)))

    -- Y en reposo, INMOVIL: ni un pixel de un cuadro a otro.
    local lx, ly = shape()
    for _ = 1, 120 do
        Halyard.update(1 / 60, true, s)
        local nx, ny, _, _, b = shape()
        worstMove = math.max(worstMove, math.abs(nx - lx) + math.abs(ny - ly))
        worstBow = math.max(worstBow, b - 0.5)
        lx, ly = nx, ny
    end
end
check("asentada siempre queda tensa", worstBow <= 0,
      string.format("peor exceso %.2f", worstBow))
check("el nudo vuelve a donde dice el trapo", worstRest < 30,
      string.format("peor desvio %.0f px", worstRest))
check("y en reposo no se mueve ni un pixel", worstMove == 0,
      string.format("se movio %.0f px de arte", worstMove))

--== El nudo va centrado en la cuerda =======================================
--
-- La cuerda tiene grosor PAR, asi que su banda cae a caballo de la posicion y
-- su eje esta en medio pixel. Un disco impar se centra por fuerza en un pixel
-- entero, o sea medio pixel a estribor, y como aqui no hay medios pixeles el
-- nudo volaba tres columnas por babor y CUATRO por estribor: se veia colgado
-- de lado. Esto no se ve mirando un rato -- son cinco pixeles de pantalla en
-- una pieza de cincuenta -- pero se nota, y se rompe en silencio en cuanto
-- alguien toque el grosor o el radio, asi que se mide.

print("== el nudo va centrado ==")

-- Eje de la CUERDA: las columnas que se pintan en una fila entera dada, a
-- media caida, lejos del nudo y del ancla.
local function ropeAxis(row)
    local lo, hi = nil, nil
    for _, p in ipairs(painted) do
        if p[2] <= row and row <= p[2] + p[4] - 1 then
            lo = math.min(lo or p[1], p[1])
            hi = math.max(hi or (p[1] + p[3] - 1), p[1] + p[3] - 1)
        end
    end
    return lo and (lo + hi) / 2
end

-- Eje del NUDO: de sus filas mas anchas, sin pasar por ninguna fila concreta.
-- Preguntar por "la fila del ecuador" no sirve para medir esto: con el disco
-- impar el ecuador cae en medio pixel, ninguna fila lo contiene y la medida se
-- volvia la de la cuerda, o sea que el test se aprobaba a si mismo. Lo
-- comprobe volviendo a poner el disco impar a mano, y pasaba.
local function knotAxis()
    local wide = 0
    for _, p in ipairs(painted) do
        if p[4] == 1 then wide = math.max(wide, p[3]) end
    end
    local lo, hi = nil, nil
    for _, p in ipairs(painted) do
        if p[4] == 1 and p[3] == wide then
            lo = math.min(lo or p[1], p[1])
            hi = math.max(hi or (p[1] + p[3] - 1), p[1] + p[3] - 1)
        end
    end
    return (lo + hi) / 2
end

local worstOff = 0
for _, trim in ipairs({ "full", "reef" }) do
    s.trim = trim
    Halyard.reset()
    run(s, 3.0)
    local _, ky = shape()               -- deja `painted` con el dibujo en reposo
    local ay = select(2, Halyard.anchor())
    local ejeCuerda = ropeAxis(math.floor((ay + ky) / 2))
    local ejeNudo = knotAxis()
    worstOff = math.max(worstOff, math.abs(ejeNudo - ejeCuerda))
    check("comparten eje con trapo " .. trim, ejeNudo == ejeCuerda,
          string.format("cuerda %.1f, nudo %.1f", ejeCuerda, ejeNudo))
end
check("y el nudo vuela lo mismo a los dos lados", worstOff == 0,
      string.format("peor descentrado %.1f px de arte", worstOff))

--== Cuanto tarda en callarse ===============================================
--
-- No basta con que acabe quieta: tiene que callarse PRONTO. Y la cuerda corta
-- no puede tardar mas que la larga, que es como se noto la ultima vez que esto
-- estuvo mal -- con amortiguacion por cuadro la corta oscila el doble de rapido
-- y pierde la mitad de amplitud en cada vaiven, asi que en tiempo real tardaba
-- mas justo la que peor lo disimula.

print("== se calla pronto ==")

-- Cuadros hasta que el dibujo deja de cambiar del todo.
local function quietAfter(state, seconds)
    local last, streak = nil, 0
    for f = 1, math.floor(seconds * 60) do
        Halyard.update(1 / 60, true, state)
        painted = {}
        Halyard.draw(state)
        local sig = 0
        for _, p in ipairs(painted) do
            sig = (sig * 31 + p[1] * 7919 + p[2] * 104729) % 2147483647
        end
        streak = (sig == last) and (streak + 1) or 0
        last = sig
        if streak == 30 then return (f - 30) / 60 end
    end
    return nil
end

for _, case in ipairs({ { "full", "tras tomar rizos", 300 },
                        { "reef", "tras largar trapo", 120 } }) do
    local st = { trim = case[1] }
    Halyard.reset()
    run(st, 2.5)
    pull(st, restY(case[1]), 34, restY(case[1]) + case[3])
    local t = quietAfter(st, 4)
    check("se queda quieta " .. case[2], t ~= nil and t < 1.5,
          t and string.format("%.2f s", t) or "no se callo en 4 s")
end

-- Y con un zarandeo lateral, que es lo que mas la mueve: la corta antes que la
-- larga, no al reves.
local settle = {}
for _, trim in ipairs({ "full", "reef" }) do
    local st = { trim = trim }
    Halyard.reset()
    run(st, 2.5)
    Halyard.grab(30, restY(trim))
    Halyard.haul(30 + restY(trim) * 0.35, restY(trim))
    run(st, 0.15)
    Halyard.drop(st)
    settle[trim] = quietAfter(st, 6)
    check("zarandeada de lado, se calma (" .. trim .. ")",
          settle[trim] ~= nil, "no se callo en 6 s")
end
check("y la cuerda corta se calma antes que la larga",
      settle.full and settle.reef and settle.full < settle.reef,
      string.format("corta %.2f s, larga %.2f s", settle.full or -1, settle.reef or -1))

--== El remate va en un solo sentido =======================================
--
-- Lo que se lee como temblor no es cuanto se mueve, es que CAMBIE DE SENTIDO
-- moviendose poco: un pixel de arte son cinco de pantalla, asi que uno de ida y
-- otro de vuelta parpadean por pocos que sean, mientras que tres de ida
-- seguidos se leen como algo posandose. Asi que se exige que los ultimos
-- cuadros que se mueven vayan todos hacia el mismo lado.

print("== el remate no tiembla ==")

for _, case in ipairs({ { "full", "tras tomar rizos", 300 },
                        { "reef", "tras largar trapo", 120 } }) do
    local st = { trim = case[1] }
    Halyard.reset()
    run(st, 2.5)
    pull(st, restY(case[1]), 34, restY(case[1]) + case[3])

    -- Cada cuadro en el que el nudo cambia de sitio, con su sentido.
    local moves = {}
    local _, prev = shape()
    for _ = 1, 240 do
        Halyard.update(1 / 60, true, st)
        local _, y = shape()
        if y ~= prev then moves[#moves + 1] = y - prev end
        prev = y
    end

    -- El rebote tiene UN cambio de sentido y es el suyo (sube y vuelve), pero
    -- el remate -- los ultimos movimientos -- tiene que ser de una pieza.
    local tail, ok = {}, true
    for i = math.max(1, #moves - 5), #moves do
        tail[#tail + 1] = moves[i]
        if moves[i] * moves[#moves] < 0 then ok = false end
    end
    local shown = {}
    for i, d in ipairs(tail) do shown[i] = string.format("%+d", d) end
    check("los ultimos cuadros van a una " .. case[2], ok,
          table.concat(shown, " "))

    -- Y ninguno da un salto de mas de un pixel, que se leeria como un tiron
    -- aparte en vez de como el final del movimiento.
    local biggest = 0
    for i = math.max(1, #moves - 5), #moves do
        biggest = math.max(biggest, math.abs(moves[i]))
    end
    check("y de un pixel, no a saltos " .. case[2], biggest <= 1,
          string.format("el mayor fue %.0f", biggest))
end

--== Pendulo ================================================================
--
-- Zarandeada tiene que balancearse como un pendulo -- varios vaivenes que
-- decaen -- y no plantarse en medio segundo ni temblar sin parar.

print("== pendulo ==")
s.trim = "reef"
Halyard.reset()
run(s, 2.5)
local ax = Halyard.anchor()
Halyard.grab(30, restY("reef"))
Halyard.haul(240, restY("reef") + 40)
run(s, 0.2)
Halyard.drop(s)

local crossings, peak, sign = 0, 0, 0
for _ = 1, 210 do                       -- tres segundos y medio
    Halyard.update(1 / 60, true, s)
    local x = shape()
    local off = x - ax
    peak = math.max(peak, math.abs(off))
    local now = (off > 0.5 and 1) or (off < -0.5 and -1) or 0
    if now ~= 0 and sign ~= 0 and now ~= sign then crossings = crossings + 1 end
    if now ~= 0 then sign = now end
end
check("se balancea de verdad", peak > 8, string.format("pico %.0f px de arte", peak))
check("y va y viene, no se planta", crossings >= 3,
      string.format("%d pasadas por el plomo", crossings))
run(s, 4.0)
check("y acaba durmiendose a plomo", math.abs(select(1, shape()) - ax) < 1,
      string.format("%.1f px del plomo", math.abs(select(1, shape()) - ax)))

print("")
print(string.format("%d comprobaciones, %d fallos", checks, failures))
os.exit(failures == 0 and 0 or 1)
