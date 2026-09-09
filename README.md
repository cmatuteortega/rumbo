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
love .                      # desde la raiz del proyecto
lua5.1 tests/test_sim.lua   # prueba de la simulacion, sin ventana
lua5.1 tests/test_halyard.lua  # la driza: fisica y geometria
lua5.1 tests/test_reel.lua     # el redal: la pelea, jugada desde el dibujo
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

Y de ahi sale la segunda: **nada del mundo puede tener una orientacion que se
note**. Las olas son trazos, las islas manchas y los puertos manchas con un
fanal; todos se leen igual desde cualquier demora. Si algun dia hay otro barco
en el mar, o se dibuja en ocho rumbos, o rompe la regla.

Las excepciones son cinco —la rosa del timon (`src/compass.lua`), la rueda del
timon (`src/helm.lua`), la driza del velamen (`src/halyard.lua`), el redal de
las redes (`src/reel.lua`) y la carta de marear (`src/screens/chart.lua`)— y
las cinco son legales por la misma razon: **no usan sprites**. Sus agujas,
cabillas, cuerda, cana, pez, puntos y derrotas se pintan con rectangulos de
1x1, asi que apuntan a cualquier angulo sin muestrear nada. La rueda, la driza
y el redal pintan los suyos ademas dentro del `scale()` del mundo, asi que su
madera, su cuerda y su pez tienen el mismo grano que el casco.

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

**3. Nada del mar se guarda.** Olas, rachas, islas, escollos, puertos, precios y
la gente de las tabernas son funcion pura de la posicion, la semilla y el
tiempo, via `Util.hash01`. El mar es infinito y la partida guardada ocupa un
kilobyte.

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
│   ├── crew.lua          # tripulantes
│   ├── ports.lua         # puertos, precios, tabernas
│   ├── sea.lua           # camara y dibujo del mar
│   ├── compass.lua       # la rosa del timon, centrada en la cabecera
│   ├── helm.lua          # la rueda del timon: un cuarto en la esquina de estribor
│   ├── halyard.lua      # la driza del velamen: la cuerda de babor, con fisicas
│   ├── hud.lua           # la cabecera (timon al aire, bloque de estribor) y la bitacora
│   ├── ui.lua            # UI inmediata: botones, filas, hojas
│   └── screens/
│       ├── boot.lua      # genera el arte con barra de progreso
│       ├── voyage.lua    # pantalla principal
│       ├── port.lua      # mercado, taberna, astillero
│       └── chart.lua     # carta de marear: rumbo a un puerto descubierto
└── tests/
    ├── test_sim.lua      # prueba headless de la simulacion
    └── test_halyard.lua  # prueba de la driza (fisica y geometria, con love de mentira)
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

**Los dos mandos no salen a la vez.** No porque se estorben —estan en esquinas
opuestas— sino porque mientras uno esta fuera un toque en cualquier otro sitio
lo recoge: con los dos fuera, tocar uno guardaria el otro.

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


### La pesca: el redal de estribor

El tercer mando que se usa navegando es **una cana**, y sale igual que los otros
dos: tocando su puesto. Tocar las redes larga el redal de `src/reel.lua` por el
bajo de la pantalla —carrete en la esquina de estribor, cana hacia babor— y deja
la hoja del puesto para el segundo toque.

**La cana es la regla del sedal.** Sobre ella corre la silueta del pez: a babor
del todo es el pez con todo el sedal fuera —se va— y a estribor del todo es el
pez en la borda, cobrado. No es una barra de interfaz con otro dibujo: es la
lectura directa de cuanto queda por recoger, que es lo unico que hay que saber
mientras se pelea, y cae donde se esta mirando, que es la mano que rueda.

**El pez tira siempre, se toque o no.** El reposo del carrete no es cero sino
`-run`, la carrera del pez, y de ahi sale la pelea entera:

