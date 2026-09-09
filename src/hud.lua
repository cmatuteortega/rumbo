-- HUD de la travesia: lo que se lee sin tocar nada.
--
-- Se dibuja en espacio virtual, encima del mar, y ocupa solo lo que el barco
-- no usa: un bloque en la esquina de arriba a estribor y la bitacora abajo a
-- la izquierda. El centro se deja libre a proposito, porque ahi esta el barco
-- y ahi es donde se toca.
--
-- Arriba hay dos sitios y tres preguntas:
--
--   en medio, al aire   hacia donde voy  el timon y las lecturas de navegacion
--   bloque de estribor  como estoy      casco, moral y bodega, barras de pie
--                       que llevo       debajo, los cuatro recursos en cifras
--
-- Las dos medidas comparten columna -- barras arriba, cifras debajo, con un
-- filete en medio -- y no un bloque en cada esquina. Las cifras estaban a
-- babor y de ahi se han bajado aqui: la esquina de arriba a la izquierda queda
-- libre, que es la que se come el notch y la que menos se mira, y todo lo que
-- se consulta cae del mismo lado sin cruzar la pantalla. El filete es lo que
-- evita que se lean como una sola lista de siete cosas.
--
-- SOLO ESE BLOQUE LLEVA FONDO, y mide lo que mide su contenido. Antes era una
-- franja maciza de lado a lado, y una franja se come el mar aunque este vacia:
-- la parte de en medio no tenia nada que tapar. Ahora el timon y sus lecturas
-- van al aire sobre el agua y a babor se ve mar hasta el borde, que es lo que
-- hace que la pantalla respire.
--
-- El bloque sangra por el borde de la pantalla en vez de flotar. Asi solo se
-- le ve un canto, el de dentro, y se lee como parte del marco y no como una
-- tarjeta suelta; ademas cubre el notch de ese lado sin un caso aparte.
--
-- Las barras van de pie porque tres tumbadas no caben una al lado de otra y
-- apiladas hay que leerlas de una en una, mientras que de pie se comparan por
-- altura sin leer nada.
--
-- Los ritmos que muestra salen de Ship.rates, los mismos que integra
-- World.step. Si el HUD dice "+3,6 pescado/min" es exactamente lo que se esta
-- acumulando; no hay dos formulas.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local UI        = require('src.ui')
local Ship      = require('src.ship')
local Compass   = require('src.compass')

local Hud = {}

local RESOURCES = {
    { key = "coin",   icon = "icon.coin" },
    { key = "fish",   icon = "icon.fish" },
    { key = "wood",   icon = "icon.wood" },
    { key = "ration", icon = "icon.ration" },
}

local PAD     = 12    -- aire entre el contenido y el canto del bloque
local COL_W   = 116   -- ancho del bloque, sin contar el margen seguro
local ROW_H   = 26    -- alto de una fila de recurso
local ICON    = 22    -- un icono de 11 px a escala 2
local BAR_W   = 16
local BAR_H   = 76
local BAR_GAP = 22
local LINE    = 18    -- alto de una linea de Fonts.tiny
local RULE    = 10    -- aire a cada lado del filete que parte el bloque
local RULE_H  = 2     -- grosor del filete: el mismo de los cantos del bloque

-- Alto de la mitad de arriba: las barras, sus iconos y el "6/40" de bodega.
-- Sale de las piezas y no de un numero suelto para que el filete y las cifras
-- bajen solos si crece una barra.
local BARS_H = BAR_H + 4 + ICON + 6 + LINE

-- Donde acaba la interfaz de arriba. No es el canto del bloque sino el pie
-- de las lecturas de navegacion, que cuelgan mas abajo que las barras: es lo
-- que tiene que mirar quien quiera escribir debajo sin pisar nada (voyage.lua
-- pone ahi el aviso de puerto). El bloque de estribor llega mas abajo, pero
-- eso no estorba a lo que va centrado.
function Hud.topHeight()
    local _, cy = Compass.center()
    return cy + Compass.RADIUS + 4 + 2 * LINE + 6
end

-- Y del contenido dentro del bloque.
local function columnTop()
    return Constants.SAFE_TOP + 10
end

-- Fondo del bloque. No es UI.panel a proposito: `uiPanel` es el color de lo
-- que se toca (botones, filas) y esto no se toca, asi que va en `uiBack`, mas
-- oscuro. El canto solo se pinta en los dos lados que se ven, porque los otros
-- dos se salen de la pantalla.
local function columnBack(x, w, bottom, innerEdge)
    UI.rect(x, 0, w, bottom, Palette.uiBack)
    UI.rect(x, bottom - 2, w, 2, Palette.uiLine)
    UI.rect(innerEdge, 0, 2, bottom, Palette.uiLine)
end

-- Dos trozos de texto con colores distintos, centrados como si fueran uno.
-- Los nudos son un dato y la ceñida es un semaforo: pintarlos del mismo color
-- perderia justo lo que hay que ver de un vistazo, y en dos lineas separadas
-- las lecturas bajarian hasta el barco.
local function centerPair(cx, y, a, aInk, b, bInk)
    local font = Fonts.tiny
    local head = a .. "  ·  "
    local x = cx - font:getWidth(head .. b) / 2
    UI.text(head, x, y, aInk, font)
    UI.text(b, x + font:getWidth(head), y, bInk, font)
end

