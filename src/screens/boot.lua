-- Arranque: genera el arte y carga la partida.
--
-- Los sprites se construyen de uno en uno, un puñado por fotograma, para que
-- la barra de progreso se pueda pintar entre medias. Generarlos todos dentro
-- de love.load() deja la pantalla en negro el tiempo que tarde, que en un
-- movil lento se nota y parece que ha petado.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Art       = require('src.art')
local UI        = require('src.ui')
local Session   = require('src.session')
local ScreenManager = require('lib.screen_manager')

local Boot = {}

local PER_FRAME = 3

local progress, done, settle

function Boot.enter()
    progress, done, settle = 0, false, 0
end

function Boot.update(dt)
    if not done then
        for _ = 1, PER_FRAME do
            local finished, p = Art.step()
            progress = p
            if finished then
                done = true
                Session.start()
                local mine, generated, absent = Art.manifest()
                print(string.format("[arte] %d sprites de assets/, %d generados",
                                    #mine, #generated))
                for _, id in ipairs(mine) do print("  assets/ -> " .. id) end
                -- Las capas opcionales que no tienen PNG se dicen en voz alta:
                -- no petan, simplemente no se dibujan, y eso es justo lo que
                -- cuesta descubrir mirando la pantalla.
                for _, id in ipairs(absent) do print("  falta   -> " .. id) end
                break
            end
        end
    else
        -- Un respiro para que la barra llena se vea antes de irse.
        settle = settle + dt
        if settle > 0.25 then ScreenManager.switch("voyage") end
    end
end

function Boot.draw()
    local w, h = Constants.GAME_WIDTH, Constants.GAME_HEIGHT
    UI.rect(0, 0, w, h, Palette.deep)

    UI.textCenter("RUMBO", w / 2, h * 0.38, Palette.gold, Fonts.large)
    UI.textCenter("aparejando el barco", w / 2, h * 0.38 + 60, Palette.dim, Fonts.small)

    local barW = w * 0.6
    UI.bar((w - barW) / 2, h * 0.55, barW, 14, progress, Palette.foam)
end

return Boot
