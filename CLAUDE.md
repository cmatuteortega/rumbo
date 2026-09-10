# CLAUDE.md

Guia para Claude Code (claude.ai/code) al trabajar en este repositorio.

**Rumbo** es un idle de navegacion en vista cenital, vertical, para movil,
hecho en LÖVE 11.x. `README.md` es el documento de diseno y explica *por que*
cada decision es la que es: leelo antes de cambiar comportamiento, y
actualizalo cuando el comportamiento cambie.

Todo el codigo y los comentarios estan en **castellano**. Mantenlo.

---

## Ejecutar y comprobar

```sh
love .                          # el juego
lua5.1 tests/test_sim.lua       # simulacion, sin ventana - correr tras TODO cambio de balance
lua5.1 tests/test_deck.lua      # la gente de cubierta - tras tocar src/deck.lua o las caras
lua5.1 tests/test_halyard.lua   # la driza: fisica y geometria - tras tocar src/halyard.lua
lua5.1 tests/test_sea.lua       # el mar: orientacion y estela - tras tocar src/sea.lua
```

`test_sim.lua` prueba modulos que no requieren `love` y por eso corre tal cual.
Los otros dos prueban DIBUJO —viven en pixeles de arte— asi que montan un
`love` de mentira que apunta lo que se pinta y miden sobre eso.

`test_halyard.lua` lee del dibujo el nudo, la comba y el arco. Esta ahi porque
los dos fallos de la driza (doblarse sobre si misma y no estarse quieta en
reposo) no se ven mirando la pantalla un rato, solo midiendo.

`test_sea.lua` lee que sprite de cada familia se ha usado y donde. Vigila cuatro
cosas que tampoco se ven a ojo: que **ni una** llamada pase rotacion (el love
de mentira peta si alguien lo intenta), que las crestas y las rachas salgan
siempre a noventa grados y giren con el rumbo, que con viento flojo haya de
verdad menos trazos y ninguno blanco, y que el agua se mueva por si sola dentro de la
horquilla (`Sea.WAVE_DRIFT` y `Sea.GUST_DRIFT`): ni mas deprisa que lo que anda
el barco — a ojo un mar corriendo se lee como viento, y solo con el numero
delante se ve que lo que dice es que el barco va marcha atras — ni tan despacio
que se congele, que amarrado el barco no cruza el campo y el mar se queda
quieto. Ademas
mide que la estela se abra con lo que el barco anda y no con el reloj, y que se
quede corta cuando no se corre.
`test_deck.lua` tambien: `src/art.lua` no llama a `love` hasta que se le pide un
sprite, asi que la geometria del casco y la reserva de caras se miden sin
ventana. Esta ahi porque un tripulante que sale por la borda pasa cada varios
minutos, en la punta de un seno, y con el trapo tapando media cubierta no se
pilla mirando.
`test_halyard.lua` prueba DIBUJO —la driza vive en pixeles de arte— asi que se
monta un `love` de mentira que apunta lo que se pinta, y del dibujo se leen el
nudo, la comba y el arco. Esta ahi porque los dos fallos de la driza (doblarse
sobre si misma y no estarse quieta en reposo) no se ven mirando la pantalla un
rato, solo midiendo.

No hay build ni gestor de dependencias. Tras una edicion amplia:

```sh
for f in main.lua conf.lua lib/*.lua src/*.lua src/screens/*.lua; do
  luac5.1 -p "$f" || echo "FALLA $f"
done
```

---

## Reglas no negociables

Romper cualquiera de estas se ve en pantalla al instante.

**Nada se dibuja girado.** Ninguna llamada pasa rotacion a
`love.graphics.draw`. La camara va con el barco: la proa apunta siempre arriba,
el barco esta quieto en el centro y lo que gira es el mar (`Sea.project`). Las
excepciones son cinco —la rosa del timon (`src/compass.lua`), la rueda del
timon (`src/helm.lua`), la driza del velamen (`src/halyard.lua`), el redal de
las redes (`src/reel.lua`) y la carta de marear (`src/screens/chart.lua`)— y
las cinco son legales porque no usan sprites: pintan agujas, cabillas, cuerda,
cana, puntos y derrotas con rectangulos de 1x1. La carta es ademas la unica
pantalla con el norte arriba, y eso es a proposito: un papel sobre una mesa no
gira con el barco.

