# assets/

Aqui van **tus** pixeles.

Mientras esta carpeta este vacia, el juego genera todos los sprites al
arrancar (`src/art.lua`). En cuanto aparece un PNG con el nombre de la tabla,
ese sprite deja de generarse y se carga el archivo: no hay que tocar codigo,
ni registrar nada, ni reiniciar mas que el juego.

Al arrancar se imprime en consola cuales se han cogido de aqui:

```
[arte] 3 sprites de assets/, 24 generados
  assets/ -> ship.hull
  ...
```

## Reglas

* **PNG con transparencia**, sin capas ni perfil de color raro.
* **Un pixel del PNG es un pixel de arte.** El juego los escala por 5 (entero,
  filtro `nearest`); no hagas tu el escalado ni entregues el sprite ya escalado,
  que entonces sale enorme y borroso. Si quieres que algo se vea mas grande, el
  sitio es este: mas pixeles en el PNG, no un escalado en el dibujo.
* **Paleta**: no es obligatoria, pero `src/palette.lua` es la que usa todo lo
  demas. Si te sales mucho, tu sprite va a cantar contra el mar.
* **El tamano puede variar.** El juego usa el tamano real del PNG. Cambiar la
  proporcion del casco esta bien: los anclajes de cubierta de
  `src/stations.lua` son fracciones, no pixeles, y se recolocan solos. Lo que
  *no* se recoloca solo es el aire alrededor del casco: si redibujas el barco
  con otro margen hay que volver a medir `Art.HULL_BOX` en `src/art.lua`.
* **Nada se dibuja girado** (ver `src/sea.lua`). El barco se dibuja **con la
  proa hacia ARRIBA** y no rota nunca: lo que gira es el mar. Dibuja el casco
  mirando al norte del PNG.

## El barco: una pila de capas

El barco no es un sprite, son varios **sobre el mismo lienzo de 80x96**. Todos
se dibujan en el mismo origen, asi que el arte tiene que venir ya casado: el
fogon donde va el fogon, la verga asomando por fuera de la borda. No hay
offsets que ajustar, y por eso tampoco se pueden recortar los PNG.

El **numero del final del archivo es la prioridad**: 1 arriba, 3 abajo. Los
canones llevan 3 porque van *debajo* del casco y de fuera de la borda solo
asoman las bocas.

El casco ocupa 48x82 dentro de esos 80x96, centrado a lo ancho y empezando
cinco filas abajo (`Art.HULL_BOX`). El resto es aire para las vergas y las
bocas de los canones.

| id | archivo | z | estado |
|----|---------|---|--------|
| `ship.cannons` | `assets/cannons3.png` | 3 | registrado, **sin dibujar**: no hay artilleria |
| `ship.hull` | `assets/ship2.png` | 2 | |
| `ship.hold` | `assets/bodega1.png` | 1 | **falta**: se genera una trampilla provisional |
| `ship.galley` | `assets/cook1.png` | 1 | |
| `ship.nets` | `assets/fish1.png` | 1 | |
| `ship.sails` | `assets/sails1.png` | 1 | lleva el palo dentro |
| `ship.sailsReef` | `assets/sails_reef1.png` | 1 | **falta**: se genera, y canta |
| `ship.anchor` | `assets/anchor1.png` | 1 | solo a la vista con el barco amarrado |

Las capas sin generador (`ship.cannons`, `ship.galley`, `ship.nets`,
`ship.anchor`) son **opcionales**: si borras el PNG, esa capa deja de existir
y no pasa nada mas. El arranque las lista en consola con `falta ->`.

## Sprites

| id | tamano | archivo |
|----|--------|---------|
| `sea.wave` | 7x2 | `assets/sea_wave.png` |
| `sea.ripple` | 4x1 | `assets/sea_ripple.png` |
| `sea.gust` | 11x3 | `assets/sea_gust.png` |
| `sea.foam` | 3x3 | `assets/sea_foam.png` |
| `sea.island` | 40x32 | `assets/sea_island.png` |
| `sea.rock` | 10x8 | `assets/sea_rock.png` |
| `sea.port` | 32x26 | `assets/sea_port.png` |
| `crew.helm` | 8x10 | `assets/crew_helm.png` |
| `crew.sail` | 8x10 | `assets/crew_sail.png` |
| `crew.net` | 8x10 | `assets/crew_net.png` |
| `crew.cook` | 8x10 | `assets/crew_cook.png` |
| `crew.wright` | 8x10 | `assets/crew_wright.png` |
| `crew.watch` | 8x10 | `assets/crew_watch.png` |
| `crew.hold` | 8x10 | `assets/crew_hold.png` |
| `icon.coin` | 11x11 | `assets/icon_coin.png` |
| `icon.fish` | 11x11 | `assets/icon_fish.png` |
| `icon.wood` | 11x11 | `assets/icon_wood.png` |
| `icon.ration` | 11x11 | `assets/icon_ration.png` |
| `icon.morale` | 11x11 | `assets/icon_morale.png` |
| `icon.hull` | 11x11 | `assets/icon_hull.png` |
| `icon.wind` | 11x11 | `assets/icon_wind.png` |
| `icon.crew` | 11x11 | `assets/icon_crew.png` |
| `icon.anchor` | 11x11 | `assets/icon_anchor.png` |
| `icon.sail` | 11x11 | `assets/icon_sail.png` |
| `icon.hold` | 11x11 | `assets/icon_hold.png` |
| `icon.chart` | 11x11 | `assets/icon_chart.png` |
| `ui.dial` | 44x44 | `assets/ui_dial.png` |

## Notas por sprite

* `ship.hull` — casco visto desde arriba, proa **arriba**. Es la referencia de
  toda la cubierta.
* `ship.sails` / `ship.sailsReef` — el aparejo **con el palo dentro**, aparte
  del casco para poder cambiar entre trapo largo y rizos sin repintar el barco.
  Al arrizar se recoge el trapo, no se acorta la verga: en las dos versiones el
  palo y la verga caen en el mismo sitio, o tomar rizos parece cambiar de barco.
* `sea.wave`, `sea.ripple` — trazos de mar. Salen cientos por pantalla: cuanto
  mas simples, mejor.
* `sea.gust` — racha de viento, corre a favor del viento.
* `sea.foam` — un punto de estela.
* `sea.island`, `sea.rock`, `sea.port` — se dibujan **sin girar** desde
  cualquier rumbo, asi que evita formas con una direccion clara.
* `crew.*` — tripulante en cenital, uno por gremio (siete). Muy pequenos:
  silueta y un color, poco mas.
* `icon.*` — iconos del HUD y de los menus.
* `icon.chart` — abre la carta de marear.
* `icon.hold` — bodega; tambien es el icono de la barra de carga del HUD.
* `ui.dial` — el bisel del timon. Las agujas (norte, viento, rumbo pedido) NO
  van en el sprite: las dibuja `src/compass.lua` porque giran.

## Lo que NO es un sprite

La carta de marear (`src/screens/chart.lua`) no usa ninguno: los puertos son
puntos, el barco es un aro con una aguja y la derrota es una linea de puntos,
todo ploteado. Es a proposito — ahi todo apunta a angulos cualesquiera, y la
regla de "nada girado" solo se puede cumplir sin sprites.
