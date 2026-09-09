-- Paleta cerrada. Todo lo que se dibuja sale de aqui: ni un RGB suelto en el
-- resto del codigo. Con una paleta corta los sprites generados y los que
-- dibujes tu conviven sin que se note la costura, y cambiar el mar entero es
-- tocar tres lineas de este archivo.
--
-- Nada usa alpha salvo los velos de UI (paneles), que llevan su propio alpha
-- explicito en el sitio donde se dibujan.

local function hex(s)
    return {
        tonumber(s:sub(1, 2), 16) / 255,
        tonumber(s:sub(3, 4), 16) / 255,
        tonumber(s:sub(5, 6), 16) / 255,
        1,
    }
end

local Palette = {
    -- Mar, de fondo a espuma.
    deep    = hex("0b2038"),
    sea     = hex("123a55"),
    shallow = hex("1c5a73"),
    foam    = hex("6fb8bd"),
    white   = hex("dcf2f2"),

    -- Madera y cubierta.
    woodDark = hex("3a2418"),
    wood     = hex("6b432a"),
    woodLite = hex("9a6b3f"),
    deck     = hex("b8894f"),
    deckLite = hex("d6a566"),

    -- Trapo y jarcia.
    sail      = hex("e8dcc0"),
    sailShade = hex("bfaf8e"),
    rope      = hex("8a7550"),

    -- Tierra.
    sand  = hex("d8c58c"),
    grass = hex("5fa34a"),
    rock  = hex("5a5a63"),

    -- Acentos y UI.
    ink     = hex("16121a"),
    gold    = hex("e8b23c"),
    red     = hex("b23a3a"),
    green   = hex("5fa34a"),
    skin    = hex("d9a06b"),
    uiBack  = hex("101a26"),
    uiPanel = hex("182839"),
    uiLine  = hex("2e4a63"),
    text    = hex("e6eef2"),
    dim     = hex("7c93a6"),
}

-- Mezcla dos colores de la paleta. Solo para generar sprites: en pantalla se
-- dibuja siempre un color de la tabla, nunca uno interpolado en vivo.
function Palette.mix(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        1,
    }
end

return Palette