Si anades algo con orientacion, tienes dos salidas y ninguna es rotar en draw:
**un sprite por rumbo**, o dibujarlo con primitivas como el timon.

El mar toma la primera. Las islas y los puertos siguen siendo manchas sin
direccion, pero las CRESTAS si tienen una —se peinan contra el viento, asi que
van en diagonal cuando el viento va en diagonal— y por eso cada trazo esta
pintado doce veces, una cada quince grados (`Art.SEA_DIRS`), y `src/sea.lua`
elige la orientacion por el angulo en pantalla. Doce, y no ocho, porque a este
tamano de pixel con ocho se ve saltar el mar al virar.

**Solo pixeles enteros.** El mundo se dibuja dentro de un `scale()` entero
(`Constants.ART`) y toda posicion se redondea. `Art.draw`/`Art.drawCentered`
ya hacen el `math.floor`. Filtro `nearest` en todas partes.

**El lienzo no es 540x960.** El ancho si; el alto depende de la pantalla. Nada
se posiciona contra un 960 escrito a mano: se lee `Constants.GAME_HEIGHT`,
`ART_H` y los margenes seguros `SAFE_TOP/BOTTOM/LEFT/RIGHT`.

**La paleta es cerrada.** Todo color sale de `src/palette.lua`. Ni un RGB
suelto. El unico alpha del juego es el velo de las hojas, y esta comentado
donde se usa.

**La simulacion no toca love.** `world.lua`, `ship.lua`, `stations.lua`,
`crew.lua`, `ports.lua` y `util.lua` no pueden requerir `love` ni
`love.math.random`. Es lo que permite `tests/test_sim.lua` y lo que hace que
la vuelta a la partida use el mismo codigo que el juego en vivo.

**Un campo nuevo en el estado va tambien a `DEFAULTS`.** Las partidas guardadas
sobreviven a los cambios porque `World.migrate` rellena lo que falte desde esa
tabla, y se llama al cargar (`src/session.lua`). Anadir un campo al estado y
olvidarse de `DEFAULTS` hace que la siguiente partida guardada reviente al
cargarla — que es exactamente como se rompio la version 1. El test recorre
todos los campos borrandolos de uno en uno.

Las listas (`crew`, `log`) quedan fuera de `DEFAULTS` a proposito: rellenarlas
desde una plantilla resucitaria tripulantes despedidos.

**Nada aleatorio se guarda.** Toda la variacion sale de `Util.hash01` con
posicion, semilla o tiempo como entrada. Si te ves anadiendo una semilla al
estado guardado, probablemente hay una forma de derivarlo.

**`World.step` es correcto a cualquier `dt`.** Se llama con 1/30 jugando y con
2 s al ponerse al dia. Nada dentro puede depender del tamano del paso; el
viento, en particular, es funcion pura de `state.time`.

**Los ritmos se anulan en `Ship.rates`, no en `World.step`.** En puerto no corre
la singladura, y la forma de conseguirlo es multiplicar los ritmos por cero
donde se calculan. Asi el HUD, que los pinta tal cual, sigue sin mentir. La
regla general: si el HUD dice "+14,4 pescado/min", eso tiene que ser
exactamente lo que se acumula.

**Nada anade a `state.res` directamente.** Todo lo que sube a bordo pasa por
`stow()` en `world.lua`, que respeta el tope de bodega (mercancia) o el de
pertrechos (madera). Saltarselo es como se rompe el techo de una ausencia.

---

## Arquitectura en un parrafo