| lo que se hace | lo que pasa |
|----------------|-------------|
| nada | el carrete se desenrolla solo y el pez se va por babor: la cana entera en unos diez segundos |
| agarrarlo sin rodar | manda el dedo *menos* la carrera del pez, o sea que se sigue perdiendo sedal. Agarrar no es una pausa |
| agarrarlo de golpe | el carrete se PARA: es palmearlo, y es como se corta una arrancada |
| rodar | se le gana terreno a la carrera, hasta donde deja el freno |
| soltar rodando fuerte | el carrete se queda con el giro que llevaba y regala unas decimas antes de que el pez mande otra vez |

**El segmento es la regla del juego.** Sobre la cana hay una banda clara que
cambia de sitio cada pocos segundos: es donde el pez aguanta que se tire de el.
Rodar con el pez **dentro** no cuesta nada; rodar con el pez **fuera** tensa la
linea, y la linea llena se rompe.

**Dentro se cuenta por el cuerpo del pez, no por su centro.** Midiendo por el
centro habia una mentira de las que este juego no se permite: el pez mide once
pixeles de arte, asi que con el centro justo en el canto de la banda el pez se
ve *metido en ella hasta la mitad* —y sin embargo no se ponia de oro y la cana
se tensaba—. Cinco pixeles y medio de "parece que si y el juego dice que no" a
cada lado, y justo en el sitio donde se pelea. Contando por el cuerpo, "el pez
esta en la banda" quiere decir lo que cualquiera diria mirandolo; lo que se
perdio de precision se recupero en **ritmo** (la banda se mueve mas a menudo),
que ademas es mejor sitio para ponerlo: apurar el canto de la banda era una
pelea de pixeles, llegar a la banda antes de que se vaya es una pelea de tiempo,
y esa se juega mirando.

**Y la banda manda de verdad: fuera de ella no se trae al pez.** El freno da
todo lo que tiene con el pez dentro y solo un quinto fuera, asi que fuera de la
banda como mucho se le aguanta. Antes fuera se ganaba casi igual y solo se
pagaba en comba, o sea que la banda no decidia nada: se recogia sin parar y la
unica forma de perder era romper la linea.

**Y se acumula cansancio.** El pez se cansa mientras lo tienes en la banda y lo
olvida despacio cuando se sale, y eso hace dos cosas: **la linea se tensa cada
vez menos** —hasta un 15%— y el pez tira menos. O sea que cuanto mas tiempo
lleva el pez donde tiene que estar, mas barato sale recogerlo *sin doblar la
cana*. Ese es el premio del mando y es lo que hay que aprender. Cortarle una
arrancada a tiempo —que entre en la banda huyendo y recoger de verdad en las
decimas siguientes— mete un pellizco de cansancio de golpe: un solo recurso con
dos formas de llenarlo, paciencia o reflejos. Fueron dos sistemas solapados y
no se leia ninguno. Se ve sin inventar ninguna senal nueva: **el pez se vuelve**,
de morro al carrete, porque un pez que deja de pelear deja de encarar el mar.

**La punta de la cana no se ve.** Se sale del cuadro por babor y el sedal sale
con ella, asi que del aparejo solo se ve el tramo que cae a bordo —igual que
del timon solo se ve un cuarto de rueda— y el anzuelo queda donde tiene que
estar, que es donde no se ve. El recorrido del pez empieza en el canto de babor,
asi que **un pez que se escapa se sale del cuadro**, que dice "se ha ido" mucho
mejor que pararse en una raya. De ahi salen las dos maniobras que pide el
mando, que son las dos que pide una cana de verdad: **atraer** cuando el pez
esta en la banda y **dejarlo ir** —soltar el carrete, que el pez corra hacia
babor— cuando la banda se ha ido por detras de el. Sin la segunda, pescar seria
rodar sin parar.

