-- Prueba del mar, sin ventana.
--
--     lua5.1 tests/test_sea.lua
--
-- Va aparte de tests/test_sim.lua por lo mismo que la de la driza: la
-- simulacion no puede requerir love y se prueba tal cual, pero el mar es
-- DIBUJO, asi que hace falta un love de mentira que apunte lo que se pinta.
--
-- Desde que el agua la pinta un shader (src/surface.lua) el love de mentira
-- apunta ademas los UNIFORMES: lo que se le manda al shader es exactamente lo
-- que decide como se ve el mar, y se puede medir sin una tarjeta grafica
-- delante. Es la misma idea de siempre -- leer del dibujo en vez de mirar la
-- pantalla --, solo que ahora el dibujo son doce numeros.
--
-- Lo que vigila:
--
--   * la REGLA 1. Ni una llamada con rotacion, tampoco la del shader. El love
--     de mentira PETA si alguien lo intenta.
--   * que el mar se peine con el viento. El campo de espuma se estira A TRAVES
--     del viento, asi que sus dos ejes tienen que salir a noventa grados, el
--     largo tiene que caer justo donde cae el viento en pantalla, y los dos
--     tienen que girar cuando gira el barco -- que es lo unico que hace que el
--     mar se vea distinto en cada rumbo. Mirando la pantalla se ve que hay
--     diagonales; que sean LAS diagonales, no.
--   * que con poco viento el mar este de verdad mas quieto, y que en calma no
--     pueda salir un pixel blanco. Eso ultimo no es "salen pocos": el escalon
--     del blanco se manda por encima de uno, que es mas de lo que la cuenta de
--     espuma puede dar en ningun pixel.
--   * que el agua DESFILE a sotavento y corra por debajo del barco cuando anda.
--
-- La estela se mide igual: los brazos de la V solo dicen la verdad si se abren
-- con lo que el barco ANDA, y eso son dos capturas y una resta.

package.path = "./?.lua;" .. package.path

-- love de mentira: apuntar lo que se pinta y tragarse todo lo demas.
local painted = {}   -- { id, x, y } de cada sprite dibujado
local byImage = {}   -- imagen -> id, para poder leer painted
local sent = {}      -- nombre -> valor de cada uniforme del shader

local function nop() end

local ImageData = {}
ImageData.__index = ImageData
function ImageData:setPixel(x, y, r, g, b, a)
    self.p[y * self.w + x + 1] = { r, g, b, a }
end

