-- Prueba del mar, sin ventana.
--
--     lua5.1 tests/test_sea.lua
--
-- Va aparte de tests/test_sim.lua por lo mismo que la de la driza: la
-- simulacion no puede requerir love y se prueba tal cual, pero el mar es
-- DIBUJO, asi que hace falta un love de mentira que apunte lo que se pinta.
--
-- Y esta aqui porque el mar orientado mete tres cosas que no se ven mirando la
-- pantalla un rato:
--
--   * la REGLA 1. Con doce sprites por familia es facil creerse que ya que
--     estamos se puede pasar un angulo a love.graphics.draw y ahorrarse once.
--     El love de mentira PETA si alguien lo intenta, en el mar y en el barco.
--   * que las crestas apunten a donde tienen que apuntar. Se peinan CONTRA el
--     viento y las rachas corren A FAVOR, asi que las dos familias tienen que
--     salir siempre a noventa grados una de otra, y las dos tienen que girar
--     cuando gira el barco -- que es lo unico que hace que el mar se vea
--     distinto en cada rumbo. Mirando la pantalla se ve que hay diagonales;
--     que sean LAS diagonales, no.
--   * que con poco viento el mar este de verdad mas quieto. Es una diferencia
--     de cuentas -- menos trazos, ninguno blanco -- y a ojo, en dos capturas
--     separadas por diez minutos de juego, es indistinguible de la suerte.
--   * a que VELOCIDAD desfila. Mirando la pantalla el mar corriendo se lee
--     como "hay viento", y solo comparandolo con lo que anda el barco se ve
--     que lo que en realidad dice es que el barco va marcha atras. Es un
--     numero contra Ship.BASE_SPEED, no una impresion.
--
-- La estela se mide igual: la uve solo dice la verdad si se abre con lo que el
-- barco ANDA, y eso son dos capturas y una resta.

package.path = "./?.lua;" .. package.path

-- love de mentira: apuntar lo que se pinta y tragarse todo lo demas.
local painted = {}   -- { id, x, y } de cada sprite dibujado
local byImage = {}   -- imagen -> id, para poder leer painted

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

-- Que se ha pintado de una escena, contado por familia.
local function shot(s)
    painted = {}
    Sea.draw(s)
    local tally = setmetatable({}, { __index = function() return 0 end })
    for _, p in ipairs(painted) do
        local family = p.id:gsub("%d+$", "")
        tally[family] = tally[family] + 1
        tally[p.id] = tally[p.id] + 1
    end
    return tally
end

-- El angulo de una familia orientada, leido del sprite que se ha usado.
-- Devuelve nil si no se pinto ninguno.
local function angleOf(tally, family)
    local best, bestN = nil, 0
    for d = 1, Art.SEA_DIRS do
        local n = tally[family .. d]
        if n > bestN then best, bestN = d, n end
    end
    return best and (best - 1) * math.pi / Art.SEA_DIRS
end

-- Diferencia entre dos angulos de TRAZO: viven en media vuelta, asi que 175
-- grados y 5 grados distan diez, no ciento setenta.
local function strokeDiff(a, b)
    local d = math.abs(a - b) % math.pi
    return math.min(d, math.pi - d)
end

--== Regla 1 ===============================================================