La banda **se desliza** a su sitio nuevo en dos decimas en vez de aparecer alli:
a este grano un salto de veinte pixeles no se lee como que la banda se ha
movido, sino como que hay otra banda. Y llega **exacta**, por interpolacion con
un parametro acotado, en vez de acercarse para siempre: una banda que deriva
medio pixel repinta su sello entero, que es la misma leccion que costo la driza.

**El carrete tiene freno, y ese es el numero que sostiene el mando.** Un carrete
de verdad lleva freno, y pasado el freno la bobina **resbala**: se sigue moviendo
la manivela y el pez no viene mas rapido, solo se tensa la linea. Aqui igual
(`MAX_GAIN`), y de eso salen dos cosas de balde: pasarse no adelanta nada y
ademas rompe —asi que barrer el pulgar sin mirar pierde siempre, y pierde
ensenando por que— y **se ve resbalar sin dibujar nada nuevo**, porque el
carrete gira lo que da el freno y no lo que pide el dedo, asi que pasado el tope
la manivela se queda atras de la mano. Sin el freno la cuenta salia justa por
los dos lados —rodar acerca el pez y a la vez tensa la linea— y la prueba decia
que ganaba rodar: ocho peces cobrados de ocho a base de barrer. Es exactamente
el tipo de cosa que no se ve jugando un rato.

**La tension no tiene barra: la cana se comba.** Es el indicador que ya existe
en el mundo real y el unico que no hay que aprenderse, y ademas cae encima del
pez, que es donde se esta mirando.

**La tension esta calibrada contra reflejos de persona, y esa es la leccion mas
cara del mando.** `TENSE` llego a estar al doble porque el jugador de mentira
—que reacciona en *un cuadro*, 16 ms— ganaba demasiado facil. Medido despues con
retraso de reaccion realista, a 400 ms **nueve de dieciocho peleas acababan con
la linea rota y ninguna con el pez escapado**: el unico modo de fallo del mando
era el que peor se entiende, y estaba puesto para una maquina. Hoy la curva es
la que toca —atento 14 s, lento 16,5 s, distraido 20 s, mirando otra cosa 29 s—
o sea que **la falta de atencion se paga en tiempo, no en la pieza**, que es lo
que corresponde en un idle. La linea sigue rompiendose: rodando sin parar y sin
hacer caso al rojo revienta en 4,3 s a ritmo normal, con 1,8 s de aviso. La
diferencia es quien la rompe: antes el que jugaba bien y llegaba tarde, ahora
solo el que ignora el aviso.

Y se comba **como una cana, no como una cuerda**. Fue `sin(pi*t)` —un arco con
cero en los dos extremos— y eso dobla el *centro* dejando la punta clavada en el
eje, que es lo que hace un cabo tendido entre dos puntos. Una cana esta empotrada
en el carrete y libre por la punta: el pez tira de la punta, la punta es la que
baja y el arranque sale recto del puno porque ahi la sujeta la mano. Asi que la
flecha es la del voladizo con la carga en el extremo, `f(u) = u²(3-u)/2` con `u`
de 0 en el puno a 1 en la punta —tangente horizontal en el empotramiento y
pendiente creciente hasta la punta—, que es lo que se lee como una cana
doblandose *y aguantando*. Pasado el aviso el sedal se pone **rojo**, y
eso es todo lo que se pinta de mas. La misma idea que el nudo de oro de la
driza: nada de texto donde el propio trasto puede decirlo.

**Y el oro dice lo mismo que en todo el juego** —"esto es lo que hay que
hacer"— en dos sitios: el pez se pinta en oro mientras esta dentro de la banda
(rodar ahora sale gratis) y la manivela se pone de oro mientras hay un pez
enganchado (rodar ahora hace algo). Con la cana en reposo no hay ni una cosa ni
la otra, y ese hueco es parte del mensaje.

**Solo pica con el redal fuera y navegando.** Amarrado no corre la singladura y
tampoco la cana. El pique se sortea con `Util.hash01` y el reloj de la travesia,
asi que no hay nada aleatorio que guardar, y **vibra el movil**: es el unico
aviso de este juego que sale de la pantalla, y hace falta porque el pique es lo
unico que empieza sin que lo empiece el jugador.