love = setmetatable({}, { __index = function()
    return setmetatable({}, { __index = function() return nop end })
end })
love.filesystem = { getInfo = function() return nil end }
love.image = { newImageData = function(w, h)
    local p = {}
    for i = 1, w * h do p[i] = { 0, 0, 0, 0 } end
    return setmetatable({ w = w, h = h, p = p }, ImageData)
end }
love.graphics = setmetatable({
    newImage = function(data)
        return { data = data, setFilter = nop,
                 getWidth = function() return data.w end,
                 getHeight = function() return data.h end }
    end,
    -- Shader y lienzo de mentira. El shader apunta lo que se le manda: es
    -- todo lo que hace falta para medir el mar sin pintarlo.
    newShader = function() return { send = function(_, name, value)
        sent[name] = value
    end } end,
    newCanvas = function(w, h)
        return { setFilter = nop, release = nop,
                 getWidth = function() return w end,
                 getHeight = function() return h end }
    end,
    getCanvas = function() return nil end,
    draw = function(img, x, y, angle)
        -- REGLA 1. Si esto salta, alguien ha rotado un sprite.
        assert(angle == nil or angle == 0,
               "se paso rotacion a love.graphics.draw")
        painted[#painted + 1] = { id = byImage[img], x = x, y = y }
    end,
    rectangle = nop, setColor = nop, push = nop, pop = nop, scale = nop,
}, { __index = function() return nop end })

local Constants = require('src.constants')
local Util      = require('src.util')
local Art       = require('src.art')
local Sea       = require('src.sea')
local Surface   = require('src.surface')
local World     = require('src.world')
local Ship      = require('src.ship')

Art.loadAll()
for id, img in pairs(Art.images) do byImage[img] = id end

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

--== Escena ================================================================

-- Un barco navegando de verdad: rumbo, viento y unos segundos de singladura
-- para que haya estela. No se llama a World.step porque el viento es funcion
-- del tiempo y aqui hace falta clavarlo.
local function sail(windFrom, strength, heading, seconds)
    local s = World.new(4321)
    s.docked, s.bound = nil, nil
    s.x, s.y, s.time = 500, 500, 40
    s.heading, s.target = heading, heading
    s.trim, s.hull, s.morale = "full", 100, 100
    s.wind.from, s.wind.strength = windFrom, strength

    Sea.reset()
    local dt = 1 / 30
    for _ = 1, math.floor((seconds or 8) / dt) do
        local fx, fy = Util.headingToVector(s.heading)
        local d = Ship.speed(s) * dt
        s.x, s.y = s.x + fx * d, s.y + fy * d
        s.distance = s.distance + d
        s.time = s.time + dt
        Sea.update(s, dt)
    end
    return s
end

-- Que se ha pintado de una escena, contado por familia, y que se le ha mandado
-- al shader. El lienzo del mar y el cuadro sobre el que corre el shader no
-- llevan id: no son sprites del juego.
local function shot(s)
    painted, sent = {}, {}
    Sea.draw(s)
    local tally = setmetatable({}, { __index = function() return 0 end })
    for _, p in ipairs(painted) do
        if p.id then
            local family = p.id:gsub("%d+$", "")
            tally[family] = tally[family] + 1
            tally[p.id] = tally[p.id] + 1
        end
    end
    return tally
end

-- Direccion HACIA la que sopla, en el mundo.
local function windTo(s)
    return Util.headingToVector(Util.wrapAngle(s.wind.from + math.pi))
end

-- Los dos ejes del campo de espuma, leidos de los uniformes y puestos en
-- PANTALLA. El eje largo (`u`) corre a lo largo del viento y el corto (`v`) lo
-- cruza; lo que se mide de ellos es hacia donde apuntan y cuanto miden, que es
-- lo mismo que decir hacia donde se peina el mar y cuanto se estira.
local function axis(which)
    local i = (which == "u") and 1 or 2
    return sent.uBasisX[i], sent.uBasisY[i]
end

local function angleOf(which)
    local ax, ay = axis(which)
    return math.atan2(ay, ax)
end

local function lengthOf(which)
    local ax, ay = axis(which)
    return math.sqrt(ax * ax + ay * ay)
end

-- Diferencia entre dos angulos de EJE: un eje no tiene punta, asi que vive en
-- media vuelta -- 175 grados y 5 grados distan diez, no ciento setenta.
local function axisDiff(a, b)
    local d = math.abs(a - b) % math.pi
    return math.min(d, math.pi - d)
end

--== Regla 1 ===============================================================

print("\nnada se dibuja girado")
do
    local s = sail(0, 1.0, math.pi / 2)
    local ok = pcall(shot, s)
    check("una pantalla entera de mar sin una sola rotacion", ok)
    check("y se pinto algo, no es que no dibujara nada", #painted > 10,
          #painted .. " llamadas de dibujo")
    check("y el mar llego al shader", sent.uBasisX ~= nil and sent.uCut ~= nil)
end

--== De donde sopla ========================================================

print("\nel mar se peina con el viento")
do
    local s = sail(0, 1.0, math.pi / 2)
    shot(s)
    local wx, wy = windTo(s)
    local wind = Sea.screenAngle(s, wx, wy)
    check("el campo corre justo por donde sopla el viento",
          axisDiff(angleOf("u"), wind) < 0.02,
          string.format("%.0f vs %.0f grados",
                        math.deg(angleOf("u")), math.deg(wind)))
    check("y la veta de espuma lo cruza en angulo recto",
          math.abs(axisDiff(angleOf("u"), angleOf("v")) - math.pi / 2) < 0.02,
          string.format("%.0f grados entre ejes",
                        math.deg(axisDiff(angleOf("u"), angleOf("v")))))
    check("y es la veta la que se estira, no el desfile",
          lengthOf("v") < lengthOf("u"),
          string.format("%.3f a traves contra %.3f a lo largo",
                        lengthOf("v"), lengthOf("u")))

    -- Mismo viento, dos rumbos: el mar tiene que verse girado en pantalla
    -- exactamente lo que se ha virado.
    local a = angleOf("u")
    shot(sail(0, 1.0, math.pi / 2 + math.pi / 4))
    local b = angleOf("u")
    check("virar repeina el mar",
          math.abs(axisDiff(a, b) - math.pi / 4) < 0.05,
          string.format("%.0f grados de repeinado por 45 de virada",
                        math.deg(axisDiff(a, b))))

    -- Rumbo fijo, dos vientos: igual, porque lo que manda es el angulo entre
    -- los dos y no el rumbo suelto.
    shot(sail(math.pi / 4, 1.0, math.pi / 2))
    check("y rolar el viento tambien", axisDiff(a, angleOf("u")) > 0.3,
          string.format("%.0f grados", math.deg(axisDiff(a, angleOf("u")))))
end

--== Calma =================================================================

print("\ncon poco viento el mar se calma")
do
    shot(sail(0, 1.00, math.pi / 2))
    local fresco = { gain = sent.uGain, white = sent.uCut[3],
                     warp = sent.uWarp, veta = lengthOf("u") / lengthOf("v") }
    shot(sail(0, 0.55, math.pi / 2))
    local flojo  = { gain = sent.uGain, white = sent.uCut[3],
                     warp = sent.uWarp, veta = lengthOf("u") / lengthOf("v") }

    check("con viento flojo hay menos espuma", flojo.gain < fresco.gain * 0.5,
          string.format("%.2f contra %.2f", flojo.gain, fresco.gain))

    -- No es que salgan pocas rompientes: es que ninguna cuenta de espuma puede
    -- pasar de uno, asi que con el escalon por encima de uno no hay blanco.
    check("y en calma no PUEDE romper ni una ola",
          flojo.white > 1.0 and fresco.white < 1.0,
          string.format("escalon %.2f en calma, %.2f con viento",
                        flojo.white, fresco.white))

    check("y el mar de calma es de rizos, no de vetas largas",
          flojo.veta < fresco.veta * 0.6,
          string.format("%.1f de estiron en calma, %.1f con viento",
                        flojo.veta, fresco.veta))

    check("y las crestas apenas se comban", flojo.warp < fresco.warp * 0.6,
          string.format("%.3f contra %.3f", flojo.warp, fresco.warp))
end

--== El desfile ============================================================

print("\nel agua desfila aunque el barco no ande")
do
    -- El origen del campo se envuelve, asi que la resta se hace por el camino
    -- corto.
    local function gap(a, b)
        return (a - b + Surface.WRAP / 2) % Surface.WRAP - Surface.WRAP / 2
    end

    local s = sail(0, 1.0, math.pi / 2)
    s.docked = "x"                       -- amarrado: el barco no anda
    shot(s)
    local antes = sent.uOrigin[1]
    for _ = 1, 30 do Sea.update(s, 1 / 30) end
    shot(s)
    check("amarrado, el agua sigue corriendo a sotavento",
          gap(sent.uOrigin[1], antes) < -2,
          string.format("%.1f celdas en un segundo", gap(sent.uOrigin[1], antes)))

    -- Y andando, el campo tiene que correr ademas por debajo del barco: si no,
    -- el mar seria una tela pintada delante de la que el barco resbala.
    local quieto = sail(0, 0.55, math.pi / 2, 2)
    quieto.docked = "x"
    shot(quieto)
    local a0 = sent.uOrigin[2]
    for _ = 1, 60 do Sea.update(quieto, 1 / 30) end
    shot(quieto)
    local sinAndar = math.abs(gap(sent.uOrigin[2], a0))

    local anda = sail(0, 0.55, math.pi / 2 + 0.7, 2)
    shot(anda)
    local b0 = sent.uOrigin[2]
    for _ = 1, 120 do
        local fx, fy = Util.headingToVector(anda.heading)
        local d = Ship.speed(anda) * (1 / 30)
        anda.x, anda.y = anda.x + fx * d, anda.y + fy * d
        Sea.update(anda, 1 / 30)
    end
    shot(anda)
    -- Parado, el eje cruzado no se mueve NADA: por ahi no desfila el agua.
    -- Andando de traves si, y eso es lo que ata el campo al mundo.
    check("y andando de traves el campo corre ademas de lado",
          sinAndar == 0 and math.abs(gap(sent.uOrigin[2], b0)) > 0.5,
          string.format("%.2f celdas de lado contra %.2f parado",
                        math.abs(gap(sent.uOrigin[2], b0)), sinAndar))
end

--== Estela ================================================================

print("\nla estela dice lo que hace el barco")
do
    local s = sail(0, 1.0, math.pi / 2, 10)

    -- Los brazos de la V se miden por lo ANCHO que abre la estela: el punto
    -- mas apartado de la crujia. Todo en pixeles de arte.
    local function halfWidth(state)
        painted = {}
        Sea.draw(state)
        local cx = Constants.shipAnchor()
        local wide = 0
        for _, p in ipairs(painted) do
            if p.id == "sea.drop" or p.id == "sea.foam" then
                wide = math.max(wide, math.abs(p.x - cx))
            end
        end
        return wide
    end

    local ancho = halfWidth(s)
    check("la V se abre por detras del barco", ancho > 6, ancho .. " px")

    -- Y se abre con lo que el barco ANDA, no con el reloj: parado no se abre.
    -- (Se para el barco pero se sigue llamando a Sea.update, que es lo que
    -- pasaria de verdad al quedarse en el ojo del viento.)
    local antes = halfWidth(s)
    for _ = 1, 30 do Sea.update(s, 1 / 30) end
    check("y no sigue abriendose con el barco parado",
          halfWidth(s) <= antes, antes .. " -> " .. halfWidth(s))

    -- Amarrado no se siembra estela nueva, pero la vieja se deshace sola.
    s.docked = "x"
    for _ = 1, 30 * 20 do Sea.update(s, 1 / 30) end
    check("y amarrado acaba sin una brizna de espuma", halfWidth(s) == 0)
end

--== Bigote de proa ========================================================

print("\nel bigote de proa mide la velocidad")
do
    -- Un barco quieto no levanta agua; uno lanzado si, y con el bigote grande.
    local parado = sail(0, 1.0, 0)      -- proa al viento: 10 % de andar
    local lanzado = sail(0, 1.0, math.pi / 2)
    local a, b = shot(parado), shot(lanzado)
    local quieto = a["sea.bow1"] + a["sea.bow2"] + a["sea.bow3"]
    check("en el ojo del viento no hay bigote", quieto == 0, quieto .. " pintados")
    check("y a buen andar sale el grande", b["sea.bow3"] == 1)
end

--== Recuento ==============================================================

print("")
print(checks .. " comprobaciones, " .. failures .. " fallos")
os.exit(failures > 0 and 1 or 0)
