-- El redal: pescar a mano.
--
-- Es el tercer mando que se usa NAVEGANDO, y sale del mismo reparto que los
-- otros dos (`src/helm.lua` y `src/halyard.lua`): tocar el puesto de Redes en
-- cubierta larga el redal por la esquina inferior de estribor y deja la hoja
-- del puesto para el segundo toque. Los tres se excluyen, asi que la rueda y
-- el redal pueden nacer de la misma esquina sin pisarse nunca.
--
-- La diferencia con los otros dos es que estos NO piden nada a la simulacion:
-- la rueda ordena rumbo y la driza pide trapo, pero aqui no hay estado que
-- cambiar mientras se pelea. Por eso la pelea entera vive en este modulo y no
-- en el estado guardado, y por eso `Reel.update` devuelve un SUCESO -- pez
-- cobrado, pez perdido, linea rota -- que la travesia traduce a
-- `World.landFish` o a una linea de bitacora. Nada de esto se guarda: cerrar
-- la app con un pez enganchado es perderlo, igual que soltar el movil con la
-- cana en la mano.
--
-- LA CANA ES LA REGLA DEL SEDAL. Del carrete sale una cana hacia babor, y
-- sobre ella corre la silueta del pez: a babor del todo es el pez con todo el
-- sedal fuera -- se va -- y a estribor del todo es el pez en la borda,
-- cobrado. No es una barra de interfaz con otro dibujo: es la lectura directa
-- de cuanto sedal queda por recoger, que es lo unico que hay que saber
-- mientras se pelea, y cae donde se esta mirando, que es la mano que rueda.
--
-- SE RUEDA EL CARRETE, no se aprieta un boton, y de ahi sale la pelea entera:
--
--   * El pez tira SIEMPRE, se toque o no. El carrete tiene una velocidad de
--     giro y su reposo no es cero sino `-run`: la carrera del pez. Dejarlo
--     solo es verlo desenrollarse.
--   * Con el dedo encima manda el dedo, como el nudo de la driza: el carrete
--     gira lo que ha corrido el dedo MENOS lo que el pez se lleva igual. Asi
--     que agarrar y quedarse quieto no es una pausa -- se sigue perdiendo
--     sedal -- y hay que rodar de verdad para ganar terreno.
--   * Al soltar, el carrete se queda con el giro que llevaba y se relaja
--     hacia la carrera del pez. Soltar rodando fuerte da unas decimas de
--     regalo antes de que el pez mande otra vez, y soltar en seco deja el
--     carrete girando al reves: eso es "se escapa si el redal sigue rodando".
--   * Y volver a agarrarlo lo PARA, aunque no se ruede. Es palmear el
--     carrete, y es la herramienta con la que se corta una arrancada.
--
-- EL SEGMENTO ES LA REGLA DEL JUEGO. Sobre la cana hay una banda clara que
-- cambia de sitio cada pocos segundos: es donde el pez aguanta que se tire de
-- el. Rodar con el pez DENTRO no cuesta nada; rodar con el pez FUERA tensa la
-- linea, y la linea llena se rompe. De ahi salen las dos maniobras que pide
-- el mando, y son las dos que se piden de una cana de verdad: ATRAER cuando
-- el pez esta en la banda, y DEJARLO IR -- soltar el carrete, que el pez
-- corra hacia babor -- cuando la banda se ha ido por detras de el. Sin la
-- segunda, pescar seria rodar sin parar.
--
-- LA TENSION NO TIENE BARRA: LA CANA SE COMBA. Es el indicador que ya existe
-- en el mundo real y el unico que no hay que aprenderse, y ademas cae encima
-- del pez, que es donde se esta mirando. Cuando pasa de DANGER el sedal se
-- pone rojo, que es lo unico que se pinta de mas. La misma idea que el nudo
-- de oro de la driza: nada de texto donde el propio trasto puede decirlo.
--
-- Y EL ORO DICE LO MISMO QUE EN TODO EL JUEGO -- "esto es lo que hay que
-- hacer" -- en dos sitios: el pez se pinta en oro mientras esta dentro de la
-- banda (rodar ahora es gratis) y la manivela se pone de oro mientras hay un
-- pez enganchado (rodar ahora hace algo). Con la caña en reposo no hay ni una
-- cosa ni la otra, y eso es parte del mensaje.
--
-- EN REPOSO ESTA INMOVIL, que es la leccion que costo la driza. Sin pez no se
-- integra nada: el sedal cuelga con una comba fija, la cana va recta y el
-- carrete no gira. Lo unico que se mueve entre pique y pique es un contador
-- que no se ve. Y todo lo que se atenua -- la comba del sedal, el tiron del
-- pique -- llega a su valor EXACTO en vez de asintoticamente, porque a cinco
-- pixeles de pantalla por pixel de arte una cola exponencial no es suave, es
-- un parpadeo.
--
-- ENTRA SUBIENDO POR LA BORDA, desde debajo del canto de abajo, con la misma
-- curva y los mismos tiempos que la rueda y la driza; y el carrete rueda lo
-- que le toca por subir esa distancia, como la rueda del timon, para que se
-- lea como un trasto que sube y no como un panel que desliza. La animacion es
-- SOLO dibujo: el angulo del dedo se mide siempre desde el carrete PUESTO,
-- porque midiendolo desde el que sube el propio deslizamiento rodaria el
-- carrete sin que el dedo se moviera y el pez vendria solo.
--
-- MIENTRAS ESTA FUERA, EL BAJO DE LA PANTALLA ES SUYO: la travesia se guarda
-- las dos columnas de botones y la bitacora. La rueda solo se lleva su
-- columna porque cabe en su esquina; el redal cruza de banda a banda -- el
-- carrete a estribor, la cana hasta babor y el sedal cayendo al agua -- asi
-- que debajo no puede quedar nada. Y se pierde poco: la bitacora se lee de
-- reojo cuando no pasa nada, y mientras hay un pez en la cana lo que pasa
-- esta en la cana.
--
-- Se dibuja con rectangulos de 1x1 dentro de la escala de arte, que es la
-- salida legal a la regla de "nada girado" (ver src/sea.lua): la cana se
-- comba y el carrete da vueltas, pero no hay un solo sprite que rotar y su
-- pixel mide lo mismo que el del casco. Cada pieza se pinta dos veces,
-- engordada en `Palette.ink` y luego en su color, que es de donde sale el
-- contorno negro de 1px de los sprites de assets/.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')
local Ship      = require('src.ship')
local UI        = require('src.ui')