`main.lua` monta el lienzo virtual y reparte la entrada. `lib/screen_manager`
tiene tres pantallas: `boot` (genera el arte con barra de progreso), `voyage`
(el mar, el barco, el timon) y `port` (mercado, taberna, astillero).
`src/session.lua` guarda la unica copia del estado y el autoguardado.
`src/world.lua` es la simulacion entera — estado plano, `World.step`,
`World.catchUp` y las acciones. `src/ship.lua` convierte estado en ritmos: ahi
esta todo el balance. La cuarta pantalla, `chart.lua`, es la carta de marear:
ensena los puertos descubiertos y fija rumbo a uno (`World.setCourse`), y a
partir de ahi el timonel corrige solo y el barco atraca al llegar. El dibujo
del mundo es `src/sea.lua` (camara + mar) mas `voyage.lua` (barco y cubierta);
el de la interfaz es `src/ui.lua` (inmediata) y `src/hud.lua`. La tripulacion
que se ve andar por el barco es `src/deck.lua`, y es SOLO dibujo: cada uno saca
su cara de la reserva de `assets/crew_pjNN.png` segun el hash de su nombre
(`Crew.face`) y su paseo es funcion pura de `state.time`, sin estado que
guardar. Los destinados se remueven en su puesto y los que no tienen destino
pasean el barco entero, por dentro de la silueta de `Art.hullHalf` y siempre
por DEBAJO del trapo.

El mar de `sea.lua` no guarda nada y todo sale del viento y de la velocidad. Las
crestas se peinan CONTRA el viento y las rachas corren A FAVOR, asi que las dos
familias van siempre a noventa grados y giran con el rumbo; la fuerza del viento
—estirada a [0,1] en `Sea.state`, porque el rango del viento es corto— decide
cuantos trazos hay, como de grandes y si alguno rompe en blanco, y un ruido de
manchas (`SWELL_CELL`) hace que un trozo de mar este picado y el de al lado
liso, y el agua se mueve MUY poco por si sola
(`Sea.WAVE_DRIFT`, `Sea.GUST_DRIFT`: siete decimas de pixel por segundo la ola)
porque en pantalla se le suma lo que el barco cruza el campo, que son diez, y es
el sumando grande — un mar que corre por su cuenta no se lee como viento sino
como que el barco cia. Con viento flojo quedan cuatro rizos y ni una racha.
Los campos que
desfilan (olas, rachas, y las manchas de agua honda) no se reciclan con un
modulo —eso da un tiron cada vuelta— sino desplazando el punto alrededor del
cual se barren las celdas. Y lo andado por ese punto se INTEGRA cuadro a cuadro
en `Sea.update`, nunca `state.time` por el ritmo de ahora: como el viento rola y
refresca sin parar, multiplicar el tiempo vivido por el ritmo del momento
reescribe hacia atras el desfile entero y el mar ACELERA con las horas de
partida (a las ocho, 39,7 px/s en vez de 0,7). `tests/test_sea.lua` lo mide a
0, 1, 8 y 72 horas. Y los trazos no se pintan segun se recorren: se
apuntan por sprite y se sueltan al final todos los de uno seguidos, porque con
treinta y seis sprites entremezclados al azar cada trazo rompia el envio del
anterior.

La estela ES el bigote de la roda, estirado hacia atras: las crestas
transversales de un barco visto desde arriba son la misma uve, quedando atras y
abriendose, asi que hay un solo dibujo en una escalera de cinco anchos
(`sea.wake1..5`). El ancho de cada arco sale de lo que el barco ha ANDADO desde
que se solto (`state.distance`, no el reloj), asi que la uve se abre siempre al
mismo angulo y en una virada se dobla sola; lo que decide la VELOCIDAD es cuanto
llega a durar, y por eso en el ojo del viento no queda mas que un hervor contra
el codaste. Los arcos son lo unico del mar que se pinta ENCIMA del barco
(`Sea.drawWake`, que llama `voyage.lua` despues del casco): el agua que revuelve
la popa esta contra la popa, y con la estela debajo del casco habia que
sembrarla media eslora mas atras para que asomara, con lo que salia despegada
del barco. Delante, el bigote de la roda en tres tamanos y unas salpicaduras a
sotavento; los dos callan por debajo de `WORKING`, que es donde un barco deja de
levantar agua.

