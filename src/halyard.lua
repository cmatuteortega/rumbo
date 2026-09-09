-- La driza del velamen: largar trapo y tomar rizos tirando de una cuerda.
--
-- Es la hermana de la rueda del timon (`src/helm.lua`) y sale del mismo
-- reparto: los dos mandos que se usan NAVEGANDO se sacan tocando su puesto en
-- cubierta, no desde la columna de botones. Tocar el velamen larga esta
-- cuerda por la esquina de arriba a babor -- la unica esquina de la pantalla
-- sin interfaz, porque el bloque del HUD esta a estribor y la bitacora abajo
-- -- y deja la hoja del puesto para el segundo toque, igual que el timon. Es
-- el mismo orden de frecuencia: se toca el trapo muchas veces por cada vez
-- que se destina a alguien a las drizas.
--
-- SE MANEJA COMO UNA PERSIANA, y de ahi sale todo lo demas: el trapo no es un
-- interruptor con dos estados iguales, sino algo que se recoge tirando y se
-- larga de golpe. Las dos maniobras no son simetricas a proposito:
--
--   trapo largo   la cuerda cuelga CORTA, con el nudo a la altura de la rosa.
--                 Se arrastra el nudo hacia abajo -- un trecho largo, hasta
--                 media pantalla -- y al soltar quedan tomados los rizos.
--   con rizos     la cuerda cuelga LARGA, con el nudo a media pantalla, ahi
--                 donde cae el pulgar. Un tiron corto y soltar: la cuerda
--                 rebota hasta arriba y el trapo queda largo.
--
-- Recoger cuesta un arrastre largo y largar un tiron corto porque es lo que
-- hace una persiana de verdad, y porque las dos maniobras no valen lo mismo:
-- los rizos se toman para no romper nada y el trapo se larga para correr, asi
-- que la que cuesta es la de guardar.
--
-- EL LARGO DE LA CUERDA ES EL INDICADOR. No hay ninguna lectura que diga que
-- trapo se lleva: lo dice cuanto cuelga, lo dicen las velas del barco (hay
-- sprite de trapo arrizado) y lo dice la bitacora. Lo unico que se pinta de
-- mas es el NUDO EN ORO cuando ya se ha tirado bastante para que soltar haga
-- algo, que es el color con el que este juego dice "esto es lo que has
-- pedido". Y no lleva texto: la rueda lleva lectura porque un rumbo no tiene
-- otra representacion que un numero, pero el trapo se ve en el barco.
--
-- LA CUERDA TIENE FISICAS de verdad, y el reparto es el de este trasto: un
-- cabo ligero con un NUDO PESADO en la punta. FISICA TIENE EL NUDO, y solo el:
-- un pendulo colgado del ancla, con el radio en un muelle. La cuerda de en
-- medio no se simula, se DERIVA -- una recta del ancla al nudo con una comba,
-- que es un solo numero -- y en `shape` esta por que, que es la lectura que
-- mas cuesta de este archivo.
--
-- No es adorno: de este reparto salen tres cosas que si no habria que escribir
-- una por una. El rebote al largar trapo (el muelle del radio se pasa de largo
-- y vuelve), el latigazo de la cuerda cuando el nudo corre de lado, y el
-- balanceo de pendulo al soltar despues de arrastrar en diagonal. El muelle va
-- subamortiguado: UN rebote que se lee, y no tres que marean. Y el largo
-- cambia deslizando por el ancla y no estirando, porque al nudo se le impone
-- el radio: la cuerda paga o cobra por arriba, como una de verdad.
--
-- En REPOSO esta inmovil hasta el ultimo pixel, no "casi". Derivada de dos
-- puntos y un numero, la cuerda solo cambia cuando cambia el nudo o la comba,
-- asi que quieto el nudo no hay nada que hierva; y las colas del radio, del
-- vaiven y de la comba se cortan en cuanto bajan de medio pixel (ver los
-- cortes de `update`). Una cuerda colgada esta quieta, y temblando un pixel se
-- leia como que el juego no acaba de decidirse.
--
-- Se integra a paso FIJO con acumulador, y el paso es el del fotograma
-- nominal a proposito: asi el nudo agarrado guarda de un paso al siguiente la
-- velocidad que le da el dedo, y al soltar la cuerda sale despedida en vez de
-- quedarse muerta. Un verlet a dt de fotograma, ademas, se descuadra en cuanto
-- hay un tiron de imagen, y aqui un tiron de imagen es una cuerda que se
-- estira o se dobla sola.
--
-- ENTRA DESDE LA IZQUIERDA con la misma curva y los mismos tiempos que la
-- rueda, y con la punta llegando mas tarde que el ancla (`LAG`): eso es lo que
-- la hace entrar como una cuerda que alguien larga y no como un panel que
-- desliza. La animacion es SOLO dibujo, como en la rueda: el tiron se mide
-- siempre desde el ancla PUESTA, porque midiendolo desde la que entra el
-- propio deslizamiento cambiaria el largo sin que el dedo se moviera y el
-- trapo se cambiaria solo.
--
-- SE AGARRA DONDE SE VE, nodo a nodo, y no en la recta del ancla al nudo:
-- entrando va inclinada y con la punta retrasada, y recien soltada se comba un
-- instante mientras la cuerda va floja. Una zona de toque que no coincide con
-- lo que se ve se siente rota. Y el tiron es RELATIVO -- al agarrar se guarda
-- lo que sobra entre el dedo y el nudo -- asi que se puede coger la cuerda por
-- el medio y tirar sin que el nudo salte al dedo.
--
-- Se dibuja con rectangulos de 1x1 dentro de la escala de arte, que es la
-- salida legal a la regla de "nada girado" (ver src/sea.lua): la cuerda cae a
-- cualquier angulo, pero no hay sprite que rotar y su pixel mide lo mismo que
-- el del casco. Cada pieza se pinta dos veces, engordada en `Palette.ink` y
-- luego en su color, que es de donde sale el contorno negro de 1px de los
-- sprites de assets/.
--
-- Y lleva LA TORCIDA marcada, un pixel claro cada tres, porque sin ella una
-- cuerda de media pantalla se lee como un palo. Se cuenta DESDE EL NUDO y no
-- desde el ancla, y ahi esta todo el asunto: la cuerda corre por el ancla al
-- largar y al recoger, asi que el trozo que se ve cuelga siempre del mismo
-- nudo y lo que entra por arriba es cuerda nueva. Contada desde el nudo, la
-- torcida se queda quieta sobre su material y aparece por el ancla segun sale
-- cuerda, que es lo que hace una cuerda de verdad; contada desde el ancla se
-- veria correr al reves, que es la mentira que la llanta de la rueda evita
-- yendo lisa.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Compass   = require('src.compass')