**Con la bodega llena se pesca igual**, y es una decision tomada contra el
argumento contrario. El argumento era que cobrar un pez que no cabe es cobrar
para nada, asi que mejor que no picara; pero la bodega llena es justo el estado
en el que se vuelve despues de una ausencia larga, o sea que la pesca a mano se
apagaba sola precisamente cuando mas rato se lleva mirando la pantalla. Pelear
y que no quepa es mal negocio, pero es del jugador; lo que no puede ser es que
el mando se apague sin decir nada. Asi que pica, y `World.landFish` deja linea
de bitacora tambien cuando no entra nada.

**Del sedal cuelga un corcho, y es la regla de la driza al reves.** La driza
cuelga inmovil porque una cuerda colgada esta quieta; un corcho en el agua no lo
esta nunca, y uno que se para esta roto. El aparejo —cana, carrete y forma del
sedal— sigue sin mover un pixel entre pique y pique, y lo unico que vive es el
corcho cabeceando dos pixeles cada dos segundos. No es un capricho: se probo con
el pulgar y ocho segundos de pantalla congelada no se leen como esperar un
pique, se leen como que el juego se ha colgado. Y al picar **el corcho se hunde
y desaparece**, que es la imagen de un pique en cualquier sitio del mundo: asi
el pique se lee tambien en escritorio, donde `love.system.vibrate` no hace nada.

**Y cuando no se puede pescar, lo dice.** `Reel.idle` devuelve el motivo —hoy
solo "amarrado no se pesca"— y se pinta bajo la cana; con la cana pescando ahi
no hay nada, y ese hueco tambien dice lo suyo. Existe porque el mando estaba
roto sin estarlo: amarrado se sacaba el redal, el sedal caia al agua y ahi se
quedaba para siempre, sin pique y sin una sola pista. Y amarrado es donde
*empieza* la partida, asi que era el estado en el que mas facil era
encontrarselo. Un mando que no puede funcionar tiene que decirlo; callarse es lo
mismo que estar averiado. Con el redal fuera, ademas, la columna de estribor no
se dibuja —o sea que el boton de **Zarpar** tampoco—, y un toque en cualquier
sitio recoge la cana y lo devuelve.

**La pelea no se guarda.** Vive entera en el modulo y no toca la simulacion:
`Reel.update` devuelve un *suceso* —pez cobrado, pez perdido, linea rota— que la
travesia traduce a `World.landFish` o a una linea de bitacora. Por eso guardar
el redal con un pez enganchado es perderlo, igual que soltar el movil con la
cana en la mano, y por eso no hay ningun campo nuevo en el estado ni nada que
migrar. Lo que sube a bordo pasa por `stow` como todo lo demas.

**Mejorar las redes afloja la pelea, no la salta.** Mas potencia es banda mas
ancha, pez menos brioso y pieza mas grande: es el pescador el que sabe aguantar
al pez, no el pez el que se cansa. Y la pesca de arrastre del puesto sigue
corriendo igual: el redal es un extra encima, no un sustituto.

**Mientras esta fuera, el bajo de la pantalla es suyo:** las dos columnas de
botones y la bitacora se quitan. La rueda solo se lleva su columna porque cabe
en su esquina; el redal cruza de banda a banda. Se pierde poco: la bitacora se
lee de reojo cuando no pasa nada, y mientras hay un pez en la cana lo que pasa
esta en la cana.

**Entra subiendo por la borda**, desde debajo del canto de abajo, con la misma
curva y los mismos tiempos que la rueda y la driza, y el carrete rueda con la
subida para que se lea como un trasto que sube y no como un panel que desliza.
Como en los otros dos, la animacion es *solo dibujo*: el angulo del dedo se mide
siempre desde el carrete **puesto**, porque midiendolo desde el que sube el
propio deslizamiento rodaria el carrete sin que el dedo se moviera y el pez
vendria solo.

