# Rumbo

Idle de navegacion en **vista cenital**, formato vertical, para movil. Hecho en
LÖVE 11.x.

Un barco cruza el mar solo. Tu eliges el rumbo, repartes a la tripulacion por
los puestos de cubierta, atracas en los puertos que aparecen y decides en que
gastar lo que has sacado. El barco navega igual cuando la app esta cerrada: al
volver se simula el tiempo ausente y se te cuenta que ha pasado.

Esto es el **andamiaje**: la estructura, los sistemas y el arte provisional.
Cada sprite se genera por codigo salvo que exista su PNG en `assets/`, en cuyo
caso gana el archivo (ver `assets/README.md`). El barco ya viene dibujado: son
ocho capas sobre un mismo lienzo de 80x96, seis de ellas de archivo, y le
faltan dos por dibujar (la bodega y el trapo arrizado).

---

## Ejecutar

```sh
love .                        # desde la raiz del proyecto
lua5.1 tests/test_sim.lua     # prueba de la simulacion, sin ventana
lua5.1 tests/test_deck.lua    # el paseo de la tripulacion por cubierta
lua5.1 tests/test_halyard.lua # la driza: fisica y geometria
lua5.1 tests/test_sea.lua     # el mar: como se peina, la calma y la estela
```

Teclas: `F11` / `alt+enter` pantalla completa, `esc` cierra la hoja abierta,
`F5` empieza partida nueva (borra la guardada).

La partida se guarda sola cada 15 s, al perder el foco y al salir, en el
directorio de guardado de LÖVE (`~/.local/share/love/rumbo/save.lua` en Linux).

Una partida guardada por una version anterior se pone al dia sola al cargarla
(`World.migrate`): rellena los campos que falten desde `DEFAULTS` y da de alta
los puestos nuevos a nivel 1, sin pisar nada de lo que ya hubiera. Por eso
anadir un campo al estado obliga a anadirlo tambien a `DEFAULTS`.

Comprobacion de sintaxis rapida tras una edicion amplia:

```sh
for f in main.lua conf.lua lib/*.lua src/*.lua src/screens/*.lua; do
  luac5.1 -p "$f" || echo "FALLA $f"
done
```

---

## Las tres reglas que sostienen el aspecto

**1. Nada se dibuja girado.** Ni una sola llamada pasa rotacion a
`love.graphics.draw`. Un sprite girado en tiempo de dibujo muestrea fuera de la
rejilla y se deshace, y el arte de 16px no lo perdona.

De ahi sale la decision mas importante del juego: **la camara va con el barco**.
La proa apunta siempre hacia arriba de la pantalla, el barco se dibuja quieto en
el centro y lo que gira es el mar (`Sea.project`). Cambiar de rumbo no gira el
barco: gira el mundo.

Y de ahi sale la segunda: **lo del mundo que tenga orientacion hay que
dibujarlo, no rotarlo**. Las islas son manchas y los puertos manchas con un
fanal; se leen igual desde cualquier demora y por eso les basta un sprite. Si
algun dia hay otro barco en el mar, o se dibuja en varios rumbos, o rompe la
regla.

El **oleaje** es el caso que si tiene orientacion -- se peina contra el viento,
asi que va en diagonal cuando el viento va en diagonal --, y hay una tercera
salida que no rompe la regla porque no hay sprite que romper: **calcularlo por
pixel**. La superficie es hoy un shader (`src/surface.lua`) que muestrea un
campo de espuma en coordenadas del mundo, giradas por el mismo rumbo que
`Sea.project`. Un shader no muestrea una rejilla de pixeles: la evalua, asi que
puede peinar el mar en cualquier direccion sin deshacerlo. Y como se pinta en un
lienzo a escala de ARTE, cada invocacion **es** un pixel del juego, con lo que
la rejilla sale cuadrada sola.

Antes de eso el oleaje iba por la primera salida, y funcionaba: cada trazo
generado doce veces, uno cada quince grados, elegido por el angulo en pantalla.
Costaba cuarenta y ocho sprites y doscientas llamadas de dibujo por fotograma;
el shader cuesta una. Sigue siendo la salida buena para cualquier cosa del mundo
que sea un DIBUJO y no una textura -- un barco enemigo, por ejemplo.

Las excepciones que van por la OTRA salida son cinco —la rosa del timon
(`src/compass.lua`), la rueda del timon (`src/helm.lua`), la driza del velamen
(`src/halyard.lua`), el redal de las redes (`src/reel.lua`) y la carta de marear
(`src/screens/chart.lua`)— y las cinco son legales por la misma razon: **no usan
sprites**. Sus agujas, cabillas, cuerda, cana, puntos y derrotas se pintan con
rectangulos de 1x1, asi que apuntan a cualquier angulo sin muestrear nada. La
rueda, la driza y el redal pintan los suyos ademas dentro del `scale()` del
mundo, asi que su madera y su cuerda tienen el mismo grano que el casco.

La carta ademas es la unica pantalla con el **norte arriba**. La travesia lleva
la camara solidaria a la proa porque es lo que ves desde cubierta; una carta es
un papel sobre una mesa y no gira contigo. Que las dos vistas esten orientadas
distinto es la diferencia entre mirar por la borda y mirar el papel.

**2. Solo pixeles enteros.** Todo lo que es mundo se dibuja dentro de un
`scale()` entero (`Constants.ART`, x5) sobre un lienzo virtual, y todas las
posiciones se redondean. `Art.draw` hace el `math.floor` por ti.

Ese numero es ademas el zoom del mundo, y es la unica forma de agrandar el
barco sin ensuciarlo: al ser entero, cada pixel de arte cae en un cuadrado
exacto de pantalla y el filtro `nearest` no tiene nada que interpolar. Estuvo
en x4 y el barco se quedaba pequeno; x6 ya mete la perilla del palo debajo del
HUD, asi que x5 es el techo. Cuesta mar: el area de arte pasa de 135x240 a
108x192, se ven menos olas y el mundo desfila mas rapido en pantalla a la misma
velocidad de singladura. Si algun dia hace falta un barco mas grande sin
recortar mar, el camino no es este numero sino redibujar los PNG mas grandes.

**3. Nada del mar se guarda.** Islas, escollos, puertos, precios y la gente de
las tabernas son funcion pura de la posicion, la semilla y el tiempo, via
`Util.hash01`. La estela y las salpicaduras tampoco: son adorno, y al volver a
la partida el barco aparece con el mar limpio detras. La superficie guarda una
sola cosa entre fotograma y fotograma -- el punto del campo de espuma que le
toca mirar, que se arrastra con lo que anda el barco (`Surface.update`) --, y
tampoco va al fichero: al cargar arranca de cero y no se nota, porque es ruido.
El mar es infinito y la partida guardada ocupa un kilobyte.

---

## Espacios de coordenadas

Hay tres y conviene no mezclarlos:

| espacio | quien lo usa | quien lo define |
|---------|--------------|-----------------|
| ventana | solo `main.lua` | el sistema |
| virtual | HUD, botones, hojas, texto (540 de ancho) | `Constants.GAME_WIDTH/HEIGHT` |
| arte | mar, barco, sprites (108x192 aprox.) | virtual entre `Constants.ART` |