local Halyard = {}

-- Nodos de la cadena. Doce es lo que hace falta para que la curva de una
-- cuerda de media pantalla se lea como curva: con menos, el balanceo sale
-- anguloso justo en el nudo, que es donde se mira.
local NODES = 12

-- Aire entre el margen seguro de babor y la cuerda, en pixeles de ARTE y no
-- virtuales: la cuerda es del mismo grano que el barco, asi que si el lienzo
-- se estrecha y ART baja, encoge con el barco en vez de descuadrarse.
--
-- Diez y no seis: pegada al canto, la driza se leia como el marco del lienzo
-- en vez de como un cabo que baja de una verga que esta fuera de plano.
-- Separada, tiene aire a los dos lados y se ve que VIENE de algun sitio.
local MARGIN = 10

local KNOT  = 4         -- radio del nudo
local ROPE  = 2         -- grosor de la cuerda, el de las cabillas de la rueda
local TWIST = 3         -- cada cuantos pixeles de arte se marca la torcida
local MIN_LEN = 8       -- lo menos que puede colgar: el nudo no se come el ancla

-- Lo que se puede tirar mas alla del largo de rizos, y el tiron que larga
-- trapo. OVER es holgura de dedo, no maniobra: hay que poder pasarse del
-- tiron sin que la cuerda se plante, pero no llegar a la bitacora.
local OVER, TUG = 32, 16