print("\nnada se dibuja girado")
do
    local s = sail(0, 1.0, math.pi / 2)
    local ok = pcall(shot, s)
    check("una pantalla entera de mar sin una sola rotacion", ok)
    check("y se pinto algo, no es que no dibujara nada", #painted > 50,
          #painted .. " sprites")
end

--== De donde sopla ========================================================

print("\nel mar se peina con el viento")
do
    -- Mismo viento, dos rumbos: el mar tiene que verse girado en pantalla
    -- exactamente lo que se ha virado.
    local a = shot(sail(0, 1.0, math.pi / 2))
    local b = shot(sail(0, 1.0, math.pi / 2 + math.pi / 4))
    local wa, wb = angleOf(a, "sea.wave"), angleOf(b, "sea.wave")
    check("virar repeina el mar", wa and wb and strokeDiff(wa, wb) > 0.5,
          wa and wb and string.format("%.0f vs %.0f grados",
                                      math.deg(wa), math.deg(wb)) or "sin olas")

    -- Rumbo fijo, dos vientos: igual, porque lo que manda es el angulo entre
    -- los dos y no el rumbo suelto.
    local c = shot(sail(math.pi / 4, 1.0, math.pi / 2))
    local wc = angleOf(c, "sea.wave")
    check("y rolar el viento tambien", wa and wc and strokeDiff(wa, wc) > 0.3,
          wa and wc and string.format("%.0f vs %.0f grados",
                                      math.deg(wa), math.deg(wc)) or "sin olas")

    -- La racha corre a favor del viento y la cresta se peina contra el: entre
    -- las dos familias hay siempre un angulo recto, en cualquier rumbo.
    local ga = angleOf(a, "sea.gust")
    check("la racha cruza a la cresta en angulo recto",
          wa and ga and math.abs(strokeDiff(wa, ga) - math.pi / 2) < 0.30,
          wa and ga and string.format("%.0f grados entre ellas",
                                      math.deg(strokeDiff(wa, ga))) or "sin rachas")
end

--== Calma =================================================================

print("\ncon poco viento el mar se calma")
do
    local fresco = shot(sail(0, 1.00, math.pi / 2))
    local flojo  = shot(sail(0, 0.55, math.pi / 2))

    check("con viento flojo hay menos trazos",
          flojo["sea.ripple"] + flojo["sea.wave"] + flojo["sea.swell"]
        < fresco["sea.ripple"] + fresco["sea.wave"] + fresco["sea.swell"])

    check("y en calma no rompe ni una ola",
          flojo["sea.swell"] == 0 and fresco["sea.swell"] > 0,
          flojo["sea.swell"] .. " rompientes en calma, "
          .. fresco["sea.swell"] .. " con viento")

    check("y no queda una racha en la pantalla",
          flojo["sea.gust"] == 0 and fresco["sea.gust"] > 0,
          flojo["sea.gust"] .. " rachas en calma, "
          .. fresco["sea.gust"] .. " con viento")
end

--== Desfile ===============================================================

print("\nel mar no corre mas que el barco")
do
    -- La escala del juego la pone el barco: Ship.BASE_SPEED es lo que anda uno
    -- perfecto. Un campo de agua que cruce la pantalla mas deprisa que eso no
    -- se lee como viento, se lee como que el barco cia a toda maquina -- que
    -- es exactamente lo que hacia el mar de antes, a treinta y uno de desfile
    -- contra los siete del barco.
    local ola = Sea.WAVE_DRIFT[1] + Sea.WAVE_DRIFT[2]
    check("la ola no adelanta al barco", ola <= Ship.BASE_SPEED,
          string.format("%.1f px/s de mar contra %.1f del barco",
                        ola, Ship.BASE_SPEED))

    -- La racha si puede correr mas que la ola -- es el viento tocando el agua,
    -- no el agua moviendose -- pero no el triple.
    local racha = Sea.GUST_DRIFT[1] + Sea.GUST_DRIFT[2]
    check("y la racha corre mas que la ola, pero no se desboca",
          racha > ola and racha <= 2 * Ship.BASE_SPEED,
          string.format("%.1f px/s", racha))

    -- Y el suelo, que ahora importa mas que el techo: el agua esta a siete
    -- decimas de pixel por segundo, cerca de pararse del todo. Por debajo de
    -- media (un pixel cada dos segundos) deja de haber animacion a este grano
    -- y el mar se congela, que es la leccion del corcho del redal -- una
    -- pantalla identica cuadro tras cuadro se lee como colgada. Que el barco la
    -- cruce no salva: amarrado en puerto el barco no cruza nada.
    check("pero el agua no se congela", ola >= 0.5 and racha >= 0.5,
          string.format("%.2f la ola, %.2f la racha", ola, racha))
    check("y en calma tampoco", Sea.WAVE_DRIFT[1] > 0 and Sea.GUST_DRIFT[1] > 0)
end

--== El desfile no acelera =================================================

print("\nel desfile no acelera con las horas de partida")
do
    -- Este es el fallo que costo tres arreglos de tuning encontrar, y no se ve
    -- mirando la pantalla: se ve restando dos medidas separadas por ocho horas
    -- de partida. El desfile salia de state.time por el ritmo del momento
    -- (drift = t * v(t)), y como el viento rola y refresca sin parar, lo que se
    -- movia el campo era v + t*dv/dt -- un sumando que crece con las horas sin
    -- techo. A las ocho horas las olas iban a 39,7 px/s y las rachas a 146.
    --
    -- Se nota AMARRADO, que es donde el barco no cruza el campo y el desfile se
    -- queda solo en pantalla, asi que asi se mide.
    local function anda(horas)
        local s = World.new(4321)
        s.docked, s.bound = "x", nil
        s.x, s.y = 500, 500
        s.time = horas * 3600
        s.trim, s.hull, s.morale = "full", 100, 100
        World.updateWind(s)

        Sea.reset()
        local dt = 1 / 30
        local function correr(segundos)
            for _ = 1, math.floor(segundos / dt) do
                s.time = s.time + dt
                World.updateWind(s)
                Sea.update(s, dt)
            end
        end

        -- Un segundo de rodaje antes de medir: recien reseteado el campo esta
        -- en cero y el primer cuadro da un salto que no es la velocidad de
        -- crucero. Lo que se quiere saber es a que va el mar YA puesto.
        correr(1)
        local ax, ay, bx, by, f0 = Sea.drift()
        correr(1)
        local cx, cy, dx, dy, f1 = Sea.drift()
        return math.sqrt((cx - ax) ^ 2 + (cy - ay) ^ 2),
               math.sqrt((dx - bx) ^ 2 + (dy - by) ^ 2),
               math.abs(f1 - f0)
    end

    local techoOla   = Sea.WAVE_DRIFT[1] + Sea.WAVE_DRIFT[2]
    local techoRacha = Sea.GUST_DRIFT[1] + Sea.GUST_DRIFT[2]
    local techoVaiven = Sea.SURGE_RATE[1] + Sea.SURGE_RATE[2]

    for _, horas in ipairs({ 0, 1, 8, 72 }) do
        local ola, racha, vaiven = anda(horas)
        check(string.format("a las %d h el campo sigue a su ritmo", horas),
              ola <= techoOla + 0.01 and racha <= techoRacha + 0.01
                                     and vaiven <= techoVaiven + 0.01,
              string.format("%.2f / %.2f px/s y %.3f rad/s, techo %.2f / %.2f y %.2f",
                            ola, racha, vaiven, techoOla, techoRacha, techoVaiven))
    end
end

--== Estela ================================================================

print("\nla estela dice lo que hace el barco")
do
    local s = sail(0, 1.0, math.pi / 2, 10)

    -- La estela es el bigote de proa estirado por popa: una escalera de arcos
    -- (sea.wake1..5) que se elige por lo lejos que ha quedado cada uno. Asi
    -- que lo que abre la uve es QUE ESCALON se ha alcanzado, y eso es lo que
    -- se lee del dibujo. La estela se pinta fuera de Sea.draw, encima del
    -- barco, asi que hay que llamarla aparte -- como hace voyage.lua.
    local function widest(state)
        painted = {}
        Sea.draw(state)
        Sea.drawWake(state)
        local top = 0
        for _, p in ipairs(painted) do
            local step = p.id and p.id:match("^sea%\.wake(%d)$")
            if step then top = math.max(top, tonumber(step)) end
        end
        return top
    end

    -- Y que el arco de verdad se abre a lo ancho: el ultimo escalon tiene que
    -- asomar por fuera del casco, o la estela se queda escondida debajo.
    local paso = widest(s)
    check("la estela llega a los escalones anchos", paso >= 3,
          "escalon " .. paso)
    local ancho = Art.size("sea.wake" .. math.max(paso, 1))
    check("y el arco es mas ancho que el espejo de popa", ancho > 26,
          ancho .. " px de arco")

    -- Y dice lo que se corre. El angulo de la uve no cambia -- el escalon se
    -- elige por pixeles quedados atras, no por velocidad --, lo que cambia es
    -- lo LARGA que llega a ser: en el ojo del viento se anda al diez por
    -- ciento y por popa no puede quedar mas que un hervor contra el codaste.
    local pesca = widest(sail(0, 1.0, 0, 10))
    check("y en el ojo del viento se queda pegada al codaste", pesca < paso,
          "escalon " .. pesca .. " parado contra " .. paso .. " lanzado")

    -- Se abre con lo que el barco ANDA, no con el reloj: parado no se abre.
    -- (Se para el barco pero se sigue llamando a Sea.update, que es lo que
    -- pasaria de verdad al quedarse en el ojo del viento.)
    local antes = widest(s)
    for _ = 1, 30 do Sea.update(s, 1 / 30) end
    check("y no sigue abriendose con el barco parado",
          widest(s) <= antes, antes .. " -> " .. widest(s))

    -- Amarrado no se siembra estela nueva, pero la vieja se deshace sola.
    s.docked = "x"
    for _ = 1, 30 * 20 do Sea.update(s, 1 / 30) end
    check("y amarrado acaba sin una brizna de espuma", widest(s) == 0)
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
