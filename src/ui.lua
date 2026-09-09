-- UI inmediata.
--
-- No hay objetos de widget ni arboles: cada pantalla dibuja sus botones cada
-- fotograma y UI.button devuelve true si el toque de este fotograma cayo
-- dentro. Un panel entero son diez lineas y no hay estado que sincronizar
-- entre lo que se ve y lo que responde.
--
-- El puntero lo alimenta main.lua desde los callbacks de raton y tactil, en
-- coordenadas VIRTUALES (540 de ancho). El UI no vive en espacio de arte: el
-- texto es una fuente TTF y necesita la resolucion fina.
--
-- Como el toque se procesa durante el dibujo, la accion ocurre un fotograma
-- despues de soltar. A 60 Hz no se nota y ahorra mantener listas de botones.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Art       = require('src.art')

local UI = {}

UI.pointer = { x = -1000, y = -1000, down = false, released = false, moved = false }

function UI.press(x, y)
    UI.pointer.x, UI.pointer.y = x, y
    UI.pointer.down = true
    UI.pointer.moved = false
    UI.pointer.startX, UI.pointer.startY = x, y
end

function UI.move(x, y)
    UI.pointer.x, UI.pointer.y = x, y
    if UI.pointer.down and UI.pointer.startX then
        local dx, dy = x - UI.pointer.startX, y - UI.pointer.startY
        if dx * dx + dy * dy > 100 then UI.pointer.moved = true end
    end
end

function UI.release(x, y)
    UI.pointer.x, UI.pointer.y = x, y
    UI.pointer.down = false
    -- Un arrastre no es un toque: soltar lejos de donde se apreto no dispara
    -- botones. Es lo que deja convivir la rueda del timon con la cubierta.
    UI.pointer.released = not UI.pointer.moved
end

-- Se llama al final de cada draw: consume el toque del fotograma.
function UI.finish()
    UI.pointer.released = false
    UI.locked = false
end

-- Bloqueo de entrada. Los widgets se siguen DIBUJANDO, pero no responden.
-- Es lo que evita que un toque dentro de una hoja abierta dispare ademas el
-- boton que ha quedado debajo: como la hoja se dibuja la ultima, sin esto el
-- de abajo se lleva el toque primero.
UI.locked = false

function UI.lock(value)
    UI.locked = value and true or false
end

function UI.inside(x, y, w, h)
    local p = UI.pointer
    return p.x >= x and p.y >= y and p.x < x + w and p.y < y + h
end

--== Primitivas ============================================================

function UI.rect(x, y, w, h, color)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.floor(w), math.floor(h))
    love.graphics.setColor(1, 1, 1, 1)
end

function UI.border(x, y, w, h, color)
    love.graphics.setColor(color)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", math.floor(x) + 1, math.floor(y) + 1,
                            math.floor(w) - 2, math.floor(h) - 2)
    love.graphics.setColor(1, 1, 1, 1)
end

function UI.panel(x, y, w, h)
    UI.rect(x, y, w, h, Palette.uiPanel)
    UI.border(x, y, w, h, Palette.uiLine)
end

function UI.text(str, x, y, color, font)
    love.graphics.setFont(font or Fonts.small)
    love.graphics.setColor(color or Palette.text)
    love.graphics.print(str, math.floor(x), math.floor(y))
    love.graphics.setColor(1, 1, 1, 1)
end

function UI.textCenter(str, cx, y, color, font)
    font = font or Fonts.small
    UI.text(str, cx - font:getWidth(str) / 2, y, color, font)
end

function UI.textRight(str, rx, y, color, font)
    font = font or Fonts.small
    UI.text(str, rx - font:getWidth(str), y, color, font)
end

-- Dibuja un sprite de arte dentro del espacio virtual, a escala entera.
function UI.icon(id, x, y, scale)
    scale = scale or Constants.ART
    love.graphics.draw(Art.get(id), math.floor(x), math.floor(y), 0, scale, scale)
end

--== Botones ===============================================================

-- Devuelve true si se ha tocado. `opts.enabled = false` lo apaga; `opts.tone`
-- pinta el borde de otro color (oro para lo importante, rojo para lo que
-- resta).
function UI.button(x, y, w, h, label, opts)
    opts = opts or {}
    local enabled = opts.enabled ~= false
    local hot = enabled and UI.pointer.down and UI.inside(x, y, w, h) and not UI.pointer.moved

    local face = enabled and (hot and Palette.uiLine or Palette.uiPanel) or Palette.uiBack
    local edge = enabled and (opts.tone or Palette.uiLine) or Palette.uiPanel
    local ink  = enabled and (opts.ink or Palette.text) or Palette.dim

    UI.rect(x, y, w, h, face)
    UI.border(x, y, w, h, edge)

    local font = opts.font or Fonts.small
    local ty = y + (h - font:getHeight()) / 2
    if opts.icon then
        local iw = select(1, Art.size(opts.icon)) * 2
        UI.icon(opts.icon, x + 10, y + (h - iw) / 2, 2)
        UI.text(label, x + 16 + iw, ty, ink, font)
    else
        UI.textCenter(label, x + w / 2, ty, ink, font)
    end

    local hit = enabled and not UI.locked and UI.pointer.released and UI.inside(x, y, w, h)
    if hit then UI.pointer.released = false end   -- un toque, un boton
    return hit