-- Radios de agarre. La cuerda se coge por cualquier nodo, y el nudo lleva mas
-- margen porque es lo que dice "agarrame". Con el nudo a media pantalla el
-- paso entre nodos es de nueve pixeles de arte, menos que GRAB, asi que no
-- queda ningun hueco muerto de un nodo al siguiente.
local GRAB, KNOT_GRAB = 10, 15

-- Gravedad en pixeles de ARTE por segundo al cuadrado. Una cuerda de este
-- largo balancearia mas rapido de verdad, pero a este tamano de pixel un
-- balanceo mas rapido se lee como temblor en vez de como peso.
local GRAVITY = 4200

-- Amortiguacion del pendulo, como ZETA y no como un factor por cuadro. La
-- diferencia se ve: el periodo del pendulo depende del largo (2*pi/sqrt(g/len),
-- medio segundo con el trapo largo y casi uno con rizos), asi que un factor por
-- cuadro amortigua el doble de mal justo la cuerda CORTA -- en el mismo tiempo
-- da el doble de vaivenes y pierde la mitad de amplitud en cada uno. Y era
-- verdad que la corta era la que peor lucia.
--
-- Con zeta el decaimiento se cuenta en VAIVENES y no en cuadros: las dos
-- longitudes pierden la misma fraccion por vaiven y se calman igual. 0,3 deja
-- un par de vaivenes que se leen y a dormir. Mas flojo se pasa demasiado
-- tiempo fuera de cuadro por babor -- el ancla esta a seis pixeles del canto,
-- asi que cualquier vaiven se sale -- y mas fuerte se come el pendulo, que es
-- lo que hay que ver.
--
-- No toca el rebote de largar trapo: ese lo mueve el muelle del largo, que es
-- radial, y esto es la inercia transversal del nudo.
local SWAY = 0.3

-- Lo que le puede quedar de recorrido al radio y al vaiven para darlos por
-- terminados, en pixeles de arte. Ver los dos cortes de `update`: son
-- directamente la cota de lo que se puede llegar a ver moverse, asi que van
-- por debajo del pixel.
local SETTLE, SLEEP = 0.5, 0.9

-- Y por debajo de esto los ultimos pixeles se ANDAN, de uno en uno y sin
-- velocidad, en vez de atenuarse. Es el remate de todo lo anterior y el que
-- mas se nota.
--
-- Un muelle y un pendulo llegan a su sitio con cola exponencial, y esa cola a
-- este tamano de pixel no es suave: son tres o cuatro decimas de segundo de
-- pasitos de un pixel salteados, unos cuadros moviendose y otros no, que es
-- exactamente lo que se lee como que la cuerda no se decide. Y la torcida lo
-- multiplica: las marcas van a distancias fijas del NUDO, asi que cualquier
-- deriva del largo por debajo del pixel las corre todas de golpe -- dos
-- docenas de pixeles repintados por una centesima de movimiento, y mas cuanto
-- mas corta la cuerda, que es como se noto.
--
-- Andando el remate el recorrido es MONOTONO: se ve moverse un pixel, otro, y
-- quieta. Y monotono es la clave, no la duracion: un pixel de ida y otro de
-- vuelta se lee como temblor por pocos que sean, y tres de ida seguidos se
-- leen como algo posandose.
--
-- El numero tiene margen por los dos lados. Se mide por AMPLITUD (lo que falta
-- mas lo que vale la velocidad que lleva) y no por lo que falta a secas, porque
-- el rebote CRUZA el largo de reposo a toda velocidad camino de su punto alto:
-- midiendo solo lo que falta, el remate se lo tragaria ahi y no habria rebote.
-- Por eso no baja de 3,5, que es donde todavia pilla la llegada -- que va
-- despacio pero no quieta -- y por eso no sube: a 4,5 ya da pasos de dos
-- pixeles, y diez de pantalla de golpe se leen como un tiron aparte.
local WALK = 3.5