El lienzo **no es 540x960 fijo**: el ancho si, el alto se estira segun la
pantalla, asi que un movil 20:9 ve mas mar en vez de bandas negras. Nada se
coloca contra un 960 escrito a mano; se lee `GAME_HEIGHT`, `ART_H` y los
margenes seguros (`Constants.SAFE_*`).

Mundo -> pantalla es `Sea.project(state, wx, wy)`, y es la unica conversion que
hay. No la reimplementes.

---

## Estructura

```
rumbo/
├── conf.lua              # ventana 540x960, vertical, pantalla completa en movil
├── main.lua              # lienzo, fuentes, reparto de entrada
├── Pixellari.ttf         # fuente pixel (la misma que AutoChest)
├── assets/               # TUS PNG (ver assets/README.md)
├── lib/
│   ├── classic.lua       # OOP
│   ├── viewport.lua      # lienzo virtual -> ventana
│   └── screen_manager.lua
├── src/
│   ├── constants.lua     # resolucion, escalas, margenes seguros
│   ├── palette.lua       # la paleta entera
│   ├── util.lua          # hash determinista, angulos, formatos (sin love)
│   ├── art.lua           # registro de sprites: genera, o carga de assets/
│   ├── save.lua          # persistencia
│   ├── session.lua       # la partida en curso + autoguardado
│   ├── world.lua         # LA SIMULACION: estado, paso, ausencia, acciones
│   ├── ship.lua          # estado -> ritmos (todo el balance)
│   ├── stations.lua      # los seis puestos de cubierta
│   ├── crew.lua          # tripulantes: pericia, soldada y cara
│   ├── ports.lua         # puertos, precios, tabernas
│   ├── sea.lua           # camara, estela, bigote, islas y puertos
│   ├── surface.lua       # la superficie del agua: el shader del oleaje
│   ├── deck.lua          # donde anda la tripulacion por cubierta (solo dibujo)
│   ├── compass.lua       # la rosa del timon, centrada en la cabecera
│   ├── helm.lua          # la rueda del timon: un cuarto en la esquina de estribor
│   ├── halyard.lua      # la driza del velamen: la cuerda de babor, con fisicas
│   ├── reel.lua          # el redal de las redes: pescar a mano por el bajo
│   ├── hud.lua           # la cabecera (timon al aire, bloque de estribor) y la bitacora
│   ├── ui.lua            # UI inmediata: botones, filas, hojas
│   └── screens/
│       ├── boot.lua      # genera el arte con barra de progreso
│       ├── voyage.lua    # pantalla principal
│       ├── port.lua      # mercado, taberna, astillero
│       └── chart.lua     # carta de marear: rumbo a un puerto descubierto
└── tests/
    ├── test_sim.lua      # prueba headless de la simulacion
    ├── test_deck.lua     # prueba del paseo por cubierta (geometria, sin ventana)
    ├── test_halyard.lua  # prueba de la driza (fisica y geometria, con love de mentira)
    └── test_sea.lua      # prueba del mar (uniformes del shader y estela, con love de mentira)
```

**El corte importante es simulacion / dibujo.** `world.lua`, `ship.lua`,
`stations.lua`, `crew.lua`, `ports.lua` y `util.lua` **no requieren `love`**.
Por eso se pueden probar sin ventana y por eso la vuelta a la partida usa
exactamente el mismo paso que el juego en vivo.

---

## La pantalla de travesia

```
┌─────────────────────────────────────────────┐
│ ┃                                 │ ▉ ▉ ▉  │
│ ┃               ╭───────────╮     │ ▉ ▉ ▉  │
│ ┃               │  N  ·  E  │     │ ▉ ▉ ░  │
│ ●               │   NE 045  │     │🛡 ❤ 📦 │
│  la driza       ╰───────────╯     │  6/40  │
│               4,3 nudos · vela 80%├────────┤
│               viento NE fresco    │🪙  240 │
│            Puerto Vela a 42 millas│🐟   38 │
│                                   │🪵   12 │
│                                   │📦    6 │
│                                   └────────┤
│                                     debe 14 │
│                     ▲                       │
│                   ▐███▌                     │  el barco, en el
│                   ▐███▌                     │  centro exacto
│                    ▀▀▀                      │
│  se avista un pecio                         │  bitacora
│  Mariña Cordal se enrola                    │
│  [ Tripulacion ]                            │  dos columnas
│  [ Carta       ]        [ Atracar        ]  │
└─────────────────────────────────────────────┘
```

