-- Resolucion, escala y margenes seguros.
--
-- Hay tres espacios de coordenadas y conviene tenerlos claros:
--
--   ventana  -> pixeles reales del dispositivo. Solo main.lua los toca.
--   virtual  -> lienzo de 540 de ancho (GAME_WIDTH/GAME_HEIGHT). Todo el UI
--               (texto, botones, paneles) vive aqui.
--   arte     -> virtual dividido por ART (5). El mar, el barco y cualquier
--               sprite se dibujan aqui, en enteros, y se suben a virtual con
--               un scale() entero. Es lo que mantiene el pixel crujiente.
--
-- El lienzo NO es 540x960 fijo: la altura se estira para cubrir la pantalla
-- del movil (un 20:9 da 540x1215). Nada se posiciona contra un 960 escrito a
-- mano; se lee GAME_HEIGHT / ART_H.

local Constants = {}

Constants.BASE_WIDTH  = 540
Constants.BASE_HEIGHT = 960

Constants.GAME_WIDTH  = 540
Constants.GAME_HEIGHT = 960

-- Escala de UI respecto a la resolucion base (1.0 en un movil 9:16).
Constants.SCALE = 1

-- Un pixel de arte son ART pixeles virtuales. Entero siempre: es la unica
-- forma de que un sprite de 16px no se interpole. Es tambien el zoom del
-- mundo: subirlo agranda el barco y el mar sin tocar un pixel de los sprites,
-- porque un pixel de arte sigue siendo un cuadrado exacto de pantalla. 5 es el
-- techo: a 6 la perilla del palo se mete debajo del HUD.
Constants.ART = 5
Constants.ART_W = 108
Constants.ART_H = 192

-- Tamano de la rejilla de arte de referencia (los sprites son multiplos).
Constants.TILE = 16

Constants.FONT_SIZES = { LARGE = 48, MEDIUM = 32, SMALL = 24, TINY = 16 }
Constants.BASE_FONT_SIZES = { LARGE = 48, MEDIUM = 32, SMALL = 24, TINY = 16 }

-- Margenes seguros (notch / barra de navegacion) en coordenadas virtuales.
Constants.SAFE_TOP, Constants.SAFE_BOTTOM = 0, 0
Constants.SAFE_LEFT, Constants.SAFE_RIGHT = 0, 0

function Constants.updateResolution(windowWidth, windowHeight)
    local aspect = windowWidth / windowHeight

    -- Ancho fijo, alto segun el aspecto: una pantalla mas larga ensena mas mar
    -- en vez de deformar o poner bandas negras.
    Constants.GAME_WIDTH  = Constants.BASE_WIDTH
    Constants.GAME_HEIGHT = math.floor(Constants.BASE_WIDTH / aspect)

    -- Si la ventana es apaisada (escritorio) invertimos el criterio para no
    -- generar un lienzo absurdamente bajo.
    if aspect > (Constants.BASE_WIDTH / Constants.BASE_HEIGHT) then
        Constants.GAME_HEIGHT = Constants.BASE_HEIGHT
        Constants.GAME_WIDTH  = math.floor(Constants.BASE_HEIGHT * aspect)
    end

    Constants.SCALE = math.min(Constants.GAME_WIDTH / Constants.BASE_WIDTH,
                               Constants.GAME_HEIGHT / Constants.BASE_HEIGHT)

    -- ART se queda en 5 salvo que el lienzo sea tan estrecho que el area de
    -- arte baje de los 108 px de ancho con los que esta encuadrado el barco;
    -- entonces baja de escalon en vez de recortar el barco. El area de arte se
    -- deriva de ART, nunca al reves.
    Constants.ART = math.max(2, math.min(5, math.floor(Constants.GAME_WIDTH / 108)))
    Constants.ART_W = math.floor(Constants.GAME_WIDTH  / Constants.ART)
    Constants.ART_H = math.floor(Constants.GAME_HEIGHT / Constants.ART)

    -- Las fuentes se ajustan a multiplos de 8, la rejilla de Pixellari: un
    -- tamano intermedio la renderiza a medio pixel y se ve sucia.
    local function snap(base, min)
        return math.max(min, math.floor(base * Constants.SCALE / 8) * 8)
    end
    Constants.FONT_SIZES.LARGE  = snap(Constants.BASE_FONT_SIZES.LARGE, 24)
    Constants.FONT_SIZES.MEDIUM = snap(Constants.BASE_FONT_SIZES.MEDIUM, 16)
    Constants.FONT_SIZES.SMALL  = snap(Constants.BASE_FONT_SIZES.SMALL, 8)
    Constants.FONT_SIZES.TINY   = snap(Constants.BASE_FONT_SIZES.TINY, 8)
end

function Constants.updateSafeInsets(sx, sy, sw, sh, windowW, windowH)
    local kx = windowW / Constants.GAME_WIDTH
    local ky = windowH / Constants.GAME_HEIGHT
    Constants.SAFE_LEFT   = sx / kx
    Constants.SAFE_TOP    = sy / ky
    Constants.SAFE_RIGHT  = (windowW - sx - sw) / kx
    Constants.SAFE_BOTTOM = (windowH - sy - sh) / ky
end

-- Centro del barco en espacio de arte. Va justo en la mitad: estuvo en 0.42
-- mientras el timon ocupaba la esquina inferior de estribor y habia que
-- dejarle sitio, y con el timon en la cabecera esa razon desaparecio. Bajarlo
-- al centro equilibra las dos franjas de interfaz, que ahora son parecidas de
-- alto (cabecera arriba, dos columnas de botones abajo), y deja el mismo mar
-- por proa que por popa.
--
-- No sube mas: la hoja de menu llega hasta la mitad de la pantalla y taparia
-- la cubierta justo cuando se esta repartiendo tripulacion por ella.
function Constants.shipAnchor()
    return math.floor(Constants.ART_W / 2), math.floor(Constants.ART_H * 0.50)
end

return Constants