-- La comba: cuanto se retrasa la cuerda respecto al nudo cuando este corre de
-- lado. BOW son pixeles de comba por pixel/segundo de velocidad transversal,
-- BOW_MAX el tope y BOW_EASE lo rapido que la comba persigue a su valor.
-- Nada de esto se simula (ver `shape`): la comba es UN numero.
local BOW, BOW_MAX, BOW_EASE = 0.022, 6, 14
local FIXED   = 1 / 60       -- paso fijo (ver la cabecera)
local STEPS   = 4            -- tope de pasos por fotograma, contra el bucle largo

-- Muelle del largo de reposo: SPRING pone el periodo (~0,75 s) y DRAG la
-- amortiguacion. Zeta sale ~0,55, y ese numero no es de gusto: es el mas bajo
-- -- o sea el rebote mas largo -- con el que el nudo NO llega a MIN_LEN al
-- largar trapo, que es el recorrido mas largo que hace. Rebotando mas, el tope
-- se nota, y un tope que se ve es una mentira: la cuerda no se para porque
-- pese, se para porque se ha quedado sin numero.
local SPRING, DRAG = 70, 9.4

-- Los mismos tiempos que la rueda: sale en 0,24 s y se guarda en 0,16.
local ENTER, EXIT = 0.24, 0.16

-- Cuanto llega mas tarde la punta que el ancla al entrar. 1,2 quiere decir que
-- el nudo empieza mas del doble de lejos por babor que el ancla: la cuerda
-- entra inclinada y se endereza, que es como entra una cuerda largada.
local LAG = 1.2

-- El nudo es lo UNICO que tiene fisica: posicion y la anterior, para verlet.
-- `nodes` no es una cadena simulada sino la curva ya repartida para dibujarla
-- y para tocarla, que se recalcula de `knot` y `bow` en `shape()`.
local knot = { x = 0, y = 0, px = 0, py = 0 }
local nodes = {}             -- la curva, en pixeles de arte
local bow = 0                -- comba, en pixeles: + hacia babor de la cuerda
local len, lenVel = 0, 0     -- largo libre de driza y su velocidad
local grabbed = nil          -- lo que sobraba entre el dedo y el nudo al agarrar
local finger = nil           -- dedo, en pixeles de arte, mientras se arrastra
local anim, accum = 0, 0

--==========================================================================
-- Geometria
--==========================================================================

-- Ancla, en pixeles de arte: la esquina de arriba a babor del area segura. Un
-- pixel POR ENCIMA del borde, para que la cuerda venga de fuera de la pantalla
-- en vez de empezar en un punto que se ve.
function Halyard.anchor()
    return math.floor(Constants.SAFE_LEFT / Constants.ART) + MARGIN,
           math.floor(Constants.SAFE_TOP / Constants.ART) - 1
end

-- Largo de driza de cada trapo. Con el trapo largo el nudo queda a la altura
-- de la rosa; con rizos, a media pantalla. Los dos salen de donde estan las
-- cosas y no de numeros escritos a mano: la rosa se lee de `Compass.center`
-- (si se mueve, el nudo la sigue) y la media pantalla de `GAME_HEIGHT`, que no
-- es 960 (ver src/constants.lua).
local function lengths()
    local _, ay = Halyard.anchor()
    local _, roseY = Compass.center()
    return math.floor(roseY / Constants.ART) - ay,
           math.floor(Constants.GAME_HEIGHT / 2 / Constants.ART) - ay
end

local function maxLen()
    local _, reef = lengths()
    return reef + OVER
end

-- Cuanto hay que tirar para que soltar cambie el trapo, y el trapo que
-- quedaria. Es lo unico que sabe de la asimetria de las dos maniobras.
local function order(trim)
    local full, reef = lengths()
    if trim == "full" then return full + (reef - full) * 0.5, "reef" end
    return reef + TUG, "full"
end

-- Si soltando ahora mismo pasaria algo. Es lo que pinta el nudo de oro.
local function ready(trim)
    return finger ~= nil and len >= order(trim)
end

--==========================================================================
-- Entrada y salida
--==========================================================================

-- La travesia es la que sabe si la driza esta pedida; aqui solo se recorre el
-- camino hacia ese estado, como en la rueda.
local function settled()
    local u = 1 - anim
    return 1 - u * u * u
end