**Arriba hay tres preguntas y dos sitios.** En medio *hacia donde voy*: el
timon con las dos lecturas que la rueda no lleva dentro. Y a estribor, en un
solo bloque, las otras dos: arriba *como estoy* — casco, moral y bodega, que se
miran de un vistazo para ver si algo se esta cayendo — y debajo *que llevo* —
los cuatro recursos en cifras, porque con ellos se hace aritmetica ("me faltan
40 monedas para subir la bodega") y una barra no se suma.

Las tres preguntas se hacen en momentos distintos, y separadas asi cada una
cae siempre en el mismo sitio en vez de obligar a recorrer la pantalla entera.
Por lo mismo las barras van **de pie**: tres tumbadas no caben una al lado de
otra y apiladas hay que leerlas de una en una, mientras que de pie se comparan
por altura sin leer.

**Las cifras estan debajo de las barras y no en la esquina de babor**, que es
donde estuvieron. Las dos medidas comparten columna, con un filete en medio
para que no se lean como una sola lista de siete cosas, y a cambio la esquina
de arriba a la izquierda queda vacia: es la que se come el notch y la que menos
se mira, y asi todo lo que se consulta cae del mismo lado sin cruzar la
pantalla. Las cifras van alineadas a la derecha, como el `6/40` de bodega, para
que las unidades caigan todas en la misma columna.

**Solo ese bloque lleva fondo**, y mide lo que mide su contenido. Fue una
franja maciza de lado a lado y era peor: una franja se come el mar aunque este
vacia, y la parte de en medio no tenia nada que tapar. El bloque sangra por el
borde de la pantalla en vez de flotar, asi que solo se le ve el canto de dentro
y se lee como parte del marco; de paso cubre el notch de ese lado sin un caso
aparte. La soldada devengada cuelga *fuera* del bloque, sobre el agua, para que
lea como aviso y no como una medida mas: cuando no se debe nada ahi no hay
nada, y el hueco es parte del mensaje.

**El timon esta centrado arriba y no en una esquina.** La rueda ya lleva dentro
las tres cosas que se miran al gobernar — rumbo, viento y rumbo pedido — asi
que su sitio es con el resto de la navegacion. Se paga con el pulgar: en la
esquina inferior de estribor se alcanzaba sin mover la mano y arriba no. Cuelga
al aire sobre el mar, y bastante por debajo del borde (`Compass.MARGIN`): si
subiera del todo, se pegaria al canto del bloque de estribor y los dos juntos
volverian a parecer una franja maciza.

A cambio libera el bajo de la pantalla, y de ahi salen las otras dos piezas:
los botones se reparten en **dos columnas** (a babor lo que se consulta, a
estribor lo que se le hace al barco), lo que baja la pila de cinco filas a dos,
y con ella baja la bitacora y **el barco pasa al centro exacto** de la pantalla
(`Constants.shipAnchor`, antes en 0,42) con el mismo mar por proa que por popa.

Ningun alto de estos esta escrito dos veces: el pie de las lecturas sale de
`Compass.center()` mas dos lineas (`Hud.topHeight`), y el bloque no tiene alto
propio — lo suman las barras (`BARS_H`), el filete y las cuatro filas de
recursos, asi que crece solo si crece lo que lleva dentro. Mover el timon mueve
todo lo de arriba y no hay un segundo numero que ajustar.

### Gobernar: la rosa arriba, la rueda abajo

Hay **dos mandos de rumbo y hacen cosas distintas**. La rosa de la cabecera es
para *elegir* rumbo: se toca un punto y se pide "la proa ahi", de un toque y sin
pulso. La rueda de `src/helm.lua` es para *gobernar*: sale al tocar el puesto
del timon en cubierta, ocupa la esquina inferior de estribor y se mueve
arrastrando, que es el gesto de corregir un poco.

**De la rueda solo se ve un cuarto**, con el centro clavado en la esquina. Es lo
que permite que sea enorme —220 px de radio, mas que el ancho del barco— sin
comerse el mar, y es tambien lo que se ve de un timon de verdad con el timonel
detras. Va a estribor porque el movil se sujeta con la derecha: ahi cae bajo el
pulgar sin mover la mano, que es exactamente lo que la rosa perdio al subirse a
la cabecera y lo que dejo libre el bajo de la pantalla.

**Entra rodando** desde fuera de la esquina, por su propia diagonal, y sale por
donde vino. El giro de la maniobra no es un adorno pegado al deslizamiento: es
el que le toca por rodar esa distancia (`SLIDE / RADIUS` radianes), asi que la
rueda parece venir rodando hasta su sitio en vez de girar porque si. La curva
es una sola, un cubo que frena al final, y de ella salen las dos sensaciones
sin escribir ninguna: recorrida de 0 a 1 entra rapido y se asienta; recorrida
de 1 a 0 arranca despacio y se escapa. Ser una sola es tambien lo que permite
interrumpir la maniobra a medias —volver a sacarla mientras se guarda— sin un
salto. Meterla cuesta 0,24 s y sacarla 0,16: guardar algo tiene que sentirse
resuelto.

La animacion es **solo dibujo**. El gobierno mide siempre desde el centro
puesto, no desde el que entra: midiendo desde el que entra, el propio
deslizamiento cambiaria el angulo del dedo sin que el dedo se moviera y la
rueda ordenaria rumbo ella sola. Y como entrando la rueda esta mas cerca de la
esquina que puesta, lo que se ve cae siempre dentro de lo que se toca, asi que
se puede agarrar desde el primer cuadro.

La madera se pinta con rectangulos de 1x1 dentro de la escala de arte, asi que
la rueda gira sin que gire ningun sprite y su pixel mide lo mismo que el del
casco. Cada pieza se pinta dos veces —engordada un pixel en `Palette.ink` y
luego en su color— y de ahi sale el **contorno negro de 1px** que llevan los
sprites de `assets/`; el corte del cuarto no se lo lleva, porque la rueda no
esta recortada, es que sigue fuera de la pantalla. La llanta va lisa a
proposito: es lo unico de la rueda que no gira, y una veta encima delataria que
se queda quieta mientras las cabillas dan vueltas.

La **desmultiplicacion no es un numero elegido a dedo**: los 90 grados de rueda
que se ven son toda la rosa, o sea una vuelta de rumbo entera cada cuarto de
rueda. De ahi salen las dos cosas que hacen que se lea:

* la **cabilla maestra** (la dorada) nunca se sale del cuarto visible, asi que
  la rueda no puede aparentar estar a la via estando a la banda. Con las
  cabillas iguales y equidistantes, una rueda girada justo el paso entre dos se
  dibuja *exactamente* igual que una sin girar; acotar el giro al cuarto es lo
  que evita esa mentira.
* media rosa son 173 pixeles de arco en la llanta: un pixel de dedo, un grado
  de rumbo.

**La rueda no guarda su angulo en ningun sitio**: es lo que falta por caer
(`angleDiff(rumbo, rumbo pedido)`) desmultiplicado. Por eso se centra sola segun
el barco entra al rumbo nuevo, y la cabilla maestra bajo el indice blanco es la
maniobra terminada — la misma lectura que la marca dorada subiendo al pico de la
rosa. Arrastrar recalcula el rumbo pedido desde el rumbo *actual* en cada
cuadro; si ordenara un incremento sobre el rumbo pedido, el barco cayendo
giraria la rueda por debajo del dedo y pareceria que forcejea.

Mientras la rueda esta a la vista, **la esquina de estribor es suya**: la
columna de botones de ese lado no se dibuja, porque cae debajo, y la rosa de
arriba se queda inerte. Se mira si se *ve* y no si esta pedida: volviendo en
cuanto se suelta el toque, los botones asomarian por entre las cabillas justo
mientras la rueda se va. Se pierde poco —atracar y zarpar son cosas que se
hacen una vez, no mientras se gobierna— y la columna de babor y la bitacora,
que estan al otro lado, siguen ahi. Un toque en cualquier otro sitio la recoge
y no hace nada mas: dos mandos de rumbo vivos a la vez es como se acaba
pidiendo un rumbo con el pulgar que sujeta el movil, y recoger la rueda
zarpando de propina —que es justo lo que tapa— es la misma clase de accidente.

### El trapo: la driza de babor

El otro mando que se usa navegando es **una cuerda**, y sale igual que la
rueda: tocando su puesto. Tocar el velamen larga la driza de `src/halyard.lua`
por la esquina de **arriba a babor**, que es la unica esquina de la pantalla
donde no hay nada —el bloque del HUD esta a estribor y la bitacora abajo— y
deja la hoja del puesto para el segundo toque.

**Se maneja como una persiana**, y de ahi sale todo lo demas. El trapo no es un
interruptor con dos estados iguales: es algo que se recoge tirando y se larga
de golpe, asi que las dos maniobras no son simetricas.

| trapo | la cuerda | para cambiarlo |
|-------|-----------|----------------|
| largo | cuelga corta, el nudo a la altura de la rosa | arrastrar el nudo hacia abajo, un buen trecho |
| con rizos | cuelga larga, el nudo a media pantalla | un tiron corto y soltar: la cuerda rebota arriba |

Recoger cuesta un arrastre largo y largar un tiron corto porque es lo que hace
una persiana de verdad, y porque las dos maniobras no valen lo mismo: los rizos
se toman para no romper nada y el trapo se larga para correr, asi que **la que
cuesta es la de guardar**. Con rizos, ademas, el nudo cuelga a media pantalla,
que es justo donde cae el pulgar, y es el estado del que se sale mas a menudo.

**El largo de la cuerda es el indicador.** No hay ninguna lectura que diga que
trapo se lleva: lo dice cuanto cuelga, lo dicen las velas del barco (hay sprite
de trapo arrizado) y lo dice la bitacora. Lo unico que se pinta de mas es el
**nudo en oro** cuando ya se ha tirado bastante para que soltar haga algo, que
es el color con el que el juego dice "esto es lo que has pedido" y que cae justo
bajo el dedo, que es donde se esta mirando. Y no lleva texto: la rueda lleva
lectura porque un rumbo no tiene otra representacion que un numero, pero el
trapo se ve en el barco.

**La cuerda tiene fisicas de verdad**, y el reparto es el de este trasto: un
cabo ligero con un **nudo pesado** en la punta. Fisica tiene el nudo, y solo el:
un pendulo colgado del ancla, con el radio en un muelle. La cuerda de en medio
no se simula, se **deriva** —una recta del ancla al nudo con una comba, que es
un solo numero—. De ese reparto salen tres cosas que si no habria que escribir
una por una: el rebote al largar trapo (el muelle del radio se pasa de largo y
vuelve), el latigazo de la cuerda cuando el nudo corre de lado, y el balanceo de
pendulo al soltar despues de arrastrar en diagonal. Y el largo cambia
deslizando por el ancla en vez de estirando, porque al nudo se le impone el
radio: la cuerda paga o cobra por arriba, como una de verdad.

**Que el nudo sea el cuerpo es lo que la hace un pendulo.** Antes eran doce
nodos con verlet y cada uno colgado del de encima, que es lo natural para una
cuerda clavada arriba, y no habia una cuerda tensa sino doce pendulos
independientes de un tramo cada uno. Los tramos son cortos —con el trapo largo,
dos pixeles y pico— y su pendulo va a `sqrt(g/tramo)` = 43 radianes por segundo,
que a paso de 1/60 son 0,7 por paso: el limite en el que el integrador ya no
converge, **zumba**. Y el balanceo de la cuerda entera lo mandaba el tramo de
*arriba*, el que menos palanca tiene, asi que se plantaba en un tercio de
segundo por mucho que se bajara la amortiguacion. Con el nudo de cuerpo el
pendulo es el de la cuerda entera, con su periodo de casi un segundo.

**Y que la cuerda se derive es lo que hace que en reposo este quieta.** Con la
cadena simulada la cuenta salia —colgaba recta y el nudo terminaba limpio— pero
el *dibujo* hervia: doce nodos moviendose cada uno una fraccion de pixel
vuelcan sellos enteros cada vez que uno cruza un borde, y salian sesenta
pixeles cambiando de cuadro a cuadro cuando el rebote ya habia terminado a la
vista. Era ruido de mas, porque una cuerda tensa con un nudo pesado **es** una
recta: los doce nodos solo aportaban la comba del latigazo. Derivada de dos
puntos y un numero, la cuerda solo cambia cuando cambia el nudo o la comba.

**Los ultimos pixeles se andan, no se atenuan.** Un muelle y un pendulo llegan
con cola exponencial, y esa cola a este tamano de pixel no es suave: son tres o
cuatro decimas de pasitos de un pixel salteados, unos cuadros moviendose y
otros no. La torcida lo multiplica, porque sus marcas van a distancias fijas del
*nudo* y cualquier deriva del largo por debajo del pixel las corre todas de
golpe —dos docenas de pixeles repintados por una centesima de movimiento, y mas
cuanto mas corta la cuerda, que es como se noto—. Asi que por debajo de tres
pixeles y medio de amplitud el largo y el angulo van a su sitio **de un pixel
por cuadro y sin velocidad**, y de ahi al reposo.

Lo que se lee como temblor no es cuanto se mueve: es que **cambie de sentido**
moviendose poco. Un pixel de ida y otro de vuelta parpadean por pocos que sean,
mientras que tres de ida seguidos se leen como algo posandose. El umbral se mide
por amplitud —lo que falta mas lo que vale la velocidad que lleva— y no por lo
que falta a secas, porque el rebote *cruza* el largo de reposo a toda velocidad
camino de su punto alto: midiendo solo lo que falta, el remate se lo tragaria
ahi y no habria rebote.

**La amortiguacion del balanceo va como zeta y no como un factor por cuadro.**
El periodo del pendulo sale del largo —medio segundo con el trapo largo, casi
uno con rizos— asi que un factor por cuadro amortigua el doble de mal justo la
cuerda *corta*: en el mismo tiempo da el doble de vaivenes y pierde la mitad de
amplitud en cada uno, o sea que tardaba mas en calmarse precisamente la que
menos lo disimula. Contando el decaimiento en vaivenes, la corta se calma antes
que la larga, que es lo que toca.

**Entra desde la izquierda**, con la misma curva y los mismos tiempos que la
rueda, y con la punta llegando mas tarde que el ancla: eso es lo que la hace
entrar como una cuerda que alguien larga y no como un panel que desliza. La
animacion es *solo dibujo*, igual que en la rueda: el tiron se mide siempre
desde el ancla **puesta**, porque midiendolo desde la que entra el propio
deslizamiento cambiaria el largo sin que el dedo se moviera y el trapo se
cambiaria solo.

**Se agarra donde se ve**, nodo a nodo y no en una recta desde el ancla: la
cuerda no esta recta ni entrando ni balanceandose, y una zona de toque que no
coincide con lo que se ve se siente rota. Y el tiron es **relativo** —al agarrar
se guarda lo que sobra entre el dedo y el nudo— asi que se puede coger la cuerda
por el medio y tirar sin que el nudo salte al dedo. Pasado el tope la cuerda
queda tensa y el dedo se le escapa, que es lo que hace una cuerda y no una goma.

**Cuelga a diez pixeles de arte del margen seguro de babor**, y no pegada al
canto: pegada, la driza se lee como el marco del lienzo en vez de como un cabo
que baja de una verga que esta fuera de plano. Separada tiene aire a los dos
lados, y se ve que viene de algun sitio.

**El nudo es un disco par**, y eso es lo unico que hay que saber para no
volverlo a romper. La cuerda mide dos pixeles de arte de cuerpo y uno de
contorno a cada lado —el grosor de las cabillas de la rueda, de donde salio—,
o sea un ancho PAR, asi que la banda que se pinta cae a caballo de la posicion
y su eje esta en medio pixel. Un disco de radio entero (2r+1 de ancho) se
centra por fuerza en un pixel entero, medio pixel a estribor de ese eje, y aqui
no hay medios pixeles: el nudo volaba tres columnas por babor y **cuatro** por
estribor y se veia colgado de lado. Con el disco par —diametro 2r, centro en el
cruce de cuatro pixeles— los dos comparten eje exacto. El semiancho de cada
fila se redondea en vez de truncarse, porque truncando el disco par pierde una
columna por lado y con el alto intacto sale huevo en vez de nudo.

La cuerda lleva **la torcida** marcada, un pixel claro cada tres, porque sin
ella una cuerda de media pantalla se lee como un palo. Se cuenta *desde el
nudo* y no desde el ancla, y ahi esta el detalle: la cuerda corre por el ancla
al largar y al recoger, asi que el trozo que se ve cuelga siempre del mismo
nudo y lo que entra por arriba es cuerda nueva. Contada desde el nudo, la
torcida se queda quieta sobre su material y aparece por el ancla segun sale
cuerda; contada desde el ancla se veria correr al reves, que es la mentira que
la llanta de la rueda evita yendo lisa.

**Los tres mandos no salen a la vez.** No porque se estorben —la rueda y la
driza estan en esquinas opuestas— sino porque mientras uno esta fuera un toque
en cualquier otro sitio lo recoge: con dos fuera, tocar uno guardaria el otro.
Y es esa exclusion la que deja al redal nacer de la misma esquina que la rueda
sin pisarla nunca.

**Y el trapo no tiene boton.** Lo tuvo, abajo a estribor, diciendo "tomar
rizos" o "largar trapo" segun lo que hubiera puesto, y se lo ha quedado la
cuerda entera. Dos formas de hacer lo mismo no salen gratis cuando una de ellas
es una maniobra: el boton se enteraba del cambio *despues*, asi que mientras se
arrastraba el nudo hacia abajo seguia ofreciendo lo que ya estaba pasando. Y
sobre todo, un interruptor y una persiana cuentan cosas distintas —el boton
decia que el trapo tiene dos estados iguales, y la driza dice que recoger
cuesta un arrastre y largar un tiron—, asi que la que se queda es la que dice
la verdad. Al quitarlo, la columna de estribor se queda con lo de puerto y
`World.toggleTrim` se fue con el: el trapo ya solo se **pide**.

### Pescar: el redal del bajo

El tercer mando que se usa navegando es **una cana**, y sale del mismo reparto
que los otros dos: tocar el puesto de **Redes** en cubierta larga el redal de
`src/reel.lua` por la esquina inferior de estribor y deja la hoja del puesto
para el segundo toque. Las redes pescan solas mientras se navega —eso no
cambia— y el redal es lo que se puede hacer *a mano* encima.

**No pide nada a la simulacion.** La rueda ordena rumbo y la driza pide trapo,
pero mientras se pelea un pez no hay estado que cambiar: la pelea entera vive
en el modulo y no en la partida guardada. `Reel.update` devuelve un **suceso**
—pez cobrado, pez perdido, linea rota— y la travesia lo traduce a
`World.landFish` o a una linea de bitacora. Cerrar la app con un pez enganchado
es perderlo, igual que soltar el movil con la cana en la mano.

**La cana es la regla del sedal.** Del carrete sale una cana hacia babor y
sobre ella corre la silueta del pez: a babor del todo es el pez con todo el
sedal fuera —se va— y a estribor del todo es el pez en la borda, cobrado. No
es una barra de interfaz con otro dibujo: es la lectura directa de lo unico que
hay que saber mientras se pelea, y cae donde se esta mirando, que es la mano
que rueda.

**Se rueda el carrete**, no se aprieta un boton, y de ahi sale la pelea entera:

| lo que se hace | lo que pasa |
|----------------|-------------|
| nada | el pez tira **siempre**: el reposo del carrete no es cero, es la carrera del pez |
| el dedo encima | manda el dedo, y gira lo que ha corrido *menos* lo que el pez se lleva igual: agarrar y quedarse quieto no es una pausa |
| soltar rodando | el carrete se queda con su giro y se relaja hacia la carrera: unas decimas de regalo antes de que el pez mande otra vez |
| volver a agarrar | lo **para**, aunque no se ruede. Es palmear el carrete, y es como se corta una arrancada |

**El segmento es la regla del juego.** Sobre la cana hay una banda clara que
cambia de sitio cada pocos segundos: es donde el pez aguanta que se tire de el.
Rodar con el pez **dentro** no cuesta nada; rodar con el pez **fuera** tensa la
linea, y la linea llena se rompe. De ahi salen las dos maniobras que pide una
cana de verdad: *atraer* cuando el pez esta en la banda y *dejarlo ir* —soltar,
que el pez corra hacia babor— cuando la banda se ha ido por detras de el. Sin
la segunda, pescar seria rodar sin parar. El pez cuenta como dentro cuando su
**cuerpo** toca la banda y no cuando su centro cae en ella: midiendo por el
centro habia cinco pixeles y medio a cada lado de "parece que si y el juego
dice que no", que es exactamente el sitio donde se pelea.

**El carrete lleva freno**, y no es un adorno: es lo que evita la estrategia
degenerada de todo lo que se rueda, que es rodar como un poseso. Pasado el
freno la bobina **resbala** —hay un tope de lo que se le puede ganar por
segundo a la carrera del pez— asi que barrer el pulgar sin mirar no adelanta
nada, tensa, y ademas se **ve**: la manivela se queda atras del dedo, que es lo
que hace un freno resbalando.

**Y cortar una arrancada se cobra.** Si el pez entra en la banda *huyendo* y se
recoge de verdad en las decimas siguientes, **cede** unos segundos: tira mucho
menos y el freno aguanta mas. Sin eso la pelea no tenia jugada buena, solo
jugada correcta —rodar cuando toca y soltar cuando toca, siempre al mismo
precio—; con eso, estar atento vale dinero. La cedida se desvanece en vez de
apagarse de golpe: el pez se recupera, no se le acaba la pila.

**La tension no tiene barra: la cana se comba.** Es el indicador que ya existe
en el mundo real, el unico que no hay que aprenderse, y cae encima del pez, que
es donde se esta mirando. Pasado el aviso el sedal se pone rojo, y eso es lo
unico que se pinta de mas. El **oro** dice lo que dice en todo el juego —"esto
es lo que hay que hacer"— en dos sitios: el pez mientras esta dentro de la
banda (rodar ahora es gratis) y la manivela mientras hay un pez enganchado
(rodar ahora hace algo). Con la cana en reposo no hay ni una cosa ni la otra, y
eso es parte del mensaje.

**En reposo esta inmovil, menos el corcho.** Es la leccion de la driza y a la
vez su reverso. Sin pique no se integra nada —el sedal cuelga con una comba
fija, la cana va recta, el carrete no gira— pero la pantalla no puede quedarse
*exactamente* igual cuadro tras cuadro: ocho segundos de eso no se leen como
esperar, se leen como que el juego se ha colgado. Asi que lo unico que vive es
el corcho, que es ademas lo unico que esta en el agua: una cuerda colgada esta
quieta, un corcho no lo esta nunca. Y al picar el corcho **se hunde**, que es
la imagen de un pique en cualquier sitio del mundo: el pique se lee aunque el
movil no vibre —vibra— y aunque se este mirando a la otra punta.

**Mientras esta fuera, el bajo de la pantalla es suyo**: se quitan las dos
columnas de botones y la bitacora. La rueda solo se lleva su columna porque
cabe en su esquina; el redal cruza de banda a banda —carrete a estribor, cana
hasta babor y sedal cayendo al agua— asi que debajo no puede quedar nada. Y se
pierde poco: la bitacora se lee de reojo cuando no pasa nada, y mientras hay un
pez en la cana lo que pasa esta en la cana.

**Un mando que no puede funcionar lo dice.** Amarrado no corre la singladura y
tampoco la cana: el redal se larga igual —no dejarlo salir seria un mando que a
veces no existe— pero escribe por que no pasa nada. Sin eso estaba roto sin
estarlo, y justo en el estado en el que empieza la partida. Con la **bodega
llena**, en cambio, se pesca igual: es el estado en el que se vuelve de una
ausencia larga, o sea que apagar ahi la pesca a mano la apagaba precisamente
cuando mas rato se lleva mirando. Se puede ganar la pelea y que no quepa el
premio —mal negocio, pero del jugador— y la bitacora dice cuanto se quedo
fuera; lo que no puede ser es pelear un pez y que no pase nada visible.

**Y el puesto de Redes se nota en el mando**, que es lo suyo: ensancha la banda
y aplaca el brio del pez. Un buen pescador no tira mas fuerte, sabe cuando el
pez aguanta.

---

## El bucle

```
setup inicial: amarrado en Puerto Madre, dos manos a bordo, 60 monedas
      ↓
  navegar  ──►  elegir rumbo en el timon (la ceñida decide la velocidad)
      │         o hacer rumbo a un puerto desde la CARTA DE MAREAR,
      │           y entonces el timonel corrige solo y el barco atraca al llegar
      │         repartir tripulacion por los puestos
      │         las redes pescan hasta llenar la bodega, la cocina cocina,
      │           el carpintero repara, el vigia avista puertos y restos
      │         las soldadas se APUNTAN, no se cobran: en el mar no hay banco
      ↓
  atracar  ──►  se liquida la soldada devengada
                mercado: vender pescado, comprar madera y raciones
                taberna: enrolar y licenciar
                astillero: calafatear y subir puestos de nivel
      ↓
  zarpar   ──►  vuelta a empezar, con el barco un poco mejor
```

### Rumbo y viento

El viento es una funcion pura del tiempo de travesia (`World.updateWind`): rola
despacio, sopla mas o menos fuerte y no se guarda en ningun sitio. Lo que
importa es el angulo entre el rumbo y el viento (`Ship.pointing`):

| rumbo respecto al viento | rendimiento |
|--------------------------|-------------|
| proa al viento           | 10 %        |
| ceñida                   | ~42 %       |
| traves                   | 100 %       |
| largo                    | ~94 %       |
| popa cerrada             | ~68 %       |

El pico esta en el traves, no en popa, que es como navega un barco de vela de
verdad; es lo que convierte "elegir rumbo" en una decision y no en un adorno.

### El mar lo cuenta todo

El viento no tiene barra. Se lee **en el agua**, y esa es la mitad del trabajo
de la superficie (`src/surface.lua`).

El agua es un **voronoi de espuma**: dos capas de celdas y la espuma justo en la
FRONTERA entre celda y celda, que es donde rompe el agua de verdad. El shader
es el de Shadertoy, con cuatro cosas cambiadas para que sea este mar: sin
perspectiva (aqui no hay horizonte), atado a la camara, con direccion, y con la
paleta cerrada.

La direccion es la parte que cuenta el viento. El campo se mide en dos ejes --
uno **a lo largo** del viento y otro **cruzado** --, y el cruzado mide mas mundo
por celda: las celdas salen estiradas a traves del viento, asi que sus fronteras
-- las vetas de espuma -- caen cruzadas al viento, que es como se peina el mar.
Mires donde mires, el mar dice de donde sopla, y al virar se repeina entero
porque los dos ejes se calculan en pantalla y la pantalla gira con el barco. Y
como el campo entero desfila a sotavento, tambien dice **hacia donde** va.

La **fuerza** decide el resto. El viento sopla entre 0,55 y 1,0, que como fuerza
de mar es un rango corto, asi que se estira a [0, 1] (`Sea.state`) para que la
calma sea calma de verdad. Con poco viento el estiron baja -- las vetas se
vuelven rizos redondos --, la espuma casi no sale y el agua **no puede** romper
en blanco: el escalon del blanco se manda por encima de uno, que es mas de lo
que la cuenta de espuma del oleaje puede dar en ningun pixel, asi que no es que
salgan pocas rompientes, es que no cabe ninguna. (La estela si rompe en calma,
y a proposito: se salta ese techo porque una estela es blanca haga el tiempo
que haga.) Con viento fresco el estiron sube, las
vetas se alargan, el dorso de cada ola se oscurece y aparecen las cabezas
blancas. Un ruido de manchas por encima hace que un trozo de mar este picado y
el de al lado casi liso, que es lo que separa un oleaje de un papel pintado.

Todo esto arrastra una leccion de la version de trazos que sigue mandando en los
numeros: **un mar de marcas claras iguales se lee como lluvia**, no como agua.
Por eso la cuenta acaba en cinco escalones de paleta y no en un degradado, y por
eso el reparto esta medido: dos tercios largos de agua a secas, un quinto de
bajio, un dos por ciento de espuma y dos pixeles de cada mil en blanco. Subir el
brillo del monton es lo que convirtio la primera version en un chaparron.

Dos cosas del shader no se ven pero sin ellas no hay mar. La primera: el campo
es **periodico** -- los hashes muerden la celda en modulo --, porque a las pocas
horas de singladura las coordenadas del mundo son tan grandes que `fract()` se
queda sin decimales y el mar hierve. La segunda: el origen del campo **se
arrastra** en vez de calcularse desde `state.x`, porque el eje del campo gira
con el viento y proyectar una posicion enorme sobre un eje que rola hace que el
mar salga disparado de lado en cuanto el viento rola un grado.

### La estela dice lo que hace el barco

El barco no pasa por encima del mar: lo **rompe**. La estela no se pinta sobre
el agua, se descuenta de ella. Lua le manda al shader la **derrota** -- los
ultimos puntos por donde ha pasado el espejo de popa, ya proyectados a pixeles
de pantalla, cada uno con lo que el barco ha andado desde entonces y lo que le
queda de vida -- y el shader mide la distancia de cada pixel a esa polilinea.
De ahi salen tres cosas:

* **El surco.** Dentro de la calle que abre el casco, el campo de espuma se
  aplasta: las crestas mueren y queda agua lisa que tarda en cerrarse. Es la
  lectura que ninguna version anterior daba, porque estaba hecha de espuma
  ANADIDA y esto es mar QUITADO.
* **El hervor de popa**, lo mas macizo de todo el mar, que dura media eslora.
* **Los brazos de la V**, que nacen en la **roda** -- la calle se cierra ahi en
  punta siguiendo el costado del casco, y por eso la V acaba en pico justo
  delante de la proa -- y se abren con lo que el barco ha **andado** desde cada
  trozo de derrota, no con lo que ha tardado. En una virada la V se dobla sola
  porque cada trozo lleva puesto su propio rumbo.

Por detras del espejo la calle mide la **manga entera del sprite**, leida de
`Art.HULL_BOX`: si alguien redibuja el barco mas ancho, el surco se ensancha con
el, y hay una prueba que lo comprueba.

Tres decisiones, y dos de ellas son cicatrices de haberlo jugado.

La primera se vio antes: los brazos van multiplicados por la veta del propio
oleaje, para que salgan rotos a trozos; una linea limpia a este grano de pixel
se lee como pintada encima.

La segunda: la espuma de la estela **si** puede romper en blanco con el mar en
calma, aunque el agua libre no pueda. Tiene su propio escalon de blanco, aparte
del techo que el viento le pone al oleaje. Sumada al del mar, con viento flojo
la estela salia de color de bajio y no se veia -- una estela es blanca haga el
tiempo que haga.

La tercera: la estela se apaga por lo **andado** (110 px) y no por el reloj, y
lo que se mide por velocidad son **dos** numeros y no uno. Por delante del
espejo manda la regla de siempre (por debajo de un tercio de andar la roda no
rompe agua); por detras, una compuerta que se llena mucho antes, porque un
barco deja rastro a cualquier velocidad a la que se mueva de verdad. Con las
dos cosas atadas a la velocidad y medidas en segundos, la estela se borraba
justo virando o con viento flojo -- que es cuando el barco pierde andar y
cuando mas se agradece ver que sigue vivo.

Delante ya no hay bigote de tres tamanos: la punta de la V es el bigote, y sale
de la misma cuenta. Lo que si sigue siendo sprite son las **salpicaduras**, que
salen a pulsos y sobre todo por la banda de **sotavento**: una gota esta en el
aire, por encima del agua, y ahi un sprite dice la verdad y un campo calculado
en la superficie no. Las dos cosas callan por debajo de un tercio de andar: un
barco que apenas se mueve con espuma en la proa miente, y en el ojo del viento
se pasa un buen rato asi.

### Puestos

Siete, en `src/stations.lua`. Cada uno tiene un gremio, plazas (crecen cada dos
niveles) y una potencia = **nivel + pericia destinada**, y nada mas.

| puesto | gremio | que hace |
|--------|--------|----------|
| Cofa | vigia | alcance de vista, restos a la deriva |
| Carpinteria | carpintero | repara casco gastando madera |
| Velamen | gaviero | velocidad |
| Redes | pescador | pescado |
| Cocina | cocinero | pescado -> raciones |
| Bodega | estibador | cuanto cabe a bordo, y por tanto cuanto rinde una ausencia |
| Timon | timonel | velocidad de caida al nuevo rumbo |

Un tripulante fuera de su gremio rinde **un tercio**: se puede poner al
cocinero al timon, pero se nota.

Cada puesto tiene un ancla en el lienzo del barco (`deckX`/`deckY`, fracciones)
y ahi se toca. Dos de ellos **no abren su hoja al primer toque**, porque sacan
un mando: el timon saca la rueda y el velamen larga la driza, y los dos dejan
la hoja para el segundo toque. Es el orden de la frecuencia —se corrige el rumbo
y se cambia el trapo cien veces por cada vez que se destina a alguien a esos
puestos— y el precio es un toque de mas para lo que se hace poco. Los tres que ya tienen arte estan clavados sobre su cacharro
—la cocina en el fogon, las redes en el aparejo, el velamen al pie del palo—
porque un aro dorado a cinco pixeles de su cacharro se lee como un error. La
bodega es la unica que se dibuja sola: hasta que exista su PNG, `gen.shipHold`
le pinta una trampilla leyendo esas mismas dos fracciones.

### La gente de cubierta

La tripulacion se ve andar por el barco. Vive entera en `src/deck.lua`, que es
**solo dibujo**: no aporta un numero a la simulacion, no se guarda y no hay un
`update()` que llamar.

**Cada uno tiene su cara, y sale de su nombre.** Hay catorce en
`assets/crew_pj01.png`..`crew_pj14.png`, y a cada tripulante le toca la que
diga el hash de su nombre (`Crew.face`). Antes habia siete monigotes, uno por
gremio, y el color decia el oficio; ahora el oficio se lee por **donde** esta
plantado, que es lo que la cubierta ya explicaba mejor, y la cara dice **quien**
es, que es lo que no se leia. Sacarla del nombre y no de un campo guardado tiene
dos ventajas que valen la resta: no hay semilla nueva en la partida (regla 4) y
las tripulaciones ya enroladas en partidas viejas no necesitan migracion.

**Dos paseos, y la diferencia es la que importa:**

* **destinado** — se remueve dos pixeles alrededor de su puesto. Uno clavado se
  lee como un icono en vez de como una persona; uno que se aleja rompe lo unico
  que la cubierta explica bien, que es quien esta trabajando en que. El aro del
  puesto le sigue quedando debajo.
* **sin destino** — pasea el barco entero, de proa a popa, en algo mas de un
  minuto. Es lo que hace que contratar de mas se *vea* y no solo se pague: la
  cubierta se llena de gente que no hace nada.

**El paseo es funcion pura de `state.time`** y del hash del nombre: dos senos de
periodos que no casan (un Lissajous que no cierra nunca, asi que no se ve el
bucle) con la fase y el compas propios de cada uno, para que catorce personas no
marchen a la vez. De ahi salen tres cosas gratis: nada que anadir a `DEFAULTS`,
el mismo dibujo con `dt` de 1/30 y de 2 s, y una ausencia de ocho horas que
devuelve a la gente movida de sitio —que es lo que debe pasar— sin haber
simulado un solo paso de paseo.

Por donde puede andar el que pasea **no es un rectangulo**: es la silueta del
casco, `Art.hullHalf`, la misma con la que se dibuja el barco. Asi el paseo se
estrecha solo hacia la proa en vez de sacar a nadie por encima de la borda, y
sigue cuadrando si maniana el casco se redibuja con otra manga. `tests/test_deck.lua`
barre miles de instantes contra esa misma silueta, porque un tripulante que sale
por la banda lo hace cada varios minutos, en la punta de un seno, y con el trapo
largo tapando media cubierta no se pilla mirando la pantalla.

**Se dibujan detras del trapo**, entre las redes y las velas. La gente anda por
cubierta y el aparejo esta por encima de su cabeza: pintados al final se subian
encima del pano y el barco dejaba de leerse como un barco. Los aros de puesto,
en cambio, van por encima de todo — no son parte del barco sino de la interfaz,
y un aro que dice "aqui falta gente" tapado por la verga no avisa de nada.

### Economia

Cuatro recursos (monedas, pescado, madera, raciones) y dos medidores (casco,
moral). Los ritmos estan todos en `Ship.rates` y son por segundo; el HUD los
ensena por minuto, pero son los mismos numeros que integra `World.step`. Si el
HUD dice `+14,4 pescado/min`, eso es lo que se esta acumulando.

Tres reglas la sostienen, y las tres estan escritas contra un fallo concreto
que aparecio simulando ocho horas de ausencia:

**La bodega solo guarda mercancia.** Pescado y raciones ocupan; las monedas
caben en un cofre y la madera es pertrecho con su propio tope (`Ship.WOOD_MAX`).
Cuando la madera competia por la bodega, una bodega llena de pescado dejaba al
carpintero sin material y el casco se caia a cero mientras dormias.

**La soldada se devenga proporcionalmente al sitio libre.** Una tripulacion
cobra por lo que estiba, y con la bodega llena no estiba. Sin esto el coste de
una ausencia crecia sin techo mientras el ingreso lo tenia, y ocho horas fuera
salian a perder: se debian 5.759 monedas contra una bodega de 100. Es
proporcional y no un interruptor porque el rancho va abriendo hueco
continuamente, y un "llena / no llena" oscilaba.

**En puerto no corre la singladura.** Amarrado no se pesca, no se cocina, no se
come de la despensa, no se cobra y no se gasta el casco. El puerto es una pausa
y el unico coste de quedarse es todo lo que no se produce. Antes de esta regla,
fijar rumbo y cerrar la app hacia que el barco atracara pronto y se pasara siete
horas comiendose la despensa: volvias a una tripulacion famelica por haber hecho
justo lo que el juego invita a hacer.

Lo que queda, entonces, como presion real:

* la tripulacion **come** raciones navegando, y sin ellas la moral cae;
* la soldada se **apunta** y se liquida al atracar; lo que no se pueda pagar
  sigue debiendose y cuesta moral delante de todos;
* la moral y el casco multiplican la velocidad;
* el casco se gasta navegando y solo se recupera con madera;
* **la bodega es el techo de una ausencia**, asi que subirla es literalmente
  comprar horas de idle. Es la palanca que un idle necesita tener.

### Ausencia

`World.catchUp(state, segundos)` simula hasta **8 horas** en pasos de 2 s con el
mismo `World.step`, y devuelve el resumen que se ensena al volver. La prueba
comprueba que una hora simulada de golpe queda dentro del 3 % de una hora
jugada en pasos de 1/30.

Dos detalles que se ven al usarla:

* **Los sucesos se cuentan, no se escriben.** Ocho horas generan cientos de
  lineas de bitacora y la bitacora guarda ocho, asi que la puesta al dia corre
  en silencio (`state.quiet`) y lleva la cuenta en `state.tally`. El resumen
  resta el antes del despues, igual que hace con los recursos, y por eso puede
  decir "29 puertos nuevos" y nombrar tres.
* **Por debajo de cinco minutos no se reporta** (`World.REPORT_MIN`). Se simula
  igual, pero cerrar la app un minuto y volver a una hoja modal que dice
  "+0 monedas, -1 pescado" es ruido.

Con el barco de serie, ocho horas fuera dan unas 1.400 monedas, la bodega llena
y 47 de soldada por pagar. La cifra a vigilar si se toca el balance es la de los
barriles: no ocupan bodega, asi que son el unico ingreso que no tiene techo.

### La carta de marear

La tercera pantalla. Ensena los puertos descubiertos con el norte arriba, se
arrastra y hace zoom, y tocando uno se puede **hacerle rumbo**: a partir de ahi
el timonel corrige solo cada paso de simulacion y **el barco atraca al llegar**,
tambien con la app cerrada. Es lo que convierte una ausencia en algo dirigido en
vez de una linea recta al vacio — y liquida la soldada sola al amarrar.

Tocar el timon a mano —la rosa o la rueda— suelta el rumbo fijado, o el barco
corregiria en el paso siguiente y el timon pareceria roto.

El precio de fijar rumbo a un puerto cercano antes de una ausencia larga es que
se llega pronto y el resto del tiempo se pasa amarrado sin producir. Es una
decision real, no un descuido.

### Nombres de puerto

Las tres partes del nombre (cabecera, adjetivo, cola) **no salen de un hash**:
cada una indexa su lista por una forma lineal de la celda, asi que el nombre es
una funcion periodica con el periodo bajo control. Dos puertos solo comparten
nombre si las tres formas coinciden a la vez, y con estos coeficientes la
repeticion mas cercana esta a 49 celdas — unas cuatro mil millas.

Es una garantia geometrica, no probabilistica, y por eso aguanta cualquier
numero de puertos descubiertos. Con el hash anterior (8 x 16 = 128 nombres),
cuarenta puertos ya colisionaban casi seguro y en la carta salian dos "Puerto
de Anclas" indistinguibles. La cabecera lleva genero escrito a mano porque el
adjetivo del medio concuerda con ella ("Cala Larga" pero "Islote Largo"), y los
dos ejes van mezclados en las tres formas porque con la cabecera dependiendo
solo de `cx` un barco navegando en vertical avistaba veinte puertos seguidos
llamados todos "Abra algo".

---

## Meter tus propios pixeles

Ver `assets/README.md`. Resumen: deja un PNG con el nombre que toca y ese
sprite deja de generarse. Ni una linea de codigo.

Lo unico que hay que respetar es la regla 1: **el casco se dibuja con la proa
hacia arriba** y no gira nunca.

Con el barco hay una regla mas, porque son varias capas sobre **el mismo
lienzo de 80x96** y se dibujan todas en el mismo origen: el arte tiene que
venir ya casado entre si, sin recortar. A cambio no hay ni un offset que
ajustar cuando anades una capa.

---

## Balance

Todos los numeros viven en cuatro sitios:

* `src/ship.lua` — velocidad base, desgaste, rancho, curva de ceñida, ritmos de
  cada puesto.
* `src/stations.lua` — plazas por nivel y coste de las mejoras.
* `src/ports.lua` — densidad de puertos, precios, tamano de la taberna.
* `src/crew.lua` — curva de pericia, soldadas y primas de enganche.

Despues de tocar cualquiera de ellos, `lua5.1 tests/test_sim.lua`.

El paseo de cubierta (`src/deck.lua`) no es balance —no cambia un solo numero—
pero sus constantes se comprueban igual: `lua5.1 tests/test_deck.lua`.

---

## Lo que falta

Esto es andamiaje. Lo que esta pensado pero no hecho:

* **Sonido** — no hay `audio_manager` todavia.
* **Tiempo y averias** — el viento rola pero no hay temporales; el casco se
  desgasta a ritmo fijo. El gancho esta en `Ship.rates().wear`, y el mar ya
  sabe ponerse feo: toda la superficie cuelga de `Sea.state`, que hoy solo lee
  la fuerza del viento.
* **Encuentros en el mar** — no hay otros barcos. Cuando los haya, hay que
  resolver la regla 1, y para un barco la salida no es la del agua: un shader
  vale para una textura, no para un dibujo. Toca un sprite por rumbo, que es
  como estuvo hecho el oleaje hasta que paso a shader (doce orientaciones por
  trazo, una cada quince grados) y sigue estando en el historial de
  `src/art.lua` para copiarlo.
* **Comercio real** — hoy solo se vende pescado. La bodega ya tiene capacidad;
  faltan mercancias que valgan distinto en cada puerto.
* **Las islas no hacen nada** — son decorado. No hay colision ni interaccion:
  se navega por encima de ellas.
* **Progresion larga** — no hay meta ni final; el barco mejora y ya.