Los mandos que se usan navegando salen tocando SU puesto en cubierta, no de la
columna de botones, y por eso el timon y el velamen dejan su hoja para el
segundo toque. La driza de `src/halyard.lua` es el del trapo: una cuerda con
fisicas (el nudo con verlet y el largo de reposo en un muelle) que cuelga por
la esquina de arriba a babor y se maneja como una persiana. El nudo es el
cuerpo -- un pendulo colgado del ancla -- y la cuerda va detras, tensa
entre ancla y nudo: colocando cada nodo colgado del anterior salen doce
pendulitos que zumban y el balanceo lo manda el tramo mas corto. En reposo esta
INMOVIL, y eso pide tres cosas: la cuerda se deriva en vez de simularse (doce
nodos moviendose media fraccion de pixel hacen hervir el dibujo entero), el
balanceo se amortigua por zeta (por vaiven y no por cuadro, o la cuerda corta
tarda mas que la larga) y los ultimos pixeles se ANDAN de uno en uno en vez de
atenuarse, porque una cola exponencial a este grano son decimas de segundo de
pasitos salteados y la torcida los multiplica. Lo que se lee como temblor no es
cuanto se mueve, es que cambie de sentido moviendose poco. Con
trapo largo el nudo queda a la altura de la rosa y se arrastra hacia abajo para
tomar rizos; con rizos cuelga a media pantalla y un tiron corto y soltar larga
trapo, rebotando. El largo de la cuerda ES el indicador —no hay lectura, solo
el nudo en oro cuando soltar ya haria algo— y el trapo se pide con
`World.setTrim`, no alternando: la driza es la UNICA forma de cambiarlo, el
boton de estribor que lo alternaba ya no existe y `World.toggleTrim` se fue con
el. Los tres mandos no salen a la vez, porque mientras uno esta fuera cualquier
otro toque lo recoge.

El tercero es el redal de `src/reel.lua`: tocar el puesto de Redes larga una
cana por la esquina inferior de estribor —la misma que la rueda, y solo la
exclusion lo permite— y deja su hoja para el segundo toque. Es el unico mando
que NO pide nada a la simulacion mientras se usa: la pelea entera vive en el
modulo y nada de ella se guarda, asi que cerrar la app con un pez enganchado es
perderlo. `Reel.update` devuelve un suceso —pez cobrado, perdido o linea rota—
y la travesia lo traduce a `World.landFish` (que pasa por `stow`, con su linea
de bitacora cuando no cabe) o a `World.lostFish`. El pez corre sobre la cana,
que es la regla del sedal; la banda clara es donde el pez aguanta que se tire y
rodar fuera de ella tensa la linea; la tension no tiene barra —la cana se
comba y el sedal se pone rojo— y el oro dice lo de siempre. En reposo esta
inmovil salvo el corcho, que es el reverso de la leccion de la driza: una
cuerda colgada esta quieta, un corcho no lo esta nunca, y una pantalla
identica cuadro tras cuadro se lee como colgada. Mientras esta fuera el bajo
entero es suyo: se guardan las dos columnas de botones y la bitacora.

Gobernar tiene dos mandos y no uno: la rosa de la cabecera (`src/compass.lua`)
para *elegir* rumbo de un toque, y la rueda de `src/helm.lua` — un cuarto de
rueda con el centro en la esquina inferior de estribor — para *corregirlo*
arrastrando. La rueda sale al tocar el puesto del timon en cubierta y la hoja
de ese puesto pasa al segundo toque; mientras se ve, la esquina es suya (sin la
columna de botones de estribor) y la rosa se queda inerte. Entra y sale rodando
desde fuera de la pantalla, con el giro atado al deslizamiento y una sola curva
para los dos sentidos, y esa animacion es solo dibujo: el gobierno mide siempre
desde el centro puesto. Se dibuja con primitivas, en la escala de arte y con el
contorno negro de 1px de los sprites: cada pieza dos veces, engordada en
`Palette.ink` y luego en su color.