function Halyard.reset()
    anim, accum = 0, 0
    grabbed, finger = nil, nil
    bow, lenVel = 0, 0
    nodes = {}
end

function Halyard.showing()
    return anim > 0
end

-- Lo que le falta al ancla por entrar, en pixeles de arte. Sale de donde esta
-- el ancla y del nudo, que es lo que asoma mas: es exactamente lo que hace
-- falta para que la cuerda entera quede fuera por babor.
local function lean()
    local ax = Halyard.anchor()
    return (1 - settled()) * (ax + KNOT + 2)
end

-- Un nodo DONDE SE VE: su sitio menos lo que le falta por entrar, que crece
-- hacia la punta.
local function drawn(i)
    local n = nodes[i]
    return n.x - lean() * (1 + LAG * (i - 1) / (NODES - 1)), n.y
end

--==========================================================================
-- Fisica
--==========================================================================

-- LA CUERDA NO SE SIMULA: SE DERIVA. Es una recta del ancla al nudo con una
-- comba, y los nodos salen de repartir esa curva -- no tienen dinamica propia
-- ni la necesitan. El nudo si: es el cuerpo.
--
-- Antes eran doce nodos con verlet, tensos entre el ancla y el nudo, y la
-- cuenta salia: colgaba recta, no se doblaba, y el nudo terminaba su recorrido
-- limpio. Pero el DIBUJO hervia. Doce nodos moviendose cada uno una fraccion
-- de pixel vuelcan sellos enteros cada vez que uno cruza un borde, y la
-- torcida se reparte a lo largo del arco, asi que un cambio de largo
-- minusculo mueve marcas por toda la cuerda: sesenta pixeles cambiando de
-- cuadro a cuadro cuando el rebote ya habia terminado a la vista. Un pixel de
-- arte son cinco de pantalla, o sea que no hay posiciones intermedias que
-- ensenar y eso no se lee como algo asentandose, se lee como un parpadeo.
--
-- Y era ruido de mas: una cuerda tensa con un nudo pesado ES una recta -- lo
-- decia la propia prueba, arco igual a recta siempre -- asi que los doce nodos
-- solo aportaban la comba del latigazo, y a cambio metian todo el hervor.
-- Derivada de dos puntos y un numero, la cuerda solo cambia cuando cambia el
-- nudo o la comba: quieto el nudo, quieta hasta el ultimo pixel.
local function shape()
    local ax, ay = Halyard.anchor()
    local dx, dy = knot.x - ax, knot.y - ay
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.001 then dx, dy, d = 0, 1, 1 end
    local px, py = -dy / d, dx / d          -- perpendicular a la cuerda
    for i = 1, NODES do
        local t = (i - 1) / (NODES - 1)
        -- Un solo arco, cero en los dos extremos: la cuerda se comba en medio
        -- y no en el ancla ni en el nudo, que es donde esta sujeta.
        local arch = math.sin(t * math.pi) * bow
        nodes[i] = nodes[i] or {}
        nodes[i].x = ax + dx * t + px * arch
        nodes[i].y = ay + dy * t + py * arch
    end
end

-- Nudo a plomo, sin comba y sin velocidad: el estado guardado y el de dormida.
local function rest()
    local ax, ay = Halyard.anchor()
    knot.x, knot.px = ax, ax
    knot.y, knot.py = ay + len, ay + len
    bow = 0
    shape()
end

-- Donde queda el nudo mientras se arrastra: en la direccion del dedo, pero a
-- la distancia que da la cuerda. Pasado el tope la cuerda queda TENSA y el
-- dedo se le escapa, que es lo que hace una cuerda y no una goma.
local function tip()
    if not finger then return nil end
    local ax, ay = Halyard.anchor()
    local dx, dy = finger.x - ax, finger.y - ay
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.001 then return ax, ay + len end
    return ax + dx / d * len, ay + dy / d * len
end

-- Frecuencia del pendulo de la cuerda entera. Sale del largo, asi que cambia
-- con el trapo, y de ella salen la amortiguacion y los cortes de reposo.
local function omega()
    return math.sqrt(GRAVITY / math.max(len, MIN_LEN))