**Y el aparejo en reposo esta inmovil.** Entre pique y pique no se integra nada:
el sedal cuelga con una comba fija, la cana va recta, el carrete no gira y lo
unico que se mueve —aparte del corcho, que es de agua— es un contador que no se
ve. Lo unico que se atenua —la comba del
sedal, el tiron del pique— llega a su valor **exacto** en vez de asintoticamente,
porque a cinco pixeles de pantalla por pixel de arte una cola exponencial no es
suave, es un parpadeo. Es la leccion de la driza, y aqui vuelve entera porque la
cana y el sedal son otra vez un trazo largo: medio pixel de deriva repinta la
pantalla de lado a lado.

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
      │         y si estas mirando, TOCAR LAS REDES saca el redal: el juego
      │           vibra cuando pica y el pez hay que ganarselo rodando
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

### Puestos

Siete, en `src/stations.lua`. Cada uno tiene un gremio, plazas (crecen cada dos
niveles) y una potencia = **nivel + pericia destinada**, y nada mas.

| puesto | gremio | que hace |
|--------|--------|----------|
| Cofa | vigia | alcance de vista, restos a la deriva |
| Carpinteria | carpintero | repara casco gastando madera |
| Velamen | gaviero | velocidad |
| Redes | pescador | pescado de arrastre, y el redal: banda mas ancha, pez menos brioso y pieza mas grande |
| Cocina | cocinero | pescado -> raciones |
| Bodega | estibador | cuanto cabe a bordo, y por tanto cuanto rinde una ausencia |
| Timon | timonel | velocidad de caida al nuevo rumbo |

Un tripulante fuera de su gremio rinde **un tercio**: se puede poner al
cocinero al timon, pero se nota.

Cada puesto tiene un ancla en el lienzo del barco (`deckX`/`deckY`, fracciones)
y ahi se toca. Tres de ellos **no abren su hoja al primer toque**, porque sacan
un mando: el timon saca la rueda, el velamen larga la driza y las redes largan
el redal, y los tres dejan la hoja para el segundo toque. Es el orden de la
frecuencia —se corrige el rumbo, se cambia el trapo y se pesca cien veces por
cada vez que se destina a alguien a esos puestos— y el precio es un toque de
mas para lo que se hace poco. Los tres que ya tienen arte estan clavados sobre su cacharro
—la cocina en el fogon, las redes en el aparejo, el velamen al pie del palo—
porque un aro dorado a cinco pixeles de su cacharro se lee como un error. La
bodega es la unica que se dibuja sola: hasta que exista su PNG, `gen.shipHold`
le pinta una trampilla leyendo esas mismas dos fracciones.

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

---

## Lo que falta

Esto es andamiaje. Lo que esta pensado pero no hecho:

* **Sonido** — no hay `audio_manager` todavia.
* **Tiempo y averias** — el viento rola pero no hay temporales; el casco se
  desgasta a ritmo fijo. El gancho esta en `Ship.rates().wear`.
* **Encuentros en el mar** — no hay otros barcos. Cuando los haya, hay que
  resolver la regla 1 (o ocho rumbos por barco, o dibujarlos con `pixelart`).
* **Mas de un pez** — el redal cobra pescado a secas. Lo natural es que haya
  piezas distintas (una pieza grande que se venda aparte), pero eso es un
  recurso nuevo: campo en `state.res`, fila en el HUD, precio en el mercado y
  entrada en `DEFAULTS`.
* **Comercio real** — hoy solo se vende pescado. La bodega ya tiene capacidad;
  faltan mercancias que valgan distinto en cada puerto.
* **Las islas no hacen nada** — son decorado. No hay colision ni interaccion:
  se navega por encima de ellas.
* **Progresion larga** — no hay meta ni final; el barco mejora y ya.
