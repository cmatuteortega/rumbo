-- Puestos del barco.
--
-- Un puesto es una parte de la cubierta con la que se interactua: se toca en
-- la vista cenital y abre su hoja. Cada uno tiene un gremio (role), plazas
-- para tripulantes y un nivel que se sube en el astillero.
--
-- deckX/deckY son FRACCIONES del lienzo del barco (80x96 por defecto), con el
-- origen arriba a la izquierda y la proa arriba. Al ser fracciones, cambiar el
-- tamano de los PNG del barco los reescala solos en Ship.deckPoint().
--
-- Ojo: el lienzo es mas grande que el casco, porque lleva aire para que las
-- vergas y las bocas de los canones asomen por fuera de la borda (ver
-- Art.HULL_BOX). Una fraccion de 0.5 es la crujia, pero 0.05 es agua, no proa.
--
-- Los tres puestos que YA tienen arte estan clavados sobre su sprite -- la
-- cocina sobre el fogon de cook1.png, las redes sobre el aparejo de fish1.png,
-- el velamen al pie del palo de sails1.png -- porque un aro dorado a cinco
-- pixeles de su cacharro se lee como un error, no como un puesto.
--
-- Un puesto ya NO dice con que sprite se pinta a quien lo ocupa. Habia un
-- monigote por gremio y el color decia el oficio; ahora cada tripulante saca
-- su cara de la reserva de assets/crew_pjNN.png segun su nombre (Crew.face) y
-- el oficio se lee por donde esta plantado, que es lo que la cubierta ya
-- explicaba mejor que un color.
--
-- Lo que un puesto *hace* no vive aqui: aqui esta la definicion, y src/ship.lua
-- convierte nivel + tripulacion en los numeros que usa la simulacion. Asi se
-- puede anadir un puesto sin tocar la simulacion, y ajustar el balance sin
-- tocar la cubierta.

local Stations = {}

Stations.list = {
    {
        id = "crowsnest", name = "Cofa", role = "watch",
        icon = "icon.anchor",
        -- En la perilla del palo, que es lo mas a proa que hay: la cofa se
        -- mira arriba, y aqui arriba es la proa.
        deckX = 0.500, deckY = 0.156,
        desc = "El vigia avista puertos mas lejos y pesca restos a la deriva.",
    },
    {
        id = "carpentry", name = "Carpinteria", role = "wright",
        icon = "icon.hull",
        -- Amura de babor, justo por debajo del pano. El cuadrante de estribor
        -- lo ocupa ya la cana de las redes, que sube hasta aqui.
        deckX = 0.350, deckY = 0.323,
        desc = "Repara el casco gastando madera. Sin carpintero el barco se pudre.",
    },
    {
        id = "sails", name = "Velamen", role = "sail",
        icon = "icon.sail",
        -- Al pie del palo, en la fogonadura: es donde se cazan las drizas.
        deckX = 0.500, deckY = 0.521,
        desc = "Manos a las drizas: mas trapo bien cazado, mas nudos.",
    },
    {
        id = "nets", name = "Redes", role = "net",
        icon = "icon.fish",
        -- Sobre el aparejo de fish1.png, a estribor. Estaba a babor antes de
        -- que llegara el arte; manda el dibujo.
        deckX = 0.762, deckY = 0.490,
        desc = "Pesca de arrastre mientras se navega. La base de la despensa.",
    },
    {
        id = "galley", name = "Cocina", role = "cook",
        icon = "icon.ration",
        -- Sobre el fogon de cook1.png, arrimado a la borda de babor.
        deckX = 0.275, deckY = 0.458,
        desc = "Convierte pescado en raciones. Sin raciones la moral se hunde.",
    },
    {
        id = "hold", name = "Bodega", role = "stow",
        icon = "icon.hold",
        -- A popa, en el pasillo que dejan los dos panoles. Sin sprite propio
        -- todavia: la trampilla la genera gen.shipHold leyendo estas dos
        -- fracciones, asi que moverlas mueve el dibujo.
        deckX = 0.500, deckY = 0.667,
        desc = "Cuanto cabe en la bodega. Llena, el barco se echa a la capa.",
    },
    {
        id = "helm", name = "Timon", role = "helm",
        icon = "icon.wind",
        -- En la toldilla, sobre el espejo de popa.
        deckX = 0.500, deckY = 0.813,
        desc = "Cuanto mejor el timonel, mas rapido cae el barco al nuevo rumbo.",
    },
}

Stations.byId = {}
for i, s in ipairs(Stations.list) do
    s.order = i
    Stations.byId[s.id] = s
end

-- Plazas de tripulacion segun nivel: 1, 1, 2, 2, 3... Subir de nivel siempre
-- da algo, pero solo cada dos niveles da una plaza, para que meter gente no
-- sea la unica palanca.
function Stations.capacity(level)
    return 1 + math.floor(level / 2)
end

Stations.MAX_LEVEL = 8

-- Capacidad de bodega por recurso. Es el numero que decide cuanto rinde una
-- ausencia: el barco produce hasta llenarla y ahi se planta, asi que subir la
-- bodega es literalmente comprar horas de idle. Ver el comentario de
-- Ship.stowed sobre por que eso tambien para las soldadas.
function Stations.holdCapacity(power)
    return math.floor(50 + 50 * power)
end

-- Coste de subir del nivel actual al siguiente. Crece rapido en monedas y
-- despacio en madera: la madera se saca del mar (restos, cofa) y las monedas
-- del mercado, asi que son dos ritmos distintos a proposito.
function Stations.upgradeCost(level)
    return {
        coin = math.floor(25 * (1.85 ^ (level - 1))),
        wood = math.floor(4 + 3 * (level - 1)),
    }
end

return Stations