end

-- Un paso del nudo: o lo lleva el dedo, o es un pendulo colgado del ancla.
local function step()
    local ax, ay = Halyard.anchor()
    local tx, ty = tip()

    if tx then
        -- El dedo manda, y de su recorrido sale la velocidad que llevara el
        -- nudo al soltar: por eso el paso es el del fotograma (ver cabecera).
        knot.px, knot.py = knot.x, knot.y
        knot.x, knot.y = tx, ty
    else
        local damp = math.exp(-SWAY * omega() * FIXED)
        local vx, vy = (knot.x - knot.px) * damp, (knot.y - knot.py) * damp
        knot.px, knot.py = knot.x, knot.y
        knot.x = knot.x + vx
        knot.y = knot.y + vy + GRAVITY * FIXED * FIXED
    end

    -- El radio lo impone la cuerda: se le respeta la direccion al nudo y se le
    -- pone a `len` del ancla. Eso es el pendulo, y es tambien lo que hace que
    -- cambiar de largo DESLICE la cuerda por el ancla en vez de estirarla.
    local dx, dy = knot.x - ax, knot.y - ay
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.001 then dx, dy, d = 0, 1, 1 end
    local ux, uy = dx / d, dy / d
    knot.x, knot.y = ax + ux * len, ay + uy * len

    if not tx then
        -- Y se le quita la velocidad RADIAL, que es lo que hace un hilo: no
        -- empuja ni tira, solo sujeta. Sin esto, el radio que le mueve el
        -- muelle al largar trapo se le queda al nudo dentro como velocidad y
        -- se pasa de largo por su cuenta, ademas de lo que ya se pasa el
        -- muelle.
        local vx, vy = knot.x - knot.px, knot.y - knot.py
        local radial = vx * ux + vy * uy
        knot.px = knot.x - (vx - radial * ux)
        knot.py = knot.y - (vy - radial * uy)
    end

    -- La comba: la cuerda llega tarde a donde va el nudo, asi que se queda
    -- atras de su movimiento transversal. Es UN numero persiguiendo a otro, no
    -- una simulacion, y por eso no hierve.
    local vx, vy = (knot.x - knot.px) / FIXED, (knot.y - knot.py) / FIXED
    local perp = vx * -uy + vy * ux
    local want = Util.clamp(-perp * BOW, -BOW_MAX, BOW_MAX)
    bow = bow + (want - bow) * math.min(1, BOW_EASE * FIXED)
    if math.abs(bow) < 0.05 then bow = 0 end
end

