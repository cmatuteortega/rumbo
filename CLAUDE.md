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
lua5.1 tests/test_halyard.lua   # la driza: fisica y geometria - tras tocar src/halyard.lua
lua5.1 tests/test_reel.lua      # el redal: la pelea - tras tocar src/reel.lua
```

`test_sim.lua` prueba modulos que no requieren `love` y por eso corre tal cual.
`test_halyard.lua` prueba DIBUJO —la driza vive en pixeles de arte— asi que se
monta un `love` de mentira que apunta lo que se pinta, y del dibujo se leen el
nudo, la comba y el arco. Esta ahi porque los dos fallos de la driza (doblarse
sobre si misma y no estarse quieta en reposo) no se ven mirando la pantalla un
rato, solo midiendo.

`test_reel.lua` monta el mismo `love` de mentira, pero apuntando tambien EL
COLOR de cada rectangulo, y con eso PELEA: un jugador de mentira lee del dibujo
las tres unicas senales que tiene el mando —donde esta el pez, si esta de oro
(en la banda) y si el sedal esta rojo (la linea va a romperse)— y tiene que
cobrar peces sin mirar una sola variable del modulo. Si cobra, el dibujo lleva
de verdad todo lo que hace falta para jugar. Esta ahi porque los desequilibrios
de una pelea son marginales por los dos lados —rodar acerca el pez y a la vez
tensa la linea— y no se deciden leyendo el codigo: la primera version se ganaba
barriendo el pulgar sin mirar, y solo lo dijo la prueba.

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
el barco esta quieto en el centro y lo que gira es el mar (`Sea.project`). Por
eso nada del mundo puede tener una orientacion que se note — las olas son
trazos y las islas manchas. Las excepciones son cinco —la rosa del timon
(`src/compass.lua`), la rueda del timon (`src/helm.lua`), la driza del velamen
(`src/halyard.lua`), el redal de las redes (`src/reel.lua`) y la carta de
marear (`src/screens/chart.lua`)— y las
cinco son legales porque no usan sprites: pintan agujas, cabillas, cuerda,
cana, pez, puntos y derrotas con rectangulos de 1x1. La carta es ademas la
unica pantalla con el norte arriba, y eso es a proposito: un papel sobre una mesa no gira con
el barco.

Si anades algo con proa (otro barco), tienes dos salidas y ninguna es rotar en
draw: ocho sprites de rumbo, o dibujarlo con primitivas como el timon.

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
el de la interfaz es `src/ui.lua` (inmediata) y `src/hud.lua`.

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

El tercero es el REDAL de `src/reel.lua`, que sale tocando las redes y ocupa el
bajo entero: carrete a estribor, cana hacia babor y sedal cayendo al agua, asi
que mientras esta fuera la travesia se guarda las dos columnas de botones y la
bitacora. La cana ES la regla del sedal y sobre ella corre la silueta del pez:
a babor se escapa, a estribor se cobra. La pelea no toca la simulacion ni se
guarda -- vive entera en el modulo y `Reel.update` devuelve un SUCESO (`catch`,
`gone`, `snap`) que la travesia traduce a `World.landFish` o a una linea de
bitacora -- asi que cerrar la app con un pez enganchado es perderlo. El pez
tira SIEMPRE, se toque o no: el reposo del carrete no es cero sino la carrera
del pez, con el dedo encima manda el dedo menos esa carrera (quedarse quieto
agarrando no es una pausa) y al soltar el carrete se queda con el giro que
llevaba y se relaja hacia la carrera, que es como se escapa. Sobre la cana hay
una BANDA que cambia de sitio cada pocos segundos: rodar con el pez dentro es
gratis y rodar fuera tensa la linea, y de ahi salen las dos maniobras del mando
--atraer y dejarlo ir--. La tension no tiene barra: la cana se COMBA, y el
sedal se pone rojo antes de romperse. Y el carrete tiene FRENO (`MAX_GAIN`):
pasado el tope la bobina resbala, el pez no viene mas rapido y solo se tensa la
linea, que es lo unico que impide que el mando se gane barriendo el pulgar --
la prueba lo midio antes de que existiera el freno y decia ocho de ocho.

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
  **fraccion** del casco, no pixeles), un sprite `crew.*` y un icono en
  `src/art.lua`, y su caso en `Ship.rates` y en `readout()` de `voyage.lua`.
* **Recurso**: campo en `state.res` (`World.new`), icono, fila en `RESOURCES`
  de `hud.lua` y lo que lo produzca o gaste en `Ship.rates`/`World.step`.
* **Sprite**: fila en `SPRITES` de `src/art.lua` con su generador, y su entrada
  en la tabla de `assets/README.md`.
* **Pantalla**: modulo con las funciones que necesite (`enter`, `update`,
  `draw`, `press`, `move`, `release`, `keypressed`, `resize`) y alta en el
  `ScreenManager.init` de `main.lua`.
* **Pesca**: la pelea entera esta en las constantes de la cabecera de
  `src/reel.lua` (`MAX_GAIN`, `RUN`, `TENSE`, `SEG_*`, `FISH_*`). Correr
  `tests/test_reel.lua` despues: lo que hay que mirar no es que pase, es lo que
  imprime -- cuantos peces cobra el jugador de mentira y cuanto tarda.
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
