-- La rueda del timon: gobernar a mano.
--
-- El timon de la cabecera (`src/compass.lua`) es una rosa: se toca un punto y
-- se pide "la proa ahi". Sirve para elegir rumbo, pero no para *gobernar*: es
-- pequeno, esta arriba y un rumbo se pide de un toque, sin pulso. Esta rueda
-- es lo contrario -- grande, abajo, y se mueve arrastrando -- y sale al tocar
-- el puesto del timon en cubierta, que es donde se busca cuando lo que se
-- quiere es corregir un poco.
--
-- SOLO SE VE UN CUARTO, con el centro clavado en la esquina inferior de
-- estribor. Es lo que permite que sea enorme sin comerse el mar: una rueda
-- entera de este radio taparia media pantalla, y de un timon de verdad, con
-- el timonel detras, tampoco se ve mas que el cuarto que asoma. La esquina es
-- la de estribor porque el movil se sujeta con la derecha: ahi la rueda cae
-- bajo el pulgar sin mover la mano, que es justo lo que la rosa perdio al
-- subirse a la cabecera (ver `Compass.MARGIN`) y lo que dejo el bajo libre.
--
-- La desmultiplicacion no es un numero elegido a dedo: los 90 grados de rueda
-- que se ven son TODA la rosa, asi que un radian de rumbo son SWING/pi
-- radianes de rueda. De ahi salen las dos cosas que hacen que se lea:
--
--   * la cabilla maestra, la dorada, nunca se sale del cuarto visible, asi
--     que la rueda no puede aparentar estar a la via estando a la banda. Las
--     demas cabillas son iguales entre si y equidistantes, o sea que una
--     rueda girada justo el paso entre dos se dibuja EXACTAMENTE igual que
--     una sin girar; acotar el giro al cuarto es lo que evita esa mentira.
--   * media rosa (180 grados) son 173 pixeles de arco en la llanta. Un pixel
--     de dedo, un grado de rumbo: basta para corregir sin tener que apuntar.
--
-- La rueda no guarda su angulo en ninguna parte: es `angleDiff(rumbo, rumbo
-- pedido)` desmultiplicado, o sea LO QUE FALTA POR CAER. Por eso se centra
-- sola segun el barco va entrando al rumbo nuevo, igual que la marca dorada
-- de la rosa sube al pico; a la via con la cabilla maestra bajo el indice
-- blanco es la maniobra terminada. Y por eso arrastrar recalcula el rumbo
-- pedido desde el rumbo ACTUAL en cada cuadro: si se ordenara un incremento
-- sobre el rumbo pedido, el barco cayendo giraria la rueda por debajo del
-- dedo y pareceria que forcejea.
--
-- ENTRA RODANDO por su propia diagonal, desde fuera de la esquina, y sale por
-- donde vino. El giro no es un adorno pegado al deslizamiento: es el que le
-- toca por rodar esa distancia (`SLIDE / RADIUS` radianes), asi que la rueda
-- parece venir rodando hasta su sitio en vez de girar porque si. Antihorario
-- al entrar: es el sentido de una rueda que avanza hacia la izquierda, y la
-- rueda entra hacia babor.
--
-- La curva es una sola —un cubo que frena al final— y de ella salen las dos
-- sensaciones sin escribir ninguna: recorrida de 0 a 1 entra rapido y se
-- asienta despacio; recorrida de 1 a 0 arranca despacio y se escapa. Una sola
-- curva es ademas lo que deja interrumpir la maniobra a medias —sacarla
-- mientras se guarda— sin un salto, porque no hay una segunda curva a la que
-- cambiarse.
--
-- La animacion es SOLO dibujo. El gobierno mide siempre desde el centro
-- puesto, no desde el que entra: midiendo desde el que entra, el propio
-- deslizamiento cambiaria el angulo del dedo sin que el dedo se moviera y la
-- rueda ordenaria rumbo ella sola. Y lo que se ve mientras entra cae siempre
-- dentro de lo que se toca, porque entrando la rueda esta mas cerca de la
-- esquina que puesta, asi que se puede agarrar desde el primer cuadro.
--
-- Se dibuja con rectangulos de 1x1 dentro de la escala de arte, que es la
-- salida legal a la regla de "nada girado" (ver src/sea.lua): la madera gira,
-- pero no hay sprite que rotar, y el pixel mide lo mismo que el del casco.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local UI        = require('src.ui')

local Helm = {}

-- Radio en pixeles de ARTE, no virtuales: la rueda es del mismo grano que el
-- barco, y si el lienzo se estrecha y ART baja, la rueda encoge con el barco
-- en vez de descuadrarse. Con ART=5 son 220 px virtuales, mas 30 de cabilla:
-- eso llega a la altura de la columna de botones de estribor, y por eso la
-- travesia no la dibuja mientras la rueda esta fuera.
Helm.RADIUS = 44

