-- Tripulacion.
--
-- Un tripulante es una ficha de datos: gremio, pericia y soldada. No tiene
-- comportamiento; lo que aporta lo calcula src/ship.lua a partir del puesto
-- donde esta destinado. Un tripulante sin destino sigue comiendo y cobrando,
-- que es lo que hace que contratar de mas duela.
--
-- Todo (nombre, pericia, soldada) sale de Util.hash01 con la semilla del
-- mundo, la del puerto y un indice: la taberna de un puerto ofrece siempre la
-- misma gente hasta que pasa el dia, sin guardar nada.

local Util = require('src.util')

local Crew = {}

local NAMES = {
    "Aitor", "Bruna", "Casilda", "Damian", "Elvira", "Fermin", "Ginesa",
    "Hilario", "Idoia", "Jacinto", "Leire", "Malena", "Nuno", "Oria",
    "Pelayo", "Quiteria", "Roque", "Sabela", "Tadeo", "Ursula", "Valero",
    "Ximena", "Yago", "Zoa",
}

-- Los apodos son sustantivos, sin articulo y sin genero: la lista de nombres
-- mezcla hombres y mujeres y un apodo con articulo ("el Salado") sale mal la
-- mitad de las veces. Si anades uno, que aguante delante de cualquier nombre.
local TAGS = {
    "Manoslimpias", "Barbarroja", "Ojoalegre", "Piedeplomo", "Sietemares",
    "Cabrestante", "Malaracha", "Nudociego", "Mediaoreja", "Sinbrujula",
    "Caraensal", "Pocarisa", "Vientoenpopa", "Tresdedos", "Bocachica",
    "Manoderemo",
}

Crew.ROLE_NAMES = {
    helm   = "Timonel",
    sail   = "Gaviero",
    net    = "Pescador",
    cook   = "Cocinero",
    wright = "Carpintero",
    watch  = "Vigia",
    stow   = "Estibador",
}

local ROLES = { "helm", "sail", "net", "cook", "wright", "watch", "stow" }

-- Pericia 1..5. La curva esta cargada hacia abajo: un tripulante de 5 es un
-- hallazgo, no el suelo.
local function rollSkill(r)
    if r > 0.94 then return 5 end
    if r > 0.80 then return 4 end
    if r > 0.55 then return 3 end
    if r > 0.25 then return 2 end
    return 1
end

-- Genera el candidato n-esimo de una taberna. Deterministico: mismo puerto y
-- mismo dia, misma gente.
function Crew.candidate(seed, portKey, day, index)
    local a = seed + portKey * 7919 + day * 104729 + index * 31
    local role = ROLES[Util.hashInt(1, #ROLES, a, 1, 0)]
    local skill = rollSkill(Util.hash01(a, 2, 0))
    local name = NAMES[Util.hashInt(1, #NAMES, a, 3, 0)]
    local tag  = TAGS[Util.hashInt(1, #TAGS, a, 4, 0)]

    return {
        name  = name .. " " .. tag,
        role  = role,
        skill = skill,
        -- Soldada en monedas por minuto de travesia. Sube mas que lineal con
        -- la pericia: un 5 rinde el doble que un 3 pero cuesta el triple.
        wage  = math.floor(2 + skill * skill * 0.7),
        -- Prima de enganche, que es lo que pagas al contratar.
        hire  = math.floor(18 + skill * skill * 9 + Util.hash01(a, 5, 0) * 12),
        station = nil,
    }
end

function Crew.roleName(role)
    return Crew.ROLE_NAMES[role] or role
end

--== Cara ==================================================================

-- Cuantas caras hay en la reserva de assets/crew_pjNN.png. src/art.lua
-- registra exactamente estas, asi que subir el numero pide subir los PNG (o
-- quedarse con el respaldo generado, que tambien cuenta hasta aqui).
Crew.FACES = 14

-- Semilla propia de un tripulante, sacada de su nombre.
--
-- El nombre ya viene del hash del puerto y del dia, y ya se guarda con la
-- partida: colgar de el la cara y el paso por cubierta sale gratis y respeta
-- la regla de que nada aleatorio se guarda. Guardar un campo "cara" habria
-- sido guardar una semilla, y ademas habria que migrar a los que ya estan
-- enrolados en las partidas viejas.
--
-- Que dos tripulantes con el mismo nombre y apodo salgan clavados no es un
-- fallo: son 24 x 16 combinaciones y, si se repite, es que se llaman igual.
function Crew.seed(member)
    return Util.hashText(member.name or "")
end

-- Cual de las caras de la reserva le toca, en [1, Crew.FACES]. Ya no depende
-- del gremio: antes habia un monigote por gremio y el color decia el oficio,
-- pero con caras dibujadas la gente se reconoce por la cara, y el oficio se
-- lee por DONDE esta plantado en cubierta.
function Crew.face(member)
    return Util.hashInt(1, Crew.FACES, Crew.seed(member), 11, 0)
end

-- Cuanto rinde un tripulante en un puesto. Fuera de su gremio rinde a un
-- tercio: puedes poner al cocinero al timon, pero se nota.
function Crew.contribution(member, station)
    local base = member.skill
    if member.role ~= station.role then
        base = base / 3
    end
    return base
end

return Crew
