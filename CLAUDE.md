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
lua5.1 tests/test_sea.lua       # el mar - tras tocar src/sea.lua o src/surface.lua
```

`test_sim.lua` prueba modulos que no requieren `love` y por eso corre tal cual.
Los otros dos prueban DIBUJO —viven en pixeles de arte— asi que montan un
`love` de mentira que apunta lo que se pinta y miden sobre eso.

`test_halyard.lua` lee del dibujo el nudo, la comba y el arco. Esta ahi porque
los dos fallos de la driza (doblarse sobre si misma y no estarse quieta en
reposo) no se ven mirando la pantalla un rato, solo midiendo.

`test_sea.lua` lee lo que se pinta y, desde que el agua es un shader, tambien
los UNIFORMES que se le mandan: ahi viven la direccion del peinado y la cuenta
de espuma, asi que el mar se mide sin tarjeta grafica. Vigila cuatro cosas que
no se ven a ojo: que **ni una** llamada pase rotacion (el love de mentira peta
si alguien lo intenta), que el eje largo del campo caiga justo donde cae el
viento en pantalla y el corto lo cruce en angulo recto, que con viento flojo
haya de verdad menos espuma y que en el agua libre el blanco sea IMPOSIBLE, y
que el agua desfile a sotavento y corra bajo el barco cuando anda. De la estela
mide lo suyo: que la calle sea la manga del casco DIBUJADO, que la V acabe en
punta en la roda, que se abra con lo que el barco anda y no con el reloj, y que
virando la derrota se salga de la crujia.
`test_deck.lua` tambien: `src/art.lua` no llama a `love` hasta que se le pide un
sprite, asi que la geometria del casco y la reserva de caras se miden sin
ventana. Esta ahi porque un tripulante que sale por la borda pasa cada varios
minutos, en la punta de un seno, y con el trapo tapando media cubierta no se
pilla mirando.
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

Si anades algo con orientacion, tienes tres salidas y ninguna es rotar en draw:
**un sprite por rumbo**, dibujarlo con primitivas como el timon, o calcularlo
por pixel con un shader.

El agua toma la tercera (`src/surface.lua`): un shader no muestrea una rejilla
de pixeles, la evalua, asi que el oleaje puede peinarse a cualquier angulo sin
deshacerse. Las islas y los puertos siguen siendo manchas sin direccion y por
eso les basta un sprite. Para un DIBUJO con orientacion —un barco enemigo— la
buena sigue siendo la primera: un sprite por rumbo. El oleaje estuvo asi hasta
que paso a shader (doce trazos por familia, uno cada quince grados) y el
historial de `src/art.lua` tiene el patron.

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
del mundo es `src/sea.lua` (camara, estela, islas) mas `src/surface.lua` (el
agua, por shader) mas `voyage.lua` (barco y cubierta); el de la interfaz es `src/ui.lua` (inmediata) y `src/hud.lua`. La tripulacion
que se ve andar por el barco es `src/deck.lua`, y es SOLO dibujo: cada uno saca
su cara de la reserva de `assets/crew_pjNN.png` segun el hash de su nombre
(`Crew.face`) y su paseo es funcion pura de `state.time`, sin estado que
guardar. Los destinados se remueven en su puesto y los que no tienen destino
pasean el barco entero, por dentro de la silueta de `Art.hullHalf` y siempre
por DEBAJO del trapo.

La superficie es `src/surface.lua`: un voronoi de espuma calculado por pixel en
un lienzo a escala de ARTE (asi cada invocacion es un pixel del juego y la
rejilla sale cuadrada sola), con la paleta cerrada en cinco escalones y ni un
color entre medias. El campo se mide en dos ejes, uno a lo largo del viento y
otro cruzado, y el cruzado mide MAS mundo por celda: de ahi salen las vetas de
espuma cruzadas al viento. La fuerza del viento —estirada a [0,1] en
`Sea.state`, porque el rango del viento es corto— decide cuanto se estiran las
vetas, cuanta espuma hay y si puede haber blanco; en calma el escalon del blanco
se manda por encima de UNO, asi que no es que salgan pocas rompientes: no cabe
ninguna. Todo eso se calcula en Lua (`Surface.frame`) y se manda como
uniformes, que es lo que permite medirlo sin ventana.

Dos cosas del shader parecen rarezas y no lo son. Los hashes muerden la celda en
**modulo** porque a las pocas horas de singladura las coordenadas del mundo se
quedan sin decimales y el mar hierve. Y el origen del campo se **arrastra**
entre fotogramas (`Surface.update`, con lo que anda el barco mas lo que desfila
el agua) en vez de calcularse desde `state.x`: el eje del campo gira con el
viento, y proyectar una posicion enorme sobre un eje que rola manda el mar
disparado de lado en cuanto el viento rola un grado.

La estela va DENTRO del agua y no encima: `src/sea.lua` le manda al shader la
derrota (`wakeTrack` — los puntos por donde ha pasado el espejo, proyectados a
pantalla, con lo andado desde cada uno y lo que le queda), y el shader mide la
distancia de cada pixel a esa polilinea. De ahi salen el SURCO (dentro de la
calle el campo se aplasta: es mar quitado, no espuma anadida), el HERVOR de popa
y los BRAZOS de la V, que se abren con lo que el barco ANDA (`state.distance`,
no el reloj) y por eso se doblan solos en una virada. La calle se cierra en
punta en la roda —de ahi que la V acabe en pico delante de la proa— y por detras
mide la MANGA ENTERA del sprite, leida de `Art.HULL_BOX`. Los brazos van
multiplicados por la veta del propio oleaje para que salgan rotos: una linea
limpia a este grano se lee como pintada encima. Ya no hay bigote de proa —la
punta de la V lo es— y lo unico que sigue siendo sprite son las salpicaduras, a
sotavento, porque una gota esta en el AIRE y no en el agua. La espuma de la
estela calla por debajo de `WORKING` (`workFraction`), que es donde un barco
deja de levantar agua; el surco no del todo, porque el casco sigue metido.

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
  rotes: un sprite por rumbo, registrados en bucle.
* **Mar**: `src/surface.lua`. El balance —cuanta espuma da cada viento, cuanto
  se estiran las vetas, donde caen los escalones de color— esta en
  `Surface.frame`, en Lua, y el shader solo evalua; la forma de la espuma (el
  ancho de la veta, la octava fina, la sombra del dorso) esta en el GLSL. Vale
  para los dos: la mezcla importa mas que cada trazo, y si la mayoria de los
  pixeles claros suben de color la pantalla se llena de marcas brillantes
  iguales y el mar se lee como LLUVIA. El blanco es de las rompientes y va
  suelto. Correr `tests/test_sea.lua` despues.
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
