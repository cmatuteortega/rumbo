-- Puerto: mercado, taberna y astillero.
--
-- Pantalla completa, no una hoja, porque bajar a tierra es cambiar de sitio y
-- conviene que se note. El mundo sigue corriendo debajo (World.advance sigue
-- llamandose aqui): amarrado no se navega ni se pesca, pero la cocina cocina,
-- la tripulacion come y cobra. Quedarse en puerto no es gratis.
--
-- Nada de lo que ofrece el puerto se guarda: los precios y la gente de la
-- taberna son funcion del puerto, de la semilla y del dia de travesia (ver
-- src/ports.lua y src/crew.lua). Lo unico que recuerda la partida es a quien
-- ya has contratado, para que no vuelva a aparecer en la lista.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Art       = require('src.art')
local UI        = require('src.ui')
local World     = require('src.world')
local Ports     = require('src.ports')
local Crew      = require('src.crew')
local Ship      = require('src.ship')
local Stations  = require('src.stations')
local Session   = require('src.session')
local ScreenManager = require('lib.screen_manager')

local Port = {}

local TABS = { "Mercado", "Taberna", "Astillero" }
local tab = 1

local function state() return Session.state end

local function takenKey(port, day, index)
    return port.key .. "/" .. day .. "/" .. index
end

--==========================================================================
-- Pestañas
--==========================================================================

local function market(s, port, x, y, w)
    local day = World.day(s)
    local prices = Ports.prices(s.seed, port, day)

    UI.text("Precios de hoy en " .. port.name, x, y, Palette.dim, Fonts.tiny)
    y = y + 26

    local fish = math.floor(s.res.fish)
    if UI.row(x, y, w, 44,
              string.format("Vender pescado (%d)", fish),
              string.format("%d monedas", fish * prices.fish),
              { rightInk = fish > 0 and Palette.gold or Palette.dim }) then
        if fish > 0 then
            local earned = World.sell(s, "fish", fish, prices.fish)
            World.log(s, "Vendido el pescado por " .. earned .. " monedas.")
        end
    end
    y = y + 52

    local packs = {
        { key = "wood",   label = "Comprar 5 madera",   n = 5,  price = prices.wood },
        { key = "ration", label = "Comprar 10 raciones", n = 10, price = prices.ration },
    }
    for _, pack in ipairs(packs) do
        local total = pack.n * pack.price
        if UI.row(x, y, w, 44, pack.label, total .. " monedas",
                  { rightInk = s.res.coin >= total and Palette.gold or Palette.red }) then
            if s.res.coin >= total then
                World.buy(s, pack.key, pack.n, pack.price)
                World.log(s, "Cargado en bodega: " .. pack.label:lower() .. ".")
            end
        end
        y = y + 52
    end

    UI.text("Un puerto grande paga mejor el pescado y vende mas barato.",
            x, y + 6, Palette.dim, Fonts.tiny)
end