-- Tope de giro a cada banda. Es un cuarto porque la cabilla maestra sale de
-- la bisectriz del cuarto visible: sumarle o restarle SWING la deja justo en
-- un borde, o sea toda la banda es exactamente lo que se ve.
Helm.SWING = math.pi / 4

-- A la via. Con la rueda en la esquina de estribor el cuarto que se ve es el
-- de arriba a babor, asi que su bisectriz apunta arriba y a la izquierda.
-- Todo lo que se dibuja se cuenta desde aqui.
local AMIDSHIPS = -math.pi / 4

-- Doce cabillas y no las ocho de una rueda de verdad: de un cuarto solo se
-- ven las que caen dentro de 90 grados, y con ocho (una cada 45) eso es UNA y
-- dos pegadas a los bordes. Con doce se ven tres o cuatro, que es lo que hace
-- que el giro se lea como madera girando y no como una aguja moviendose.
local SPOKES = 12
local RIM    = 6              -- grosor de la llanta
local GRIP   = 6              -- lo que asoma la cabilla por fuera de la llanta
local HUB    = 5              -- radio de la nuez

-- Radianes de rueda por radian de rumbo. Ver el parrafo de arriba: sale de
-- que el cuarto visible cubre la rosa entera, no de probar numeros.
local GEAR = Helm.SWING / math.pi

-- Lo que se aparta el centro para quedarse del todo fuera de la pantalla. No
-- es el alcance de la rueda sino un poco mas: tiene que caber tambien la
-- lectura, que va por delante de la llanta y asomaria sola por la esquina.
local SLIDE = Helm.RADIUS + GRIP + 20

-- Meterla cuesta mas que sacarla. Guardar algo tiene que sentirse resuelto, y
-- una salida a la misma velocidad que la entrada se lee como que cuesta.
local ENTER, EXIT = 0.24, 0.16

local grabbed = nil           -- angulo del dedo en el ultimo cuadro de arrastre
local anim = 0                -- 0 = fuera de la pantalla, 1 = puesta en su sitio

--==========================================================================
-- Entrada y salida
--==========================================================================

-- La travesia es la que sabe si la rueda esta pedida; aqui solo se recorre el
-- camino hacia ese estado. Asi no hay dos sitios diciendo si esta fuera.
function Helm.update(dt, out)
    local step = dt / (out and ENTER or EXIT)
    anim = Util.clamp(anim + (out and step or -step), 0, 1)
end

-- Al entrar en la travesia la rueda esta guardada y quieta: volver de la
-- carta de marear no puede sacarla sola.
function Helm.reset()
    anim = 0
    grabbed = nil
end

-- Si hay algo que pintar. No es lo mismo que estar pedida: mientras sale ya
-- no responde, pero todavia se ve.
function Helm.showing()
    return anim > 0
end

-- Cuanto esta puesta, con la curva. El cubo frena al llegar; recorrido al
-- reves, arranca despacio y acelera al irse.
local function settled()
    local u = 1 - anim
    return 1 - u * u * u
end

--==========================================================================
-- Geometria
--==========================================================================

-- Centro en pixeles de arte: la esquina inferior de estribor del area segura.
function Helm.center()
    return math.floor((Constants.GAME_WIDTH - Constants.SAFE_RIGHT) / Constants.ART),
           math.floor((Constants.GAME_HEIGHT - Constants.SAFE_BOTTOM) / Constants.ART)
end

-- El mismo centro en coordenadas virtuales, que es donde llegan los toques.
function Helm.centerVirtual()
    local cx, cy = Helm.center()
    return cx * Constants.ART, cy * Constants.ART
end

-- Hasta donde llega la rueda desde el centro, en virtual: la llanta mas lo
-- que asoma la cabilla. Es tambien el radio tocable, porque la cabilla que
-- sobresale es justo por donde se agarra una rueda.
local function reach()
    return (Helm.RADIUS + GRIP) * Constants.ART
end

function Helm.contains(x, y)
    local cx, cy = Helm.centerVirtual()
    local dx, dy = x - cx, y - cy
    if dx > 0 or dy > 0 then return false end     -- fuera del cuarto visible
    local r = reach()
    return dx * dx + dy * dy <= r * r
end

-- Angulo del dedo alrededor del centro, en [-pi/2, 0] por estar en el cuarto.
-- La nuez es zona muerta: ahi el angulo salta con un pixel de temblor.
local function fingerAngle(x, y)
    local cx, cy = Helm.centerVirtual()
    local dx, dy = x - cx, y - cy
    local dead = (HUB + 4) * Constants.ART
    if dx * dx + dy * dy < dead * dead then return nil end
    return math.atan2(dx, -dy)
end

