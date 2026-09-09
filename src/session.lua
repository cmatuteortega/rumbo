-- La partida en curso.
--
-- Un solo sitio donde vive el estado del mundo y el reloj de autoguardado,
-- para que las pantallas no se lo pasen unas a otras ni haya dos copias.
-- Tambien guarda el resumen de lo ocurrido mientras la app estaba cerrada,
-- que la pantalla de travesia ensena en cuanto puede.

local World = require('src.world')
local Save  = require('src.save')

local Session = {}

Session.state = nil
Session.offline = nil        -- resumen de World.catchUp, o nil
Session.AUTOSAVE = 15        -- segundos entre guardados

local saveTimer = 0

-- Carga la partida y pone al dia el tiempo ausente. Si no hay partida o esta
-- corrupta, empieza una nueva: nunca se queda sin mundo.
function Session.start()
    local state, elapsed = Save.read()
    if state then
        -- Migrar ANTES de simular: la partida puede venir de una version que
        -- no tenia la mitad de los campos que World.step lee.
        Session.state = World.migrate(state)
        Session.offline = World.catchUp(state, elapsed)
    else
        Session.state = World.new()
        Session.offline = nil
    end
    saveTimer = 0
    return Session.state
end

function Session.update(dt)
    saveTimer = saveTimer + dt
    if saveTimer >= Session.AUTOSAVE then
        saveTimer = 0
        Save.write(Session.state)
    end
end

function Session.save()
    if Session.state then Save.write(Session.state) end
end

-- Empieza de cero. Solo lo llama el atajo de depuracion (F5).
function Session.reset()
    Save.delete()
    Session.state = World.new()
    Session.offline = nil
end

return Session