local Reel = {}

-- Radio del carrete en pixeles de ARTE, no virtuales: es del mismo grano que
-- el barco, asi que si el lienzo se estrecha y ART baja, encoge con el barco
-- en vez de descuadrarse. Con ART=5 son 80 px virtuales de rueda, que es lo
-- que hace falta para poder rodarla con el pulgar sin apuntar.
Reel.RADIUS = 16

local MARGIN = 10       -- aire entre el carrete y los margenes seguros
local RISE   = 40       -- cuanto sube la punta de la cana sobre el carrete
local HUB    = 4        -- radio de la nuez del carrete
local SPOKES = 6        -- radios del carrete: los que hacen que se vea girar
local CRANK  = 3        -- radio del puno de la manivela

-- Grosor de la cana en la punta y en el puno. Una cana que no adelgaza se lee
-- como un palo, igual que la driza sin torcida.
local ROD_TIP, ROD_BUTT = 1, 3

--== La pelea ==============================================================

-- Donde aparece el pez al picar: pasada la mitad de la cana hacia estribor.
-- No en medio: al picar hay que reaccionar, y desde la mitad justa los cinco
-- segundos de reaccion salian tres.
local START = 0.55

-- Cuanta cana recoge un radian de carrete. 0,06 son unas dos vueltas y media
-- de manivela para toda la cana: bastante para que rodar se sienta trabajo,
-- poco para que una arrancada no sea irrecuperable.
local POS_PER_RAD = 0.06

-- La carrera del pez, en radianes de carrete por segundo: es el reposo del
-- carrete, no el cero. 1,67 son diez segundos de cana entera si no se toca.
local RUN = 2.05

-- Lo rapido que el carrete suelto se relaja hacia la carrera del pez. Es lo
-- que deja que soltar rodando fuerte regale unas decimas antes de que el pez
-- mande otra vez; subirlo mata ese regalo y con el la sensacion de inercia.
local FRICTION = 3.0

-- El brio: la arrancada del pez, que va y viene. Sale de `Util.hash01` con el
-- tiempo de travesia, interpolado suave entre un tramo y el siguiente, asi
-- que no hay nada aleatorio que guardar y el pez no da saltos de fuerza.
local BRIO, BRIO_EVERY = 0.35, 1.7

-- Cada cuanto cambia de sitio la banda y lo que tarda en llegar. Se DESLIZA y
-- no se teletransporta, porque a este grano un salto de veinte pixeles no se
-- lee como que la banda se ha movido sino como que hay otra banda. Y llega
-- EXACTA, por interpolacion con un parametro acotado, en vez de acercarse
-- para siempre: una banda que deriva medio pixel repinta su sello entero.
-- La banda se mueve mas a menudo desde que el pez cuenta por su cuerpo: lo que
-- se perdio de precision se recupera en RITMO, que ademas es mejor sitio para
-- ponerlo. Apurar el canto de la banda era una pelea de pixeles; llegar a la
-- banda antes de que se vaya es una pelea de tiempo, y esa se juega mirando.
local SEG_EVERY, SEG_SLIDE = 2.2, 0.20

-- Medio ancho de la banda: fijo mas lo que da el puesto de Redes. Es la unica
-- forma en la que mejorar Redes se nota en el mando, y es la que toca: un
-- buen pescador no tira mas fuerte, sabe cuando el pez aguanta.
local SEG_HALF, SEG_HALF_PER = 0.035, 0.006

-- LO ANCHO QUE ES EL PEZ, en pixeles de arte, y va aqui repetido a proposito:
-- tiene que ser el ancho de la silueta de `FISH`, que se dibuja mas abajo, y
-- si una cambia sin la otra la prueba lo canta (mide el pez dibujado y compara).
--
-- Hace falta porque el pez CUENTA COMO DENTRO DE LA BANDA CUANDO SU CUERPO LA
-- TOCA, y no cuando su centro cae dentro. Medir por el centro era una mentira
-- de las que este juego no se permite: el pez mide once pixeles de arte y la
-- banda veinte, asi que con el centro justo en el canto de la banda el pez se
-- ve METIDO EN ELLA hasta la mitad -- y sin embargo no se ponia de oro y la
-- cana se tensaba. Cinco pixeles y medio de "parece que si y el juego dice que
-- no" a cada lado, que es exactamente el sitio donde se pelea.
--
-- Contando por el cuerpo, "el pez esta en la banda" quiere decir lo que
-- cualquiera diria mirandolo. Sale mas indulgente, y eso se paga donde toca
-- (ver SEG_EVERY) y no dejando el mando diciendo una cosa y haciendo otra.
local FISH_W = 11