end

-- Fila de lista tocable: fondo, texto a la izquierda, valor a la derecha.
function UI.row(x, y, w, h, left, right, opts)
    opts = opts or {}
    local hot = UI.pointer.down and UI.inside(x, y, w, h) and not UI.pointer.moved
    UI.rect(x, y, w, h, hot and Palette.uiLine or Palette.uiPanel)
    if opts.tone then UI.border(x, y, w, h, opts.tone) end

    local font = opts.font or Fonts.small
    local ty = y + (h - font:getHeight()) / 2
    UI.text(left, x + 12, ty, opts.ink or Palette.text, font)
    if right then UI.textRight(right, x + w - 12, ty, opts.rightInk or Palette.dim, font) end

    local hit = not UI.locked and UI.pointer.released and UI.inside(x, y, w, h)
    if hit then UI.pointer.released = false end
    return hit
end

-- Barra de progreso (casco, moral, carga). Sin degradados: relleno plano.
function UI.bar(x, y, w, h, fraction, color)
    UI.rect(x, y, w, h, Palette.uiBack)
    UI.rect(x, y, math.max(0, w * math.min(1, fraction)), h, color)
    UI.border(x, y, w, h, Palette.uiLine)
end

-- La misma barra, de pie y llenandose de abajo arriba, como un deposito.
-- Puestas tres en fila ocupan el ancho de una sola tumbada, y lo que se
-- compara de un vistazo es la ALTURA de las tres, no tres longitudes que hay
-- que leer una por una. El relleno se redondea a entero para que el borde de
-- la carga caiga en un pixel y no en medio.
function UI.vbar(x, y, w, h, fraction, color)
    local fill = math.floor(h * math.min(1, math.max(0, fraction)))
    UI.rect(x, y, w, h, Palette.uiBack)
    UI.rect(x, y + h - fill, w, fill, color)
    UI.border(x, y, w, h, Palette.uiLine)
end

--== Hoja inferior =========================================================

-- Las hojas suben desde abajo. El deslizamiento es puramente estetico, pero
-- la altura animada es la que se usa para dibujar, asi que los botones estan
-- donde se ven mientras entra.
local Sheet = {}
Sheet.__index = Sheet

function UI.newSheet()
    return setmetatable({ open = false, t = 0, height = 0, key = nil }, Sheet)
end

function Sheet:show(key, height)
    self.open = true
    self.key = key
    self.height = height
end

function Sheet:hide()
    self.open = false
end

function Sheet:update(dt)
    local target = self.open and 1 or 0
    local speed = 6
    self.t = self.t + (target - self.t) * math.min(1, dt * speed)
    if math.abs(self.t - target) < 0.002 then self.t = target end
end

function Sheet:visible()
    return self.t > 0.01
end

-- Y de la parte superior de la hoja, en coordenadas virtuales. La hoja llega
-- siempre hasta el borde inferior de la pantalla: `height` es cuanto sube,
-- no un rectangulo flotante, para que no quede una franja de mar debajo.
function Sheet:top()
    local bottom = Constants.GAME_HEIGHT - Constants.SAFE_BOTTOM
    return bottom - self.height * self.t
end

-- Y donde va el boton de accion de la hoja (mejorar, seguir...). Siempre
-- pegado abajo, dentro del margen seguro, para que caiga bajo el pulgar.
function Sheet:actionY()
    return Constants.GAME_HEIGHT - Constants.SAFE_BOTTOM - 62
end

-- Dibuja el velo, el marco, y devuelve (x, y, w) del area de contenido.
function Sheet:frame(title)
    local x = 12
    local w = Constants.GAME_WIDTH - 24
    local y = self:top()

    -- Velo: es el unico sitio del juego con alpha, y esta aqui para que el
    -- mar de detras no compita con el texto.
    love.graphics.setColor(0, 0, 0, 0.45 * self.t)
    love.graphics.rectangle("fill", 0, 0, Constants.GAME_WIDTH, Constants.GAME_HEIGHT)
    love.graphics.setColor(1, 1, 1, 1)

    UI.panel(x, y, w, Constants.GAME_HEIGHT - y)
    UI.rect(x + 2, y + 2, w - 4, 3, Palette.uiLine)
    UI.text(title, x + 16, y + 12, Palette.text, Fonts.medium)

    if UI.button(x + w - 56, y + 8, 44, 40, "X", { tone = Palette.uiLine }) then
        self:hide()
    end

    return x + 12, y + 58, w - 24
end

-- Un toque dentro de la hoja no debe llegar a la cubierta que hay detras.
function Sheet:blocks(x, y)
    return self:visible() and y >= self:top()
end

return UI