function Halyard.update(dt, out, state)
    local step_ = dt / (out and ENTER or EXIT)
    anim = Util.clamp(anim + (out and step_ or -step_), 0, 1)

    local full, reef = lengths()
    local target = (state.trim == "reef") and reef or full

    -- Guardada del todo: se recoloca en su sitio cada cuadro. Es lo que hace
    -- que un cambio de trapo desde el boton, o un giro de pantalla, no la dejen
    -- con el largo de antes cuando vuelva a salir.
    if anim <= 0 and not finger then
        len, lenVel, accum = target, 0, 0
        rest()
        return
    end

    accum = math.min(accum + dt, STEPS * FIXED)
    while accum >= FIXED do
        accum = accum - FIXED

        -- El largo solo obedece al muelle cuando no hay dedo: arrastrando lo
        -- manda el dedo (ver Halyard.haul) y un muelle tirando a la vez se
        -- sentiria como forcejeo.
        if not finger then
            lenVel = lenVel + (target - len) * SPRING * FIXED
            lenVel = lenVel - lenVel * DRAG * FIXED
            len = Util.clamp(len + lenVel * FIXED, MIN_LEN, maxLen())

            -- Y se PLANTA en el largo de reposo cuando al muelle le queda
            -- menos de medio pixel de recorrido, por AMPLITUD igual que el
            -- vaiven (ver el corte de abajo): lo que falta mas lo que vale la
            -- velocidad que lleva.
            --
            -- Esta es la cola que MAS se veia: el gesto de la maniobra es hacia
            -- abajo, asi que casi no imprime balanceo y lo que queda
            -- moviendose es el radio. Y se veia doble, porque al cambiar el
            -- largo corre tambien el reparto de la torcida. El umbral de antes
            -- era 0,02 px -- una asintota, casi dos segundos -- cuando lo que
            -- se puede ver es un pixel.
            local gap = target - len
            local vel = lenVel / math.sqrt(SPRING)
            local amp = gap * gap + vel * vel
            if amp < SETTLE * SETTLE then
                len, lenVel = target, 0
            elseif amp < WALK * WALK then
                -- Los ultimos pixeles, andados (ver WALK).
                lenVel = 0
                len = len + ((gap > 0) and 1 or -1)
            end
        end

        step()
    end

    -- Y SE DUERME A PLOMO cuando al vaiven le queda menos de un pixel. Un
    -- pendulo tiene cola infinita: por debajo del pixel ya no hay nada que
    -- ensenar, pero el nudo se queda temblando uno de arte -- cinco de
    -- pantalla -- despues de cada maniobra, y eso es lo que se lee como que la
    -- cuerda no se esta quieta.
    --
    -- Se duerme por AMPLITUD, que es lo que esta desviado del plomo mas lo que
    -- lo va a desviar la velocidad que lleva (`v/omega` es la amplitud que vale
    -- esa velocidad). Y no por "a plomo y quieto", que esperaba de mas: un
    -- pendulo pasa por el plomo a toda velocidad y se para solo en los
    -- extremos, asi que pidiendo las dos cosas a la vez hay que aguardar a que
    -- coincidan -- y lo que se ve mientras se aguarda es justo el temblor.
    --
    -- Se pide ademas que el largo este plantado y la comba muerta: son los tres
    -- cortes de lo mismo -- radio, angulo y forma -- y hasta que no se cumplen
    -- los tres la cuerda sigue viva.
    if not finger and len == target and bow == 0 then
        local ax, ay = Halyard.anchor()
        local off = knot.x - ax
        local vel = (knot.x - knot.px) / (FIXED * omega())
        local amp = off * off + vel * vel
        if amp < SLEEP * SLEEP then
            rest()
        elseif amp < WALK * WALK then
            -- Lo mismo que el radio, pero en el angulo: el nudo anda hacia el
            -- plomo un pixel por cuadro, por su arco y sin velocidad.
            knot.x = knot.x + ((off > 0) and -1 or 1)
            local dx = knot.x - ax
            knot.y = ay + math.sqrt(math.max(0, len * len - dx * dx))
            knot.px, knot.py = knot.x, knot.y
        end
    end

    shape()
end

--==========================================================================
-- Tirar
--==========================================================================

-- Distancia del ancla PUESTA al dedo, en pixeles de arte. Puesta y no la que
-- entra: ver la cabecera.
local function pull(x, y)
    local ax, ay = Halyard.anchor()
    return Util.dist(ax, ay, x / Constants.ART, y / Constants.ART)
end

function Halyard.contains(x, y)
    if not nodes[NODES] then return false end
    local ax, ay = x / Constants.ART, y / Constants.ART
    for i = 1, NODES do
        local nx, ny = drawn(i)
        local r = (i == NODES) and KNOT_GRAB or GRAB
        if Util.dist(ax, ay, nx, ny) <= r then return true end
    end
    return false
end

function Halyard.grab(x, y)
    grabbed = pull(x, y) - len
    finger = { x = x / Constants.ART, y = y / Constants.ART }
end

function Halyard.haul(x, y)
    if not finger then return end
    finger.x, finger.y = x / Constants.ART, y / Constants.ART
    len = Util.clamp(pull(x, y) - grabbed, MIN_LEN, maxLen())
end

-- Suelta la cuerda y devuelve el trapo que se ha pedido, o nil si el tiron no
-- llego. Devuelve el trapo QUE QUIERE DEJAR y no "el otro": tirar dos veces
-- hacia el mismo lado no puede alternarlo.
function Halyard.drop(state)
    if not finger then return nil end
    local mark, trim = order(state.trim)
    local reached = len >= mark
    grabbed, finger = nil, nil
    lenVel = 0
    return reached and trim or nil