-- EL FRENO DEL CARRETE, y no es un adorno: es lo que evita que el mando se
-- gane rodando como un poseso, que es la estrategia degenerada de todo lo que
-- se rueda. Un carrete de verdad lleva freno, y pasado el freno la bobina
-- RESBALA: se sigue moviendo la manivela y el pez no viene mas rapido, solo
-- se tensa la linea. Aqui igual -- MAX_GAIN es lo mas que se le puede ganar
-- por segundo a la carrera del pez -- y de eso salen dos cosas de balde:
--
--   * pasarse no adelanta nada y ademas rompe, asi que barrer el pulgar sin
--     mirar pierde SIEMPRE, y pierde ensenando por que (la cana se comba y el
--     sedal se pone rojo antes de romperse);
--   * y se VE resbalar, sin dibujar nada nuevo: el carrete gira `spin`, que
--     es lo que da el freno, asi que pasado el tope la manivela se queda
--     atras del dedo. Eso es exactamente lo que hace un freno resbalando.
--
-- Sin esto la cuenta salia justa por los dos lados -- rodar acerca el pez y a
-- la vez tensa la linea -- y la prueba decia que ganaba rodar: ocho peces
-- cobrados de ocho a base de barrer.
local MAX_GAIN = 2.5

-- Tension que se gana por segundo rodando fuera de la banda a la velocidad de
-- la propia carrera del pez, la que se suelta por segundo el resto del
-- tiempo, y la que anade cada radian por segundo que el freno esta
-- resbalando. FURY acota lo primero para que la cana llegue a combarse antes
-- de que la linea se rompa, o sea para que haya aviso; el resbale no lo
-- necesita, porque solo se llega a el pasandose a proposito.
local TENSE, SLACKEN, FURY, SLIP = 0.60, 0.30, 3, 0.25

-- A partir de aqui el sedal se pinta en rojo. Va antes de la mitad de camino
-- a proposito: el aviso tiene que llegar con tiempo de soltar.
local DANGER = 0.62

-- LA CEDIDA: lo que se lleva cortar una arrancada a tiempo.
--
-- Sin esto la pelea no tenia jugada buena, solo jugada correcta: rodar cuando
-- toca y soltar cuando toca, siempre al mismo precio. Ahora si el pez entra en
-- la banda HUYENDO -- o sea cortandole una carrera, no cogiendolo parado -- y
-- se recoge de verdad en las decimas siguientes, el pez CEDE unos segundos:
-- tira mucho menos y el freno aguanta mas, asi que se le gana un buen trecho.
-- Es lo que pasa de verdad cuando un pez deja de pelear, y es lo que convierte
-- estar atento en algo que se cobra.
--
-- REACT es la ventana desde que entra, YIELD lo que dura la cedida, YIELD_RUN
-- lo que le queda de carrera al empezar a ceder y YIELD_HAUL cuanto mas
-- aguanta el freno mientras cede. La cedida se va DESVANECIENDO en vez de
-- apagarse de golpe: el pez se recupera, no se le acaba la pila.
local REACT, YIELD = 0.35, 1.4
local YIELD_RUN, YIELD_HAUL = 0.50, 1.30

-- Entre pique y pique. El minimo no es cero porque un pique inmediato al
-- sacar el redal se lee como que el juego lo estaba esperando.
local BITE_MIN, BITE_MAX = 4, 12

-- Lo que da un pez cobrado, en pescado, mas lo que anade la potencia de
-- Redes. Entra por `stow` como todo lo demas, asi que con la bodega llena se
-- pierde lo que no cabe -- pero se sigue picando, y la bitacora lo dice (ver
-- mas abajo, sobre `Reel.idle`).
local FISH_BASE, FISH_PER = 6, 2

-- Cuanto se comba la cana con la linea a tope, y el tiron extra del pique, en
-- pixeles de arte. El tiron decae LINEAL y llega a cero exacto: es el unico
-- momento en el que la cana se mueve sola y tiene que acabar quieta.
local BEND, JOLT, JOLT_TIME = 8, 5, 0.3

-- Comba del sedal flojo, y lo rapido que pasa de flojo a tenso. El corte esta
-- calculado para que salte a su valor exacto antes de que se pueda ver medio
-- pixel de diferencia.
local SAG, SLACK_EASE = 10, 9

-- EL CORCHO, y es el arreglo de un fallo de verdad: con la cana fuera y sin
-- pique la pantalla se quedaba EXACTAMENTE igual cuadro tras cuadro, y ocho
-- segundos de eso no se leen como esperar, se leen como que el juego se ha
-- colgado. Es la vuelta de la regla de la driza, pero al reves: lo que alli
-- era un fallo -- una cosa en reposo temblando -- aqui lo es no moverse, y la
-- diferencia no es de gusto. La driza cuelga QUIETA porque una cuerda colgada
-- esta quieta; un corcho en el agua no lo esta NUNCA, y uno que se para esta
-- roto. Asi que el aparejo sigue inmovil hasta el ultimo pixel -- cana,
-- carrete y sedal no se mueven solos -- y lo unico que vive es el corcho, que
-- es ademas lo unico que esta en el agua.
--
-- Y hace el otro trabajo, el que la vibracion no puede hacer en escritorio: al
-- picar el corcho SE HUNDE y desaparece. Es la imagen de un pique en cualquier
-- sitio del mundo y no hay que explicarla, asi que el pique se lee aunque el
-- movil no vibre y aunque se este mirando la otra punta de la pantalla.
--
-- DROP es lo que cae el sedal de la punta al corcho, BOB el vaiven en pixeles
-- de arte y BOB_EVERY su periodo. El vaiven es de dos pixeles y lento a
-- proposito: mas rapido vuelve a ser temblor, que es lo que no queremos.
local DROP, BOB, BOB_EVERY, FLOAT = 42, 2, 2.2, 3