-- Angulo de la rueda: lo que falta por caer, desmultiplicado. No hace falta
-- acotarlo aqui -- angleDiff no pasa de pi y pi * GEAR es justo SWING -- y esa
-- igualdad es precisamente lo que hace que el cuarto visible sea la rosa
-- entera. El tope solo se aplica al arrastrar.
local function wheelAngle(state)
    return Util.angleDiff(state.heading, state.target) * GEAR
end

--==========================================================================
-- Gobierno
--==========================================================================

function Helm.grab(x, y)
    grabbed = fingerAngle(x, y)
end

function Helm.drop()
    grabbed = nil
end

-- Gira la rueda lo que ha corrido el dedo desde el cuadro anterior y devuelve
-- el rumbo que eso ordena, o nil si el dedo esta en la nuez. Es relativo a
-- proposito: la rueda se agarra, no se apunta, asi que no salta a donde cae
-- el dedo sino que gira con el.
function Helm.steer(state, x, y)
    local a = fingerAngle(x, y)
    if not a then return nil end
    if not grabbed then grabbed = a; return nil end

    local w = Util.clamp(wheelAngle(state) + Util.angleDiff(grabbed, a),
                         -Helm.SWING, Helm.SWING)
    grabbed = a
    return Util.wrapAngle(state.heading + w / GEAR)
end

--==========================================================================
-- Dibujo
--==========================================================================
--
-- Cada pieza se pinta DOS veces: primero engordada un pixel en `Palette.ink`
-- y luego a su tamano en su color. Eso deja el contorno negro de 1px con el
-- que estan dibujados los sprites de assets/, y lo deja tambien donde una
-- cabilla cruza la llanta, que es lo que separa las dos maderas en vez de
-- fundirlas en una mancha. Sale mas barato que rasterizar la silueta entera
-- para buscarle el borde, y de paso el corte del cuarto no se lleva
-- contorno: la rueda no esta recortada, es que sigue fuera de la pantalla.

-- Corona (o disco, con ri = 0) recortada al cuarto visible, fila a fila. Se
-- pinta por filas y no punto a punto porque una llanta de este radio son
-- cientos de pixeles: una tira por fila es un rectangulo, y son 45.
local function band(cx, cy, ro, ri, color)
    love.graphics.setColor(color)
    for dy = 0, math.floor(ro) do
        local outer = math.floor(math.sqrt(ro * ro - dy * dy))
        local inner = 0
        if dy < ri then inner = math.ceil(math.sqrt(ri * ri - dy * dy)) end
        if outer >= inner then
            love.graphics.rectangle("fill", cx - outer, cy - dy, outer - inner + 1, 1)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Un cuadrado de `size` recortado al cuarto: siempre un rectangulo, tambien
-- pegado al borde, para no bajar a pintar pixel a pixel las cabillas.
local function stamp(cx, cy, x, y, size)
    x, y = math.floor(x - size / 2), math.floor(y - size / 2)
    local x1 = math.min(x + size - 1, cx)
    local y1 = math.min(y + size - 1, cy)
    if x1 < x or y1 < y then return end
    love.graphics.rectangle("fill", x, y, x1 - x + 1, y1 - y + 1)
end

