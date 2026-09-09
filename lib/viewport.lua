-- Lienzo virtual.
--
-- Todo el juego se dibuja en un lienzo del tamano virtual (540 de ancho, alto
-- segun la pantalla) y ese lienzo se estira una sola vez hasta la ventana. Es
-- lo que permite trabajar en un espacio de coordenadas fijo sin pelearse con
-- la densidad de pixeles del movil de turno.
--
-- El filtro es 'nearest' en el lienzo y en todo lo que se dibuje dentro: en
-- cuanto algo interpola, el arte de 16px se convierte en papilla.

local Viewport = {}

local canvas
local vw, vh = 1, 1
local scale, ox, oy = 1, 0, 0

function Viewport.setup(virtualW, virtualH, windowW, windowH)
    if canvas then canvas:release() end
    vw, vh = virtualW, virtualH
    canvas = love.graphics.newCanvas(vw, vh)
    canvas:setFilter('nearest', 'nearest')

    scale = math.min(windowW / vw, windowH / vh)
    ox = math.floor((windowW - vw * scale) / 2)
    oy = math.floor((windowH - vh * scale) / 2)
end

function Viewport.start()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
end

function Viewport.finish()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, ox, oy, 0, scale, scale)
end

-- Ventana -> virtual. Devuelve nil si el toque cae fuera del lienzo (bandas).
function Viewport.toGame(x, y)
    local gx, gy = (x - ox) / scale, (y - oy) / scale
    if gx < 0 or gy < 0 or gx > vw or gy > vh then return nil end
    return gx, gy
end

return Viewport