-- Lo que se aparta el aparejo para quedarse debajo del canto de abajo, y los
-- mismos tiempos que la rueda y la driza: sale en 0,24 s y se guarda en 0,16.
local SLIDE = 70
local ENTER, EXIT = 0.24, 0.16

-- Paso fijo con acumulador, como la driza y por lo mismo: asi el carrete
-- guarda de un paso al siguiente el giro que le imprime el dedo, y al soltar
-- sigue rodando en vez de quedarse muerto.
local FIXED, STEPS = 1 / 60, 4

--== Estado del modulo =====================================================
--
-- Nada de esto va al estado guardado (ver la cabecera). `Reel.reset` lo deja
-- todo como al entrar en la travesia.

local anim, accum = 0, 0
local wait = nil              -- lo que falta para el pique, o nil si hay que sortearlo
local hooked = false
local pos, spin, angle = 0, 0, 0
local tension, jolt = 0, 0
local slack = 1               -- 1 = sedal flojo, 0 = tenso
local seg, segFrom, segTo, segT, segKey = START, START, START, 1, nil
local inband, react, yield = false, 0, 0   -- la cedida (ver REACT/YIELD)
local finger, crank = nil, 0  -- angulo del dedo y radianes que ha rodado sin gastar
local pending = nil           -- suceso que devolver en el update de este cuadro

--==========================================================================
-- Geometria
--==========================================================================

-- Eje del carrete, en pixeles de arte: la esquina inferior de estribor del
-- area segura, con su aire.
function Reel.center()
    return math.floor((Constants.GAME_WIDTH - Constants.SAFE_RIGHT) / Constants.ART)
             - Reel.RADIUS - MARGIN,
           math.floor((Constants.GAME_HEIGHT - Constants.SAFE_BOTTOM) / Constants.ART)
             - Reel.RADIUS - MARGIN
end

-- Punta de la cana: hacia babor y por encima del carrete, que es como se
-- sujeta una cana desde la borda de estribor.
function Reel.tip()
    local cx, cy = Reel.center()
    return math.floor(Constants.SAFE_LEFT / Constants.ART) + MARGIN, cy - RISE
end

-- Eje de la cana: punta, direccion unitaria hacia el puno y largo.
local function axis()
    local tx, ty = Reel.tip()
    local cx, cy = Reel.center()
    local dx, dy = cx - tx, cy - ty
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1 then return tx, ty, 1, 0, 1 end
    return tx, ty, dx / d, dy / d, d
end

-- Lo que recorre el pez: de la punta al canto del carrete, no a su eje. Un
-- pez cobrado esta en la boca del carrete; debajo de el ya no se veria.
local function track()
    local _, _, _, _, d = axis()
    return math.max(1, d - Reel.RADIUS - 3)
end