local function tavern(s, port, x, y, w)
    local day = World.day(s)
    local portKey = port.cx * 1000 + port.cy

    UI.text("Se enrolan por una prima; luego cobran soldada cada minuto.",
            x, y, Palette.dim, Fonts.tiny)
    y = y + 26

    local shown = 0
    for i = 1, Ports.tavernSize(port) do
        local key = takenKey(port, day, i)
        if not s.taken[key] then
            local candidate = Crew.candidate(s.seed, portKey, day, i)
            local affordable = s.res.coin >= candidate.hire
            if UI.row(x, y, w, 44, candidate.name,
                      string.format("%s %d · %d mon.", Crew.roleName(candidate.role),
                                    candidate.skill, candidate.hire),
                      { rightInk = affordable and Palette.gold or Palette.red }) then
                if affordable then
                    local ok = World.hire(s, candidate)
                    if ok then s.taken[key] = true end
                end
            end
            y = y + 50
            shown = shown + 1
        end
    end

    if shown == 0 then
        UI.text("La taberna esta vacia. Vuelve otro dia.", x, y, Palette.dim, Fonts.small)
        y = y + 30
    end

    y = y + 12
    UI.text("A bordo", x, y, Palette.dim, Fonts.tiny)
    y = y + 24
    for i = 1, math.min(4, #s.crew) do
        local member = s.crew[i]
        if UI.row(x, y, w, 38, member.name, "licenciar",
                  { rightInk = Palette.red }) then
            World.dismiss(s, member)
        end
        y = y + 42
    end
end

local function shipyard(s, port, x, y, w)
    local day = World.day(s)
    local prices = Ports.prices(s.seed, port, day)

    local missing = 100 - s.hull
    local cost = math.ceil(missing * prices.repairPerPoint)
    UI.text(string.format("Casco al %d%%", math.floor(s.hull)), x, y, Palette.text, Fonts.small)
    y = y + 28
    if UI.row(x, y, w, 44, "Calafatear el casco",
              missing > 0.5 and (cost .. " monedas") or "sin averias",
              { rightInk = s.res.coin >= cost and Palette.gold or Palette.red }) then
        World.repair(s, prices.repairPerPoint)
    end
    y = y + 56

    UI.text("Mejoras del barco", x, y, Palette.dim, Fonts.tiny)
    y = y + 24
    for _, def in ipairs(Stations.list) do
        local slot = s.stations[def.id]
        local up = Stations.upgradeCost(slot.level)
        local maxed = slot.level >= Stations.MAX_LEVEL
        local canPay = s.res.coin >= up.coin and s.res.wood >= up.wood
        local right = maxed and "maximo"
            or string.format("%d mon. + %d mad.", up.coin, up.wood)
        if UI.row(x, y, w, 40, string.format("%s  nv %d", def.name, slot.level), right,
                  { rightInk = (not maxed and canPay) and Palette.gold or Palette.dim }) then
            World.upgrade(s, def.id)
        end
        y = y + 44
    end
end

--==========================================================================
-- Ciclo de pantalla
--==========================================================================

function Port.enter()
    tab = 1
    state().taken = state().taken or {}
end

function Port.update(dt)
    World.advance(state(), dt)
    Session.update(dt)
    -- Si el barco deja de estar amarrado (por lo que sea) no se puede seguir
    -- en tierra: no hay puerto al que volver.
    if not state().docked then ScreenManager.switch("voyage") end
end

function Port.draw()
    local s = state()
    local port = World.dockedPort(s)
    if not port then return end

    local w, h = Constants.GAME_WIDTH, Constants.GAME_HEIGHT
    UI.rect(0, 0, w, h, Palette.deep)

    -- Cabecera: el puerto dibujado en grande, con el mismo sprite que se ve
    -- desde el mar. Es lo que ata las dos vistas.
    local head = Constants.SAFE_TOP + 8
    UI.rect(0, 0, w, head + 96, Palette.uiBack)
    local pw, ph = Art.size("sea.port")
    love.graphics.draw(Art.get("sea.port"), math.floor(w - pw * 3 - 16),
                       math.floor(head + 4), 0, 3, 3)
    UI.text(port.name, 16, head + 8, Palette.gold, Fonts.medium)
    UI.text(string.format("puerto de %s · dia %d",
                          ({ "una cala", "buen calado", "gran calado" })[port.size],
                          World.day(s) + 1),
            16, head + 48, Palette.dim, Fonts.small)
    UI.text(string.format("%s monedas · %s madera · %s raciones",
                          Util.short(s.res.coin), Util.short(s.res.wood),
                          Util.short(s.res.ration)),
            16, head + 74, Palette.text, Fonts.tiny)

    -- Pestañas.
    local ty = head + 108
    local tw = (w - 24) / #TABS
    for i, name in ipairs(TABS) do
        local tx = 12 + (i - 1) * tw
        if UI.button(tx, ty, tw - 6, 46, name,
                     { tone = (i == tab) and Palette.gold or Palette.uiLine,
                       ink = (i == tab) and Palette.gold or Palette.dim }) then
            tab = i
        end
    end

    local x, y, cw = 16, ty + 62, w - 32
    if tab == 1 then
        market(s, port, x, y, cw)
    elseif tab == 2 then
        tavern(s, port, x, y, cw)
    else
        shipyard(s, port, x, y, cw)
    end

    local bottom = h - Constants.SAFE_BOTTOM
    if UI.button(12, bottom - 62, w - 24, 50, "Volver a bordo", { tone = Palette.gold }) then
        ScreenManager.switch("voyage")
    end
end

function Port.keypressed(key)
    if key == "escape" then ScreenManager.switch("voyage") end
end

return Port