end

--==========================================================================
-- Dibujo
--==========================================================================

-- Un tramo de cuerda de punta a punta, avanzando de pixel en pixel con un
-- sello, como las cabillas de la rueda: a este grosor no deja huecos ni en los
-- codos.
local function strand(size, color)
    love.graphics.setColor(color)
    local x0, y0 = drawn(1)
    for i = 2, NODES do
        local x1, y1 = drawn(i)
        local steps = math.max(1, math.ceil(Util.dist(x0, y0, x1, y1)))
        for s = 0, steps do
            local t = s / steps
            love.graphics.rectangle("fill",
                math.floor(Util.lerp(x0, x1, t) - size / 2),
                math.floor(Util.lerp(y0, y1, t) - size / 2), size, size)
        end
        x0, y0 = x1, y1
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- La torcida, contada desde el nudo hacia el ancla (ver la cabecera sobre por
-- que desde ahi). Va al canto de babor de la cuerda, que es de donde viene la
-- luz en el resto del arte.
local function twist()
    love.graphics.setColor(Palette.sailShade)
    local run, mark = 0, TWIST
    local x0, y0 = drawn(NODES)
    for i = NODES - 1, 1, -1 do
        local x1, y1 = drawn(i)
        local d = Util.dist(x0, y0, x1, y1)
        if d > 0.001 then
            while run + d >= mark do
                local t = (mark - run) / d
                love.graphics.rectangle("fill",
                    math.floor(Util.lerp(x0, x1, t) - ROPE / 2),
                    math.floor(Util.lerp(y0, y1, t) - ROPE / 2), 1, 1)
                mark = mark + TWIST
            end
            run = run + d
        end
        x0, y0 = x1, y1
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Disco lleno, fila a fila: una tira por fila es un rectangulo.
--
-- El disco es PAR -- diametro 2r, con el centro en el cruce de cuatro pixeles
-- y no en uno -- y eso no es un capricho: la cuerda tiene grosor par, asi que
-- la banda que se pinta cae a caballo de `cx` y su eje esta en `cx - 0.5`. Un
-- disco impar (2r+1) se centra por fuerza en un pixel entero, o sea medio
-- pixel a estribor del eje de la cuerda, y ahi no hay medios pixeles: el nudo
-- volaba tres columnas por babor y CUATRO por estribor, y se veia colgado de
-- lado. Par, los dos comparten eje exacto.
--
-- El semiancho se REDONDEA en vez de truncarse. Truncando, un disco par pierde
-- una columna por lado y con el alto intacto sale huevo en vez de nudo.
local function blob(cx, cy, r, color)
    love.graphics.setColor(color)
    for dy = -r, r - 1 do
        local d = dy + 0.5
        local w = math.floor(math.sqrt(math.max(0, r * r - d * d)) + 0.5)
        if w > 0 then
            love.graphics.rectangle("fill", cx - w, cy + dy, 2 * w, 1)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Halyard.draw(state)
    love.graphics.push()
    love.graphics.scale(Constants.ART, Constants.ART)

    -- TODO el contorno antes que TODO el color: pintando cada tramo entero de
    -- una vez, el siguiente le comia un pixel con su propio contorno en cada
    -- codo de la cuerda.
    strand(ROPE + 2, Palette.ink)
    strand(ROPE, Palette.rope)
    twist()

    -- El nudo. Va en ORO cuando soltar ya cambiaria el trapo: es la unica
    -- lectura que lleva la driza, y cae justo bajo el dedo, que es donde se
    -- esta mirando.
    local kx, ky = drawn(NODES)
    kx, ky = math.floor(kx), math.floor(ky)
    blob(kx, ky, KNOT + 1, Palette.ink)
    blob(kx, ky, KNOT, ready(state.trim) and Palette.gold or Palette.rope)
    -- La luz arriba y a babor, como en el resto del arte. Un disco par de
    -- radio 1 son cuatro pixeles, que es justo el cuadrante que se quiere.
    blob(kx - 1, ky - 1, 1, Palette.sailShade)

    love.graphics.pop()
end

return Halyard