-- Un punto de la cana a `s` pixeles de la punta, con la comba y con lo que le
-- falte por subir.
--
-- LA COMBA ES LA DE UNA VIGA EMPOTRADA, no la de una cuerda, y la diferencia
-- se ve entera. Fue `sin(pi*t)` -- un arco con cero en los dos extremos -- y
-- eso comba el CENTRO de la cana dejando la punta clavada en el eje, que es lo
-- que hace un cabo tendido entre dos puntos, no una cana. Una cana esta
-- empotrada en el carrete y libre por la punta: el pez tira de la punta, la
-- punta es la que baja y el arranque sale RECTO del puno porque ahi la sujeta
-- la mano.
--
-- Asi que la flecha es la del voladizo con la carga en el extremo,
-- normalizada a 1 en la punta:
--
--     f(u) = u^2 * (3 - u) / 2,   u = 0 en el puno, 1 en la punta
--
-- que sale con tangente horizontal en el empotramiento (f'(0) = 0) y va
-- ganando pendiente hasta la punta. Eso es lo que se lee como una cana
-- doblandose y aguantando: la punta intenta bajar y la cana se resiste.
local function rodAt(s, bow, lift)
    local tx, ty, ux, uy, d = axis()
    local u = 1 - Util.clamp(s / d, 0, 1)
    local arch = u * u * (3 - u) / 2 * bow
    return tx + ux * s - uy * arch, ty + uy * s + ux * arch + lift
end

-- Grosor de la cana en ese punto.
local function rodSize(s)
    local _, _, _, _, d = axis()
    return math.floor(Util.lerp(ROD_TIP, ROD_BUTT, Util.clamp(s / d, 0, 1)) + 0.5)
end

--==========================================================================
-- Entrada y salida
--==========================================================================

local function settled()
    local u = 1 - anim
    return 1 - u * u * u
end

function Reel.showing()
    return anim > 0
end

function Reel.reset()
    anim, accum = 0, 0
    wait, hooked, pending = nil, false, nil
    pos, spin, angle = 0, 0, 0
    tension, jolt, slack = 0, 0, 1
    seg, segFrom, segTo, segT, segKey = START, START, START, 1, nil
    inband, react, yield = false, 0, 0
    finger, crank = nil, 0
end

--==========================================================================
-- La pelea
--==========================================================================

-- Cuanto aprieta el pez ahora mismo. Interpolado suave entre dos hashes
-- consecutivos: el pez arranca y afloja sin que la fuerza salte de un cuadro
-- al siguiente, y sin guardar nada.
local function brio(state)
    local k = state.time / BRIO_EVERY
    local i = math.floor(k)
    local t = k - i
    local a = Util.hash01(state.seed, i, 41)
    local b = Util.hash01(state.seed, i + 1, 41)
    return 1 - BRIO + 2 * BRIO * Util.lerp(a, b, t * t * (3 - 2 * t))
end

-- La carrera del pez en radianes por segundo. Mejor puesto de Redes, pez
-- menos brioso: es el pescador el que sabe aguantarlo, no el pez el que se
-- cansa.
local function runRate(state)
    return RUN * brio(state) / (1 + 0.10 * Ship.power(state, "nets"))
end

function Reel.segHalf(state)
    return math.min(0.28, SEG_HALF + SEG_HALF_PER * Ship.power(state, "nets"))
end

-- Si el pez esta EN la banda, contando por su cuerpo y no por su centro (ver
-- FISH_W). Es la misma cuenta que decide el oro y la que decide si tensa, asi
-- que lo que se ve y lo que pasa no pueden separarse.
local function inBand(state)
    return math.abs(pos - seg) <= Reel.segHalf(state) + (FISH_W / 2) / track()
end

-- POR QUE no se puede pescar ahora mismo, o nil si se puede. Devuelve el
-- motivo y no un booleano porque el motivo SE PINTA: la cana se larga igual --
-- guardarla sin dejar sacarla seria un mando que a veces no existe -- pero
-- entonces tiene que decir por que no pasa nada.
--
-- Sin esto el mando estaba roto sin estarlo: amarrado se sacaba el redal, el
-- sedal caia al agua y ahi se quedaba para siempre, sin pique y sin una sola
-- pista. Y amarrado es justo donde empieza la partida, asi que era el estado
-- en el que mas facil era encontrarselo. Un mando que no puede funcionar tiene
-- que decirlo; callarse es lo mismo que estar averiado.
function Reel.idle(state)
    -- Amarrado no corre la singladura (ver Ship.rates): tampoco la cana.
    if state.docked then return "Amarrado no se pesca" end
    return nil
end

-- Con la BODEGA LLENA se pesca igual, y es una decision tomada a proposito
-- contra el argumento contrario. El argumento era que cobrar un pez que no
-- cabe es cobrar para nada, asi que mejor que no picara; pero la bodega llena
-- es justo el estado en el que se vuelve despues de una ausencia larga, o sea
-- que la pesca a mano se apagaba sola precisamente cuando mas rato se lleva
-- mirando la pantalla. Pelear y que no quepa es peor negocio que no pelear,
-- pero es el jugador quien lo elige; lo que no puede ser es que el mando se
-- apague sin decir nada. Asi que pica, y `World.landFish` dice en la bitacora
-- lo que no cupo.

local function fishing(state)
    return Reel.idle(state) == nil
end

-- La banda cambia de sitio por tramos de tiempo, y el tramo sale del reloj de
-- la travesia: sin semilla que guardar y sin depender de cuantos cuadros se
-- hayan pintado.
local function band(state, dt)
    local k = math.floor(state.time / SEG_EVERY)
    if k ~= segKey then
        local half = Reel.segHalf(state)
        segKey = k
        segFrom, segT = seg, 0
        segTo = Util.lerp(half, 1 - half, Util.hash01(state.seed, k, 57))
    end
    segT = math.min(1, segT + dt / SEG_SLIDE)
    local e = segT * segT * (3 - 2 * segT)
    seg = Util.lerp(segFrom, segTo, e)
end

local function hook(state)
    hooked = true
    pos, spin, tension = START, 0, 0
    jolt, wait = 1, nil
    segKey = nil                 -- la banda se recoloca con el pique
    band(state, 0)
    -- El movil vibra. Es el unico aviso que sale de la pantalla, y hace falta:
    -- el pique es lo unico de este juego que empieza sin que lo empiece el
    -- jugador, y sin el se pierde mirando otra cosa.
    if love.system and love.system.vibrate then love.system.vibrate(0.12) end
end

local function unhook(kind, fish)
    hooked = false
    spin, tension, jolt = 0, 0, 0
    wait = nil
    pending = { kind = kind, fish = fish }
end

-- Un paso de la pelea. El carrete es lo unico con inercia; todo lo demas
-- (banda, tension, comba) se deriva de donde esta el pez.
-- Lo que le queda de pelea al pez mientras cede: YIELD_RUN al empezar y 1 al
-- recuperarse del todo. Se desvanece en vez de apagarse de golpe.
local function ease()
    if yield <= 0 then return 1 end
    return 1 - (1 - YIELD_RUN) * (yield / YIELD)
end

local function step(state, rate)
    local base = runRate(state)
    local give = ease()
    local r = base * give
    local slip = 0

    if finger then
        -- El dedo manda, y el pez tira igual: rodar es ganarle a la carrera,
        -- no empezar de cero. Quedarse quieto con el dedo encima pierde sedal.
        -- Y pasado el freno, la bobina resbala: lo que sobra no viene en pez,
        -- se queda en la linea.
        -- Mientras el pez cede el freno aguanta mas, porque no hay nada
        -- tirando del otro lado: es lo que hace que la cedida se NOTE en
        -- recorrido y no solo en que el pez pese menos.
        local cap = MAX_GAIN * (1 + (YIELD_HAUL - 1) * (1 - give) / (1 - YIELD_RUN))
        local drive = rate - r
        if drive > cap then
            slip = drive - cap
            drive = cap
        end
        spin = drive
    else
        -- Suelto, el carrete se relaja hacia la carrera del pez guardando lo
        -- que llevaba: de ahi salen el regalo al soltar rodando y el
        -- desenrolle al soltar en seco.
        spin = spin + (-r - spin) * math.min(1, FRICTION * FIXED)
    end

    angle = angle + spin * FIXED
    pos = pos + spin * POS_PER_RAD * FIXED

    -- Rodar con el pez fuera de la banda tensa; el resto del tiempo la linea
    -- se afloja sola. La tension se cuenta contra la carrera del pez para que
    -- un pez brioso no perdone mas que uno flojo.
    -- LA CEDIDA. El pez tiene que entrar en la banda HUYENDO -- cortandole una
    -- carrera y no cogiendolo parado -- y hay que recoger de verdad en las
    -- decimas siguientes. Premia estar mirando, que es justo lo que este mando
    -- pide y lo unico que no se cobraba.
    local inside = inBand(state)
    if inside and not inband and spin < 0 then react = REACT end
    inband = inside
    if react > 0 then
        react = react - FIXED
        if spin >= MAX_GAIN * 0.6 then react, yield = 0, YIELD end
    end
    if yield > 0 then yield = math.max(0, yield - FIXED) end

    -- La tension se normaliza contra la carrera ENTERA del pez y no contra la
    -- que le queda cediendo: si no, un pez rendido -- que tira menos -- haria
    -- que el mismo tiron contara como mas fuerza, que es justo al reves.
    if spin > 0 and not inside then
        tension = tension + math.min(FURY, spin / base) * TENSE * FIXED
    elseif slip <= 0 then
        tension = math.max(0, tension - SLACKEN * FIXED)
    end

    -- El freno resbalando tensa este dentro o fuera de la banda: la banda dice
    -- lo que el pez aguanta que se tire de el, no lo que aguanta el aparejo.
    if slip > 0 then tension = tension + slip / base * SLIP * FIXED end
end

--==========================================================================
-- Ciclo
--==========================================================================

-- Devuelve el suceso de este cuadro o nil: `{ kind = "catch", fish = n }`,
-- `{ kind = "gone" }` o `{ kind = "snap" }`. La travesia es la que sabe si el
-- redal esta pedido; aqui solo se recorre el camino hacia ese estado.
function Reel.update(dt, out, state)
    local s = dt / (out and ENTER or EXIT)
    anim = Util.clamp(anim + (out and s or -s), 0, 1)

    -- Guardar el redal con un pez enganchado es perderlo. No hay forma de
    -- pelear sin verlo, y dejarlo colgado esperando a que se vuelva a sacar
    -- seria un estado invisible.
    if not out then
        local ev = nil
        if hooked then unhook("gone"); ev, pending = pending, nil end
        wait, accum = nil, 0
        pos, spin, tension, jolt = 0, 0, 0, 0
        slack, crank, finger = 1, 0, nil
        return ev
    end

    -- Sin pez no se integra nada (ver la cabecera): solo corre el contador
    -- del pique, que no se ve.
    if not hooked then
        -- Sin pez el carrete gira LIBRE bajo el dedo y nada mas: no hay
        -- inercia que integrar, asi que soltado se queda exactamente donde se
        -- deje. Un mando que no responde al tocarlo se lee como roto, y esta
        -- es la forma barata de que responda sin inventarse un estado.
        angle = angle + crank
        crank = 0
        if anim >= 1 and fishing(state) then
            wait = (wait or (BITE_MIN + Util.hash01(state.seed, math.floor(state.time), 71)
                                        * (BITE_MAX - BITE_MIN))) - dt
            if wait <= 0 then hook(state) end
        elseif not fishing(state) then
            wait = nil
        end
    end

    if hooked then
        band(state, dt)

        -- Lo que ha rodado el dedo este cuadro, en radianes por segundo. Se
        -- mide contra el dt del cuadro y no contra el paso fijo: asi el total
        -- que gira el carrete es lo que ha corrido el dedo, tenga el cuadro
        -- los pasos que tenga.
        local rate = (dt > 0) and (crank / dt) or 0
        crank = 0

        accum = math.min(accum + dt, STEPS * FIXED)
        while accum >= FIXED do
            accum = accum - FIXED
            step(state, rate)
        end

        if pos >= 1 then
            unhook("catch", math.floor(FISH_BASE + FISH_PER * Ship.power(state, "nets")))
        elseif pos <= 0 then
            unhook("gone")
        elseif tension >= 1 then
            unhook("snap")
        end
    end

    -- El tiron del pique se va LINEAL y llega a cero exacto.
    if jolt > 0 then jolt = math.max(0, jolt - dt / JOLT_TIME) end

    -- Y el sedal pasa de flojo a tenso con el pez, saltando a su valor exacto
    -- en cuanto la diferencia baja de lo que se puede ver.
    local want = hooked and 0 or 1
    slack = slack + (want - slack) * math.min(1, SLACK_EASE * dt)
    if math.abs(want - slack) * SAG < 0.5 then slack = want end

    local ev = pending
    pending = nil
    return ev
end

--==========================================================================
-- Rodar
--==========================================================================

-- El carrete PUESTO, que es contra el que se miden los toques: la animacion
-- es solo dibujo (ver la cabecera).
local function centerVirtual()
    local cx, cy = Reel.center()
    return cx * Constants.ART, cy * Constants.ART
end

function Reel.contains(x, y)
    local cx, cy = centerVirtual()
    local dx, dy = x - cx, y - cy
    local r = (Reel.RADIUS + 6) * Constants.ART
    return dx * dx + dy * dy <= r * r
end

-- Angulo del dedo alrededor del eje, 0 = arriba y creciendo a estribor, igual
-- que la rueda del timon. La nuez es zona muerta: ahi el angulo salta con un
-- pixel de temblor.
local function fingerAngle(x, y)
    local cx, cy = centerVirtual()
    local dx, dy = x - cx, y - cy
    local dead = (HUB + 3) * Constants.ART
    if dx * dx + dy * dy < dead * dead then return nil end
    return math.atan2(dx, -dy)
end

-- Agarrar el carrete lo PARA aunque no se ruede: es palmearlo, y es la
-- herramienta con la que se corta una arrancada. Lo que sigue llevandose el
-- pez es su carrera, que no para nunca.
function Reel.grab(x, y)
    finger = fingerAngle(x, y)
    crank, spin = 0, 0
end

-- Rodar es RELATIVO, como la rueda: el carrete no salta a donde cae el dedo,
-- gira lo que el dedo ha corrido. A estribor (horario) se cobra sedal.
function Reel.roll(x, y)
    local a = fingerAngle(x, y)
    if not a then return end
    if not finger then finger = a; return end
    crank = crank + Util.angleDiff(finger, a)
    finger = a
end

function Reel.drop()
    finger, crank = nil, 0
end

--==========================================================================
-- Dibujo
--==========================================================================

-- Corona (o disco, con ri = 0) fila a fila: una tira por fila es un
-- rectangulo, y a este radio son treinta y tres en vez de ochocientos
-- pixeles sueltos.
local function ring(cx, cy, ro, ri, color)
    love.graphics.setColor(color)
    for dy = -math.floor(ro), math.floor(ro) do
        local outer = math.floor(math.sqrt(math.max(0, ro * ro - dy * dy)))
        local inner = 0
        if math.abs(dy) < ri then inner = math.ceil(math.sqrt(ri * ri - dy * dy)) end
        if outer >= inner then
            if inner == 0 then
                love.graphics.rectangle("fill", cx - outer, cy + dy, 2 * outer + 1, 1)
            else
                love.graphics.rectangle("fill", cx - outer, cy + dy, outer - inner + 1, 1)
                love.graphics.rectangle("fill", cx + inner, cy + dy, outer - inner + 1, 1)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Un tramo de cana de `s0` a `s1`, avanzando de pixel en pixel con un sello,
-- como las cabillas de la rueda y la cuerda de la driza: a este grosor no
-- deja huecos ni en la comba. `grow` es lo que engorda para el contorno.
local function alongRod(s0, s1, bow, lift, grow, color)
    love.graphics.setColor(color)
    local n = math.max(1, math.ceil(math.abs(s1 - s0)))
    for i = 0, n do
        local s = Util.lerp(s0, s1, i / n)
        local x, y = rodAt(s, bow, lift)
        local size = rodSize(s) + grow
        love.graphics.rectangle("fill", math.floor(x - size / 2),
                                math.floor(y - size / 2), size, size)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Un radio del carrete, con sello de pixel en pixel.
local function spoke(cx, cy, a, from, to, size, color)
    local sn, cs = math.sin(a), math.cos(a)
    love.graphics.setColor(color)
    for r = from, to do
        love.graphics.rectangle("fill", math.floor(cx + sn * r - size / 2),
                                math.floor(cy - cs * r - size / 2), size, size)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- El pez, con el morro a babor -- huye -- y la cola a estribor. Va a mano y
-- no generado: once por cinco pixeles de arte es un tamano en el que una
-- elipse con cola sale como una mancha, y un pez tiene que leerse como un pez
-- a la primera. Es la unica silueta del mando, asi que no hay ninguna otra
-- que casar con ella.
local FISH = {
    "...####..##",
    ".########.#",
    "###########",
    ".########.#",
    "...####..##",
}

-- `turned` pinta el pez VUELTO, con el morro a estribor. Es como se ve que ha
-- cedido: un pez que deja de pelear deja de encarar el mar y viene de cabeza
-- al barco. No es rotar nada -- se invierten las columnas de la silueta -- asi
-- que sigue dentro de la regla de "nada girado", y es la unica senal de la
-- cedida: ni color nuevo ni numero, la postura del propio pez.
local function silhouette(cx, cy, color, turned)
    love.graphics.setColor(color)
    local w = #FISH[1]
    for row = 1, #FISH do
        local line = FISH[row]
        local y = cy + row - 3
        local run = nil
        for col = 1, w + 1 do
            local on = line:sub(col, col) == "#"
            if on and not run then run = col end
            if not on and run then
                local x = turned and (cx + w + 1 - col - w / 2)
                                 or (cx + run - 1 - w / 2)
                love.graphics.rectangle("fill", math.floor(x), y, col - run, 1)
                run = nil
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Reel.draw(state)
    local put = settled()
    local lift = math.floor((1 - put) * SLIDE + 0.5)   -- pixeles ENTEROS de arte
    local len = track()
    local _, _, _, _, rod = axis()
    local bow = BEND * tension + JOLT * jolt
    local half = Reel.segHalf(state)

    love.graphics.push()
    love.graphics.scale(Constants.ART, Constants.ART)

    -- El sedal y el corcho. Donde acaba el sedal es lo que cuenta el estado
    -- entero del aparejo, y son tres:
    --
    --   sin pescar   el corcho cuelga de la punta, FUERA del agua, y quieto:
    --                es como se ve una cana que no esta pescando.
    --   esperando    el corcho esta en el agua y cabecea. Es lo unico que se
    --                mueve (ver DROP/BOB), y es lo que dice que el aparejo
    --                esta vivo mientras no pasa nada.
    --   con pez      el corcho SE HA HUNDIDO -- no se pinta -- y el sedal se
    --                va tenso al agua. Es la imagen de un pique en cualquier
    --                sitio del mundo, y es la que hace que el pique se lea sin
    --                vibracion, o sea tambien en escritorio.
    local reason = Reel.idle(state)
    local tx, ty = rodAt(0, bow, lift)
    local ex, ey
    if hooked then
        ex, ey = tx - 14, Constants.ART_H + 6
    elseif reason then
        ex, ey = tx - 2, ty + 8
    else
        local wave = math.floor(math.sin(state.time * Util.TAU / BOB_EVERY) * BOB + 0.5)
        ex, ey = tx - 5, ty + DROP + wave
    end

    -- La comba se reparte segun lo que cuelgue: con el corcho recogido bajo la
    -- punta, diez pixeles de comba en ocho de caida seria un lazo.
    local sag = SAG * slack * math.min(1, math.max(0, ey - ty) / DROP)
    love.graphics.setColor((tension > DANGER) and Palette.red or Palette.sailShade)
    do
        local n = math.max(1, math.ceil(Util.dist(tx, ty, ex, ey)))
        for i = 0, n do
            local t = i / n
            local dip = math.sin(math.pi * t) * sag
            love.graphics.rectangle("fill", math.floor(Util.lerp(tx, ex, t)),
                                    math.floor(Util.lerp(ty, ey, t) + dip), 1, 1)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)

    if not hooked then
        local fx, fy = math.floor(ex), math.floor(ey)
        ring(fx, fy, FLOAT + 1, 0, Palette.ink)
        ring(fx, fy, FLOAT, 0, Palette.sand)
        -- La luz arriba y a babor, como en el resto del arte. Va en `sail` y
        -- NO en blanco aunque el blanco pegara mejor: el blanco es el color
        -- del pez en este mando, y un corcho con una mota blanca a media
        -- pantalla es una silueta de pez de un pixel. Lo canto la prueba --
        -- que busca el pez por color -- pero el ojo se come el mismo error.
        ring(fx - 1, fy - 1, 1, 0, Palette.sail)
    end

    -- La cana: TODO el contorno antes que TODA la madera, porque pintando
    -- cada tramo entero de una vez el siguiente le comia un pixel con su
    -- propio contorno.
    alongRod(0, rod, bow, lift, 2, Palette.ink)
    alongRod(0, rod, bow, lift, 0, Palette.wood)

    if hooked then
        -- La banda: donde el pez aguanta que se tire de el. Va del color de
        -- la espuma y sin contorno propio, para que se lea como un tramo de
        -- la cana y no como una pieza puesta encima.
        alongRod(Util.clamp(seg - half, 0, 1) * len,
                 Util.clamp(seg + half, 0, 1) * len, bow, lift, 0, Palette.foam)
    end

    -- El carrete. Sube con el aparejo y RUEDA lo que le toca por subir esa
    -- distancia, como la rueda del timon entra rodando: asi sube como un
    -- trasto y no como un panel.
    local cx, cy = Reel.center()
    cy = cy + lift
    local w = angle - (1 - put) * SLIDE / Reel.RADIUS

    ring(cx, cy, Reel.RADIUS + 1, Reel.RADIUS - 4, Palette.ink)
    ring(cx, cy, Reel.RADIUS, Reel.RADIUS - 3, Palette.wood)
    ring(cx, cy, Reel.RADIUS, Reel.RADIUS - 1.4, Palette.woodLite)

    -- Radios: todos los contornos antes que todas las maderas, por lo mismo
    -- que las cabillas de la rueda.
    local spokeAngles = {}
    for i = 1, SPOKES do
        spokeAngles[i] = w + (i - 1) * Util.TAU / SPOKES
        spoke(cx, cy, spokeAngles[i], HUB - 1, Reel.RADIUS - 3, 3, Palette.ink)
    end
    for i = 1, SPOKES do
        spoke(cx, cy, spokeAngles[i], HUB, Reel.RADIUS - 3, 1, Palette.woodLite)
    end

    ring(cx, cy, HUB + 1, 0, Palette.ink)
    ring(cx, cy, HUB, 0, Palette.woodDark)

    -- La manivela. Va de ORO mientras hay un pez enganchado, que es cuando
    -- rodar hace algo: la misma regla que el nudo de la driza.
    local kx = math.floor(cx + math.sin(w) * (Reel.RADIUS - 7) + 0.5)
    local ky = math.floor(cy - math.cos(w) * (Reel.RADIUS - 7) + 0.5)
    ring(kx, ky, CRANK + 1, 0, Palette.ink)
    ring(kx, ky, CRANK, 0, hooked and Palette.gold or Palette.deckLite)

    -- Y el pez, encima de todo: en oro mientras esta dentro de la banda, que
    -- es cuando rodar sale gratis.
    if hooked then
        local fx, fy = rodAt(Util.clamp(pos, 0, 1) * len, bow, lift)
        fx, fy = math.floor(fx), math.floor(fy)
        local turned = yield > 0
        -- El contorno, engordado a los cuatro lados con la propia silueta.
        silhouette(fx - 1, fy, Palette.ink, turned)
        silhouette(fx + 1, fy, Palette.ink, turned)
        silhouette(fx, fy - 1, Palette.ink, turned)
        silhouette(fx, fy + 1, Palette.ink, turned)
        silhouette(fx, fy, inBand(state) and Palette.gold or Palette.white, turned)
    end

    love.graphics.pop()

    -- Y por que no pasa nada, cuando no puede pasar. Va en espacio virtual
    -- porque es texto: dentro de la escala de arte la fuente saldria a bloques
    -- de cinco pixeles. Es la misma excusa que la lectura de rumbo de la
    -- rueda -- "amarrado no se pesca" no tiene otra representacion que las
    -- palabras -- y aparece SOLO cuando hace falta: con la cana pescando aqui
    -- no hay nada, y ese hueco tambien dice lo suyo.
    if reason then
        local mx, my = rodAt(rod * 0.45, bow, lift)
        UI.textCenter(reason, mx * Constants.ART, (my + 11) * Constants.ART,
                      Palette.dim, Fonts.tiny)
    end
end

return Reel