function Hud.draw(state)
    local rates  = Ship.rates(state)
    local w      = Constants.GAME_WIDTH
    local cx, cy = Compass.center()
    local top    = columnTop()

    -- El bloque: alto de las dos mitades mas el filete. Se calcula antes de
    -- pintar el fondo porque el fondo tiene que llegar hasta la ultima cifra.
    local colW  = Constants.SAFE_RIGHT + COL_W
    local colX  = w - colW
    local left  = colX + PAD                     -- canto de dentro del contenido
    local right = w - Constants.SAFE_RIGHT - PAD
    local ruleY = top + BARS_H + RULE
    local resY  = ruleY + RULE_H + RULE
    local foot  = resY + #RESOURCES * ROW_H + 4

    columnBack(colX, colW, foot, colX)

    -- Arriba: como estoy. El umbral de 35 es el mismo en casco y moral y es
    -- lo unico que dice el color: por debajo, rojo.
    local barsX  = right - (3 * BAR_W + 2 * BAR_GAP)
    local gauges = {
        { icon = "icon.hull",   fill = state.hull / 100,
          color = state.hull > 35 and Palette.green or Palette.red },
        { icon = "icon.morale", fill = state.morale / 100,
          color = state.morale > 35 and Palette.gold or Palette.red },
        -- La bodega es la barra que decide cuanto rinde una ausencia, asi que
        -- va aqui y no escondida en su hoja. Roja cuando ya no cabe nada.
        { icon = "icon.hold",
          fill = (rates.capacity > 0) and (rates.cargo / rates.capacity) or 0,
          color = rates.hoveTo and Palette.red or Palette.woodLite },
    }
    for i, g in ipairs(gauges) do
        local x = barsX + (i - 1) * (BAR_W + BAR_GAP)
        UI.vbar(x, top, BAR_W, BAR_H, g.fill, g.color)
        UI.icon(g.icon, x + (BAR_W - ICON) / 2, top + BAR_H + 4, 2)
    end

    -- Lo que ninguna barra puede decir: cuanto cabe todavia en bodega.
    UI.textRight(string.format("%d/%d", math.floor(rates.cargo), rates.capacity),
                 right, top + BAR_H + 4 + ICON + 6, Palette.dim, Fonts.tiny)

    -- El filete va sangrado y no de canto a canto: de lado a lado partiria el
    -- bloque en dos y volverian a leerse como dos tarjetas, que es justo lo
    -- que se ha quitado.
    UI.rect(left, ruleY, right - left, RULE_H, Palette.uiLine)

    -- Abajo: que llevo. Van en cifras y no en barras porque lo que se hace con
    -- ellas es aritmetica ("me faltan 40 monedas para el astillero"), y una
    -- barra no se suma. La cifra va pegada al canto de dentro, alineada a la
    -- derecha como el "6/40" de arriba: asi las unidades caen todas en la
    -- misma columna y se comparan sin leerlas enteras.
    for i, res in ipairs(RESOURCES) do
        local y = resY + (i - 1) * ROW_H
        UI.icon(res.icon, left, y, 2)
        UI.textRight(Util.short(state.res[res.key]), right, y, Palette.text, Fonts.small)
    end

    -- La soldada devengada cuelga FUERA del bloque, sobre el mar. Es lo unico
    -- que se debe y no se ve en ningun otro sitio, y sacarla del fondo la hace
    -- leer como un aviso y no como una medida mas: cuando no se debe nada, ahi
    -- no hay nada, y el hueco vacio es parte del mensaje.
    if state.owed >= 1 then
        UI.textRight(string.format("debe %s", Util.short(state.owed)),
                     right, foot + 6, Palette.gold, Fonts.tiny)
    end

    -- En medio, al aire: hacia donde voy. El timon lo pinta voyage.lua justo
    -- despues; aqui van las dos lecturas que la rueda no lleva dentro.
    -- Amarrado no corre nada, y decirlo evita que parezca que el juego se ha
    -- colgado.
    local navY = cy + Compass.RADIUS + 4
    if state.docked then
        UI.textCenter("amarrado", cx, navY, Palette.dim, Fonts.tiny)
        UI.textCenter("en puerto no corre la singladura", cx, navY + LINE,
                      Palette.dim, Fonts.tiny)
        return
    end

    local knots = string.format("%.1f nudos", rates.speed / 2)
    local point = rates.hoveTo and "a la capa"
                  or string.format("vela %d%%", math.floor(rates.pointing * 100))
    local wind  = string.format("viento %s %s", Util.headingName(state.wind.from),
                                state.wind.strength > 0.85 and "fresco" or "flojo")
    centerPair(cx, navY, knots, Palette.text, point,
               (not rates.hoveTo and rates.pointing > 0.6) and Palette.foam or Palette.red)
    UI.textCenter(wind, cx, navY + LINE, Palette.dim, Fonts.tiny)
end

-- Bitacora: las ultimas tres cosas que han pasado. Va abajo a la izquierda,
-- justo encima de la columna de botones, y se lee de reojo. Estaba mas alta
-- cuando el timon ocupaba la esquina de estribor; ahora que el timon esta
-- arriba puede bajar, y con ella baja el barco.
function Hud.logTop()
    return Constants.GAME_HEIGHT - Constants.SAFE_BOTTOM - 228
end

function Hud.drawLog(state)
    local y = Hud.logTop()
    for i = 1, math.min(3, #state.log) do
        local entry = state.log[i]
        local color = (i == 1) and Palette.text or Palette.dim
        UI.text(entry.text, Constants.SAFE_LEFT + PAD, y, color, Fonts.tiny)
        y = y + LINE
    end
end

return Hud