`src/art.lua` es el registro de sprites: cada uno se genera por codigo salvo
que exista el PNG correspondiente en `assets/`, en cuyo caso gana el archivo.

---

## Extender

* **Puesto de cubierta**: fila en `Stations.list` (con `deckX`/`deckY` como
  **fraccion** del casco, no pixeles), un icono en `src/art.lua`, y su caso en
  `Ship.rates` y en `readout()` de `voyage.lua`. Un puesto ya NO trae sprite de
  tripulante: la cara la reparte `Crew.face` desde la reserva.
* **Recurso**: campo en `state.res` (`World.new`), icono, fila en `RESOURCES`
  de `hud.lua` y lo que lo produzca o gaste en `Ship.rates`/`World.step`.
* **Sprite**: fila en `SPRITES` de `src/art.lua` con su generador, y su entrada
  en la tabla de `assets/README.md`. Si lo que anades tiene ORIENTACION, no lo
  rotes: registralo como familia, en el bucle de `SEA_DIRS`, y elige con
  `Sea.orient`.
* **Mar**: los trazos en `src/art.lua` (`gen.crest*`), el reparto en
  `drawWaves` de `src/sea.lua` — cuantos hay (`density`), cual sale (`grade`) y
  como se mueven. La velocidad del desfile NO se toca a ojo: sale de
  `Sea.WAVE_DRIFT`/`Sea.GUST_DRIFT` y se mide contra `Ship.BASE_SPEED`. La mezcla importa mas que cada trazo: si la ola corriente
  lleva color claro, la pantalla se llena de marcas brillantes iguales y el mar
  se lee como LLUVIA. El blanco es solo de las rompientes, y sueltas. Correr
  `tests/test_sea.lua` despues.
  en la tabla de `assets/README.md`.
* **Cara de tripulante**: subir `Crew.FACES` y dejar el `assets/crew_pjNN.png`
  que toque. `src/art.lua` las registra en bucle contra esa constante, asi que
  no hay lista que tocar; lo que si hay que dejar es respaldo generado, porque
  el juego tiene que arrancar con `assets/` vacio. `tests/test_deck.lua`
  comprueba las dos cosas.
* **Pantalla**: modulo con las funciones que necesite (`enter`, `update`,
  `draw`, `press`, `move`, `release`, `keypressed`, `resize`) y alta en el
  `ScreenManager.init` de `main.lua`.
* **Balance**: `src/ship.lua` (ritmos, tope de bodega, curva de ceñida),
  `src/stations.lua` (plazas, costes, `holdCapacity`), `src/ports.lua` (precios,
  densidad), `src/crew.lua` (pericia y soldadas). Correr la prueba despues, y
  ademas simular una ausencia larga: casi todos los desequilibrios de este juego
  solo se ven a ocho horas.
* **Nombres de puerto**: las listas de `src/ports.lua` no pueden tener elementos
  repetidos (dos entradas iguales con indices distintos rompen la unicidad), y
  si se tocan los coeficientes de `portName` hay que **volver a medir** a que
  distancia queda la repeticion mas cercana. Que "parezca aleatorio" no es el
  criterio; el test barre 40x40 celdas.

---

## Estilo

Los comentarios explican **por que** algo es como es — el compromiso, el bug
que evita, la sensacion que produce — en vez de repetir lo que hace el codigo.
Cada modulo abre con un parrafo que dice lo que es. Manten ese tono; un cambio
que invalide uno de esos parrafos deberia actualizarlo. Los numeros que
codifican una decision de diseno se documentan en `README.md` y no se tocan a
la ligera.