-- Cabilla: un radio de la rueda. Se avanza de pixel en pixel con un sello,
-- que a este radio no deja huecos.
local function spoke(cx, cy, angle, from, to, color, size)
    -- Fuera del cuarto no se ve nada de ella, y son dos de cada tres.
    if math.abs(Util.angleDiff(AMIDSHIPS, angle)) > Helm.SWING + 0.08 then return end

    local sn, cs = math.sin(angle), math.cos(angle)
    love.graphics.setColor(color)
    for r = from, to do
        stamp(cx, cy, cx + sn * r, cy - cs * r, size)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Helm.draw(state)
    local R = Helm.RADIUS
    local put = settled()
    local slide = (1 - put) * SLIDE

    -- El centro se aparta por la diagonal, hacia fuera de la esquina, y en
    -- pixeles ENTEROS de arte: el deslizamiento avanza de pixel en pixel como
    -- todo lo demas del mundo, no a medio pixel.
    local bx, by = Helm.center()
    local function apart(d)
        return math.floor(bx - math.sin(AMIDSHIPS) * d + 0.5),
               math.floor(by + math.cos(AMIDSHIPS) * d + 0.5)
    end
    local cx, cy = apart(slide)

    -- Lo que falta por caer, mas lo que le queda por rodar para llegar. El
    -- signo es POSITIVO porque los angulos crecen a estribor (horario) y la
    -- rueda entra hacia babor: viene de un angulo mayor y baja al suyo, que
    -- es girar antihorario, que es como gira lo que rueda hacia la izquierda.
    local w = wheelAngle(state) + (1 - put) * SLIDE / R

    love.graphics.push()
    love.graphics.scale(Constants.ART, Constants.ART)

    -- Llanta. Va hueca: por dentro se sigue viendo el mar, que es lo que la
    -- hace parecer madera colgada delante y no un panel de interfaz.
    band(cx, cy, R + 1, R - RIM - 1, Palette.ink)
    band(cx, cy, R, R - RIM, Palette.wood)
    -- El canto de fuera va CLARO y el de dentro oscuro. El contorno negro ya
    -- hace de borde oscuro -- que es el papel que tiene en el casco
    -- (`gen.shipHull`) --, asi que repetirlo con woodDark por fuera solo lo
    -- engordaba; con la luz por fuera y la sombra por dentro la llanta se lee
    -- redonda. Y nada de veta: la llanta es lo unico de la rueda que no gira,
    -- y solo se sale con la suya por ser lisa. Un grano encima delataria que
    -- se queda quieta mientras las cabillas dan vueltas.
    band(cx, cy, R, R - 1.4, Palette.woodLite)           -- canto exterior
    band(cx, cy, R - RIM + 1, R - RIM, Palette.woodDark) -- canto interior

    -- Cabillas: TODOS los contornos antes que TODAS las maderas. Pintando
    -- cada cabilla entera de una vez, la siguiente le comia un pixel con su
    -- propio contorno alli donde se juntan, cerca de la nuez.
    local angles = {}
    for i = 1, SPOKES do
        angles[i] = AMIDSHIPS + w + (i - 1) * Util.TAU / SPOKES
        spoke(cx, cy, angles[i], HUB - 2, R + GRIP + 1, Palette.ink, 4)
    end

    -- La maestra va dorada, que es el color con el que el juego dice "esto es
    -- lo que has pedido" (la aguja de la rosa es del mismo), y del mismo
    -- grosor que las demas: engordarla la volvia un borron al caer en
    -- diagonal, y el color ya la separa de sobra.
    for i = 1, SPOKES do
        spoke(cx, cy, angles[i], HUB - 1, R + GRIP,
              (i == 1) and Palette.gold or Palette.woodLite, 2)
    end

    -- Nuez, que tapa el nudo de cabillas del centro.
    band(cx, cy, HUB + 1, 0, Palette.ink)
    band(cx, cy, HUB, 0, Palette.woodDark)
    band(cx, cy, 2, 0, Palette.woodLite)

    -- Indice fijo: la marca de a la via. Nace en el canto interior de la
    -- llanta y mira adentro, porque suelto en medio del hueco se leia como
    -- una mota de espuma. Se pinta ENCIMA de las cabillas: tapado por una,
    -- "alineado" y "no esta" se leen igual.
    spoke(cx, cy, AMIDSHIPS, R - RIM - 4, R - RIM + 1, Palette.ink, 4)
    spoke(cx, cy, AMIDSHIPS, R - RIM - 3, R - RIM, Palette.white, 2)

    love.graphics.pop()

    -- Lectura del rumbo pedido. Va en espacio virtual porque es texto: dentro
    -- de la escala de arte la fuente saldria a bloques de cinco pixeles.
    --
    -- Y va FUERA de la rueda, en la prolongacion del indice: dentro del hueco
    -- quedaba debajo de la cabilla maestra, que pasa por la bisectriz justo
    -- cuando la rueda esta a la via, o sea justo en el estado que mas se mira.
    -- Aqui no la cruza nada nunca, y sigue leyendose como el numero de la
    -- marca de a la via porque esta en su misma diagonal.
    -- Entra y sale con la rueda, pero deslizando MAS que ella. La lectura va
    -- por delante de la llanta en la diagonal -- esta mas lejos del centro
    -- que la rueda entera --, asi que con el mismo deslizamiento asomaria por
    -- la esquina antes que la madera: media palabra recortada por el borde
    -- sin nada todavia que la explique.
    --
    -- Desliza en proporcion a lo lejos que esta, y la referencia es el canto
    -- INTERIOR de la llanta: asi el numero cruza el borde cuando ya ha
    -- entrado un arco de madera y no la punta de una cabilla. Referenciarlo
    -- al alcance de la rueda no bastaba -- los dos cruzaban a la vez, pero el
    -- texto cruza legible y la rueda cruza como dos pixeles.
    local d = R + GRIP + 8
    local lx, ly = apart(slide * d / (R - RIM))
    local label = string.format("%s %03d", Util.headingName(state.target),
                                Util.headingDegrees(state.target))
    UI.textCenter(label,
                  (lx + d * math.sin(AMIDSHIPS)) * Constants.ART,
                  (ly - d * math.cos(AMIDSHIPS)) * Constants.ART
                      - Fonts.tiny:getHeight() / 2,
                  Palette.gold, Fonts.tiny)
end

return Helm
