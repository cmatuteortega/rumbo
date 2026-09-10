-- La superficie del mar: un shader.
--
-- El mar viejo eran trazos: doscientos sprites de cresta por fotograma, cada
-- uno pintado en doce orientaciones para no romper la regla 1. Esto es lo
-- contrario -- una sola llamada de dibujo y la mar entera calculada por pixel
-- a partir de un voronoi de espuma (el de Shadertoy: dos capas de celdas, y la
-- espuma en la FRONTERA entre celda y celda, que es exactamente lo que hace el
-- agua al romper) -- y sigue cumpliendo la regla, porque no hay sprite que
-- girar: el shader no muestrea una rejilla de pixeles, la calcula.
--
-- Cuatro cosas hubo que rehacerle al shader original para que fuera ESTE mar:
--
--   * quitarle la perspectiva. El original mira al horizonte desde la cubierta
--     y comprime el agua contra una linea de fuga; aqui la vista es cenital y
--     no hay horizonte, asi que el campo se muestrea en el mundo, plano.
--   * atarlo a la camara. Cada pixel de arte se convierte a una posicion del
--     mundo con el mismo giro que `Sea.project`, asi que virar repeina el mar
--     y andar lo hace desfilar por debajo del barco. Sin eso el mar seria una
--     tela pintada delante de la que el barco resbala.
--   * darle direccion. Las celdas se estiran A TRAVES del viento -- el eje
--     `u` va a lo largo del viento y el `v` cruzado, y `v` mide mas mundo por
--     unidad --, asi que las vetas de espuma salen cruzadas al viento, que es
--     como se peina el mar de verdad. Con viento flojo el estiron baja y las
--     vetas se vuelven rizos redondos.
--   * cerrarle la paleta. El original mezcla azul y blanco a discrecion; aqui
--     la cuenta acaba en un escalon de cinco colores de `src/palette.lua` y ni
--     un RGB intermedio, que es lo que lo deja pixel art y no un degradado.
--
-- Y dos cosas que no se ven pero sin las que no funciona:
--
-- **El campo es PERIODICO.** Los hashes muerden la celda en modulo `WRAP`, y
-- el origen se envuelve en ese mismo modulo. Sin eso, a las pocas horas de
-- singladura las coordenadas del mundo son tan grandes que `fract()` se queda
-- sin decimales y el mar hierve; con eso, la vuelta del campo no se ve porque
-- cae a cinco mil pixeles de mundo, que son veinte pantallas largas.
--
-- **Ningun numero del campo puede ser grande.** Esta es la diferencia entre
-- verse en un PC y no verse en un telefono, y costo un rato entenderla. Un
-- `float` de escritorio tiene veinticuatro bits de mantisa y le da igual todo;
-- la precision de un fragmento de movil puede ser de dieciseis bits, o de once,
-- y con once `fract()` de un numero de dos cifras ya no distingue casi nada. El
-- sintoma era el mar entero en azul liso, sin una veta de espuma, con la estela
-- encima tan visible como siempre -- porque la estela son distancias en
-- pantalla, numeros de dos cifras y sin `fract` de por medio.
--
-- La salida no es pedir mas precision (que se pide igual, por si acaso: ver
-- HIGHP), es no necesitarla. Tres cosas:
--
--   * el grano ya no se calcula, se LEE de una textura. El hash aritmetico del
--     shader original se lleva sus numeros al cincuenta largo, y ahi es donde
--     se moria; un texel vale lo que vale en cualquier maquina. Medido con la
--     cuenta a once bits: 99,7 % de la pantalla en azul y cero espuma con el
--     hash calculado, y el mar de PC clavado leyendolo.
--   * del origen solo viaja el DECIMAL (`uOrigin`); las celdas enteras van como
--     desplazamiento dentro de la textura (`uSeed`), donde no cuestan
--     precision. Asi la coordenada que se parte con `floor`/`fract` no pasa de
--     las cuarenta celdas que caben en pantalla.
--   * las fases del oleaje llegan ya envueltas en una vuelta (`uWave`, `uPhi`)
--     en vez de multiplicarse dentro: un `sin()` de setecientos radianes es
--     ruido en cuanto la maquina no es un PC.
--
-- **La estela va DENTRO del agua, no encima.** El barco no se limita a pasar:
-- abre una calle. Lua le manda la derrota -- los ultimos puntos por donde ha
-- pasado el espejo de popa, ya convertidos a pixeles de pantalla -- y el shader
-- mide la distancia de cada pixel a esa polilinea. De ahi salen tres cosas: el
-- SURCO (dentro de la calle el campo de espuma se aplasta, asi que las crestas
-- mueren y queda agua lisa que tarda en cerrarse), el HERVOR de popa y los
-- BRAZOS de la V. Pintar la V encima con puntitos era mentira: la espuma se
-- sumaba al oleaje en vez de romperlo, y se veia pegada.
--
-- La V nace en la RODA y se abre con lo que el barco ha andado desde cada
-- trozo de derrota (no con el reloj), asi que en una virada se dobla sola. Por
-- delante del espejo la calle se cierra en punta siguiendo el casco, y por
-- detras mide la manga ENTERA del sprite: es lo que hace que el surco se lea
-- como el hueco que deja el barco y no como una raya.
--
-- **El origen se ARRASTRA, no se calcula.** Seria mas limpio sacarlo de
-- `state.x`/`state.y`, pero el eje del campo gira con el viento y proyectar
-- una posicion enorme sobre un eje que rola hace que el mar salga disparado de
-- lado al menor cambio de viento. Asi que lo que se guarda entre fotogramas es
-- el propio origen, y lo que se le suma es lo que el barco ha andado y lo que
-- el agua ha desfilado. No se guarda en la partida -- `Surface.reset` lo pone
-- a cero y el mar sale igual de creible desde cualquier sitio.

local Constants = require('src.constants')
local Palette   = require('src.palette')
local Util      = require('src.util')

local Surface = {}

-- Pixeles de mundo por celda de espuma A LO LARGO del viento. A traves mide
-- CELL * estiron, que es de donde salen las vetas.
Surface.CELL = 10
Surface.STRETCH = { 1.6, 1.9 }   -- en calma, y lo que sube con viento fresco

-- El campo se repite cada tantas celdas, y el origen se envuelve ahi. Es
-- tambien el lado de la textura de grano, porque son la misma cosa: cada celda
-- muerde un texel y la textura se repite sola. Son 2560 pixeles de mundo a lo
-- largo del viento -- diez pantallas -- y cuatro veces mas cruzado, que es
-- donde las celdas van estiradas.
Surface.WRAP = 256

-- El tiempo llega al shader envuelto en este periodo. Todos los ritmos de
-- dentro son multiplos enteros de 2*pi/PERIOD, asi que la vuelta no da tiron.
Surface.PERIOD = 240

-- Lo que desfila el agua a sotavento, en pixeles de mundo por segundo. Es el
-- mismo numero que tenia el mar de trazos: por debajo el mar se ve muerto, y
-- por encima parece un rio.
local DRIFT = { 4, 22 }

-- Cuantos puntos de derrota caben en el shader. Van como array de uniformes
-- porque es lo mas simple y lo mas rapido; si algun dia aparece un movil que
-- no tenga vectores de sobra en fragmento, la salida es mandarla como textura
-- de TRACK x 1 y cambiar el indice por un texture2D -- el resto del shader no
-- se entera. La derrota se REMUESTREA a estos puntos (src/sea.lua), asi que
-- subirlo alarga la estela y no la afina: la distancia a un segmento es exacta
-- por muy separados que esten sus extremos.
Surface.TRACK = 24

-- La V. La tangente del semiangulo es la de siempre, y el tope dice cuanto se
-- abren los brazos POR FUERA de la manga: la V no nace en la crujia, nace en
-- el costado, que es donde el casco aparta el agua.
Surface.SPREAD = 0.32
Surface.ARM    = 26

-- Las mismas frecuencias de comba que el shader, para poder adelantarle aqui
-- la fase que le toca a la celda entera. Si se tocan alli, se tocan aqui.
-- Enteros: es lo que hace que la comba quepa un numero exacto de veces en el
-- periodo del campo. Con 61 la frecuencia es la misma que tenia con el campo
-- del doble de largo; 33 sube un uno y medio por ciento la otra, y eso no lo
-- ve nadie.
local K1 = 61 * Util.TAU / Surface.WRAP
local K2 = 33 * Util.TAU / Surface.WRAP

--==========================================================================
-- El shader
--==========================================================================

-- La cabecera de precision va aparte porque se prueban DOS. GLSL ES define
-- `GL_FRAGMENT_PRECISION_HIGH` cuando el fragmento tiene highp, pero hay
-- controladores que no lo definen y lo tienen igual, y el precio de creerles es
-- quedarse en mediump, que aqui es quedarse sin mar. Asi que primero se pide
-- highp a secas; si esa no compila -- un movil de verdad sin highp -- se cae a
-- la version con guarda, que compila siempre. En escritorio no existen los
-- calificadores de precision y las dos se quedan en nada.
local HIGHP = [[
#ifdef GL_ES
precision highp float;
#endif
]]

local GUARDED = [[
#if defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)
precision highp float;
#endif
]]

local BODY = [[
#define TAU 6.2831853
#define WRAP 256.0
#define OCT 3.0
#define TRACK 24

// Frecuencias de la comba. NO son redondas a proposito: tienen que caber un
// numero entero de veces en WRAP, o al envolver el origen la pantalla entera
// pegaria un salto de fase.
#define K1 (61.0 * TAU / WRAP)
#define K2 (33.0 * TAU / WRAP)

extern vec2 uSize;      // el lienzo, en pixeles de arte
extern vec2 uAnchor;    // donde esta el barco, en pixeles de arte
// El campo bajo el barco. Del origen, aqui solo llega el DECIMAL: las celdas
// enteras viajan como desplazamiento dentro de la textura de grano (uSeed), que
// es donde no cuestan precision ninguna.
extern vec2 uOrigin;

// El grano: una textura de ruido de WRAP x WRAP con cuatro numeros por celda
// (dos para el meneo de la semilla, uno para el corte y uno para las manchas de
// mar liso). El desplazamiento del campo entra como coordenada de textura --
// uSeed para la capa gruesa y uSeedOct para la fina --, y la repeticion de la
// textura hace el modulo sola.
extern Image uNoise;
extern vec2 uSeed;
extern vec2 uSeedOct;
// Fases ya envueltas: uPhi es la que le toca en la comba al trozo de mundo en
// el que estamos, y uWave las cuatro del oleaje (comba larga, comba corta,
// celdas, octava fina). Se calculan en Lua con dobles y llegan en una vuelta.
extern vec2 uPhi;
extern vec4 uWave;
extern vec2 uBasisX;    // lo que corre el campo por pixel a estribor
extern vec2 uBasisY;    // ... y por pixel hacia abajo de la pantalla
extern float uWarp;     // cuanto ondulan las lineas de cresta
extern float uGain;     // cuanta espuma deja el viento que sopla
extern float uDark;     // a partir de que sombra sale el agua honda
extern vec3 uCut;       // escalones: bajio, espuma, blanco
extern vec3 uDeep, uWater, uShallow, uFoam, uWhite;

// La derrota: por donde ha pasado el espejo de popa, en pixeles de arte y de
// lo mas reciente a lo mas viejo. Los dos primeros puntos son el barco -- roda
// y espejo --, que es lo que cierra la calle en V por delante.
//   xy = donde,  z = lo que el barco ha andado desde ahi,  w = lo que le queda
extern vec4 uTrack[TRACK];
extern float uBeam;     // media manga del casco, en pixeles de arte
extern float uHull;     // eslora: de espejo a roda
extern float uSpread;   // tangente del semiangulo de la V
extern float uArm;      // cuanto se abren los brazos por fuera de la manga
// Dos compuertas y no una. Por DELANTE del espejo manda uBow, que es la regla
// de siempre: por debajo de un tercio de andar la roda no rompe agua y no hay
// bigote. Por DETRAS manda uWash, que se llena mucho antes: un barco deja
// rastro a cualquier velocidad a la que se mueva de verdad, y con la regla de
// la roda puesta tambien aqui la estela desaparecia justo cuando mas falta
// hace -- virando, o con viento flojo, que es cuando el barco va despacio.
extern float uBow;
extern float uWash;
extern float uBreak;    // escalon del blanco de la ESTELA, aparte del del mar

// El grano sale de una TEXTURA y no de una cuenta, y esa es la diferencia
// entre verse en un PC y no verse en un telefono.
//
// El hash del shader original (el de Dave Hoskins, `fract(p * .1031)` y un
// producto escalar con 33.33 encima) es exacto de sobra en escritorio y no
// sobrevive en movil: sus numeros intermedios andan por el cincuenta, y a once
// bits de mantisa `fract()` de un cincuenta y pico deja media docena de valores
// distintos. Medido: con el hash calculado a lo bruto, un fragmento corto deja
// el 99,7 % de la pantalla en azul liso -- ni una veta de espuma --, mientras la
// estela, que son numeros de dos cifras, se sigue viendo perfecta. Era
// exactamente lo que se veia en el telefono.
//
// Un texel no tiene ese problema: vale lo que vale, lo lea quien lo lea. Y de
// paso son treinta lecturas de una textura de 256x256 -- que cabe entera en la
// cache -- donde antes habia casi sesenta hashes por pixel.
//
// El medio texel es para caer siempre en el centro: con el desplazamiento
// sumado, el redondeo mas torpe se queda a un octavo de texel del borde.
vec4 grain(vec2 i, vec2 seed) {
    return Texel(uNoise, (i + 0.5) * (1.0 / WRAP) + seed);
}

// Distancia entre la celda mas cercana y la segunda. Vale casi cero justo en
// la frontera entre dos celdas -- que es donde va la espuma -- y crece hacia
// dentro. Una de cada tres semillas se cae, y eso es lo que rompe la reticula
// en trozos sueltos en vez de una malla cerrada.
//
// `q` es la posicion DENTRO de la pantalla y nunca pasa de unas decenas: el
// trozo de mundo en el que estamos va en `seed`, en coordenada de textura. Es
// la misma idea que el grano -- que lo gordo no toque nunca a lo fino.
//
// El corte era `pow(hash, .6) < 0.5` en el shader original. Es exactamente lo
// mismo que comparar el numero contra 0.5^(1/0.6), y asi se ahorran veintisiete
// pow por pixel y capa -- y sobre todo se evita pow(0, y), que hay
// controladores que devuelven NaN y con NaN aqui se va la pantalla entera.
float cells(vec2 q, vec2 seed, float phase) {
    vec2 i = floor(q), f = fract(q);
    float m1 = 9.0, m2 = 9.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 n = vec2(float(x), float(y));
            vec4 g = grain(i + n, seed);
            if (g.b < 0.31498) continue;
            vec2 p = 0.5 + .3 * sin(TAU * g.rg + phase);
            float d = length(n + p - f);
            if (d < m1) { m2 = m1; m1 = d; }
            else if (d < m2) m2 = d;
        }
    }
    return m2 - m1;
}

// Ruido de valor: las manchas de mar picado y de mar liso. Sin el, la espuma
// sale repartida por igual y el mar se lee como un papel pintado.
float vnoise(vec2 q, vec2 seed) {
    vec2 i = floor(q), f = fract(q);
    f = f * f * (3.0 - 2.0 * f);
    // El cuarto canal, que es el unico que no usa el voronoi: asi las manchas
    // de mar liso no salen calcadas al corte de las semillas.
    float a = grain(i,                  seed).a;
    float b = grain(i + vec2(1.0, 0.0), seed).a;
    float c = grain(i + vec2(0.0, 1.0), seed).a;
    float d = grain(i + vec2(1.0, 1.0), seed).a;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Lo mas cerca que pasa la derrota de este pixel: distancia, lo que el barco ha
// andado desde el trozo mas cercano, y lo que le queda a esa espuma.
//
// Se mide contra los SEGMENTOS y no contra los puntos: con puntos sueltos la
// estela sale a lunares en cuanto el barco corre, que es exactamente el fallo
// que tenia dibujada con sprites. El relleno de la cola son puntos repetidos,
// asi que los segmentos que sobran miden cero y nunca ganan.
vec3 wakeAt(vec2 p) {
    float best = 1e9, run = 0.0, left = 0.0;
    for (int i = 0; i < TRACK - 1; i++) {
        vec4 a = uTrack[i];
        vec4 b = uTrack[i + 1];
        vec2 ab = b.xy - a.xy;
        float len2 = dot(ab, ab);
        float t = (len2 > 0.0001) ? clamp(dot(p - a.xy, ab) / len2, 0.0, 1.0) : 0.0;
        float d = length(p - (a.xy + ab * t));
        if (d < best) {
            best = d;
            run  = mix(a.z, b.z, t);
            left = mix(a.w, b.w, t);
        }
    }
    return vec3(best, run, left);
}

// Media manga de la calle a lo largo de la derrota. En el espejo `run` vale
// cero y la roda queda en -uHull, asi que por delante la calle se cierra en
// punta siguiendo el casco -- la V de proa -- y a poco menos de media eslora
// ya mide la manga entera, que es lo que deja por detras.
float beamAt(float run) {
    return uBeam * clamp((run + uHull) / (uHull * 0.45), 0.0, 1.0);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    // Al centro del pixel de arte, siempre: el mar se calcula en la rejilla,
    // no entre medias.
    vec2 pix = floor(tc * uSize) + 0.5;
    vec2 px  = pix - uAnchor;
    // Y el campo se mide desde el barco, no desde el origen del mundo: asi lo
    // que se corta en decimales es la pantalla y no la singladura.
    vec2 q = uOrigin + px.x * uBasisX + px.y * uBasisY;

    // La comba. Una linea de cresta recta de punta a punta es un peine; con
    // esto respira y se dobla como el agua. La fase que le corresponde al
    // trozo de mundo en el que estamos viene ya sumada en uPhi, que es lo que
    // deja estos dos senos por debajo de una veintena de radianes.
    q.x += sin(q.y * K1 + uPhi.y + uWave.x) * uWarp;
    q.y += sin(q.x * K2 + uPhi.x - uWave.y) * 0.10;

    float d1 = cells(q,       uSeed,    uWave.z);
    float d2 = cells(q * OCT, uSeedOct, uWave.w);
    // La sombra va MEDIA celda a barlovento de la cresta: es el dorso de la
    // ola, y es lo que le da bulto en vez de dejarla plana.
    float d3 = cells(q + vec2(0.45, 0.0), uSeed, uWave.z);

    float vein = 1.0 - smoothstep(0.0, 0.50, d1);
    float fine = 1.0 - smoothstep(0.0, 0.25, d2 * d2);
    float dark = 1.0 - smoothstep(0.0, 0.30, d3);

    // La mancha manda sobre la veta: donde el mar esta liso no hay espuma por
    // mucho que pase una frontera de celda por encima.
    float lift = pow(0.10 + 0.90 * vnoise(q, uSeed), 1.6) * uGain;

    // Y aqui pasa el barco.
    vec3 wk = wakeAt(pix);
    // `manga` y no `half`: half es palabra reservada en GLSL ES y no compila.
    float manga = beamAt(wk.y);
    float lane = (1.0 - smoothstep(manga - 2.0, manga + 3.0, wk.x)) * wk.z;

    // La compuerta cambia en el espejo de popa, y cambia SUAVE: un escalon
    // justo ahi se ve como una raya de brillo cruzando la estela.
    float gate = mix(uBow, uWash, smoothstep(-8.0, 8.0, wk.y));

    // EL SURCO. Dentro de la calle el oleaje se aplasta: no es que se pinte
    // espuma encima, es que el mar deja de haber. Se nota aunque el barco no
    // ande, porque el casco sigue metido en el agua.
    lift *= 1.0 - 0.85 * lane * (0.40 + 0.60 * gate);

    float foam = vein * (0.5 + 0.5 * fine) * lift;

    // Y la espuma que levanta el barco va aparte de la del oleaje. Aparte de
    // verdad: tiene su propio escalon de blanco, porque el mar rompe solo si
    // el viento da para ello y una estela es blanca haga el tiempo que haga.
    // Sumandola a la del mar, con viento flojo la estela salia de color de
    // bajio y no se veia.

    // EL HERVOR de popa: lo mas macizo de todo el mar, y dura poco -- media
    // eslora y se ha deshecho. Va elevado a una y media para que se concentre
    // en la crujia en vez de salir del ancho entero del espejo, y picado por la
    // octava fina: un rectangulo blanco detras del barco se lee como un babero.
    // El sqrt en vez de pow(x, 1.5): pow con la base en cero da NaN en algunos
    // controladores, y aqui la base es cero en casi toda la pantalla.
    // El hervor cuelga de uBow y no de uWash: que la estela no desaparezca por
    // ir despacio no quiere decir que un barco al ralenti hierva por la popa
    // como uno lanzado. Lo que no puede faltar es el RASTRO; la violencia si
    // depende de lo que se corra.
    float wash = 0.95 * lane * sqrt(lane) * uBow
                      * (1.0 - smoothstep(0.0, 15.0, wk.y)) * (0.45 + 0.55 * fine);

    // LOS BRAZOS. Nacen en la roda -- ahi beamAt vale cero y la V cierra en
    // punta -- y se abren con lo que el barco ha ANDADO desde cada trozo de
    // derrota, no con el reloj: por eso en una virada la V se dobla sola.
    // Van multiplicados por la veta del propio mar para que salgan rotos a
    // trozos; una linea limpia a este grano se lee como pintada encima.
    float arm = manga + min(max(wk.y, 0.0) * uSpread, uArm);
    wash += 1.00 * (1.0 - smoothstep(0.0, 3.5, abs(wk.x - arm)))
                 * wk.z * gate * (0.60 + 0.40 * vein);

    // Cinco escalones y ni un color entre medias. Los dos primeros no
    // distinguen de donde viene la espuma; el blanco si: el del mar tiene el
    // techo que le pone el viento (con uCut.z por encima de uno -- que es lo
    // que manda src/surface.lua en calma -- el agua no puede romper por mucho
    // que se mire), y el de la estela tiene el suyo, que no depende del tiempo
    // que haga.
    float any = max(foam, wash);
    vec3 c = uWater;
    c = mix(c, uDeep,    step(uDark,  dark * lift));
    c = mix(c, uShallow, step(uCut.x, any));
    c = mix(c, uFoam,    step(uCut.y, any));
    c = mix(c, uWhite,   step(uCut.z, foam));
    c = mix(c, uWhite,   step(uBreak, wash));
    return vec4(c, 1.0);
}
]]

--==========================================================================
-- El arrastre
--==========================================================================

local ou, ov = 0, 0
local lastX, lastY

function Surface.reset()
    ou, ov = 0, 0
    lastX, lastY = nil, nil
end

-- Direccion HACIA la que sopla, en el mundo, y su perpendicular. El campo se
-- mide en estos dos ejes: `u` a lo largo del viento, `v` cruzado.
local function axes(state)
    local wx, wy = Util.headingToVector(Util.wrapAngle(state.wind.from + math.pi))
    return wx, wy, -wy, wx
end

function Surface.update(state, dt, sea)
    local wx, wy, nx, ny = axes(state)
    local cw = Surface.CELL
    local cn = cw * (Surface.STRETCH[1] + Surface.STRETCH[2] * sea)

    -- Lo que el barco ha andado. Si ha dado un salto -- una vuelta a la
    -- partida mueve horas de golpe -- no se arrastra nada: el campo es ruido y
    -- de donde arranque no lo sabe nadie.
    if lastX then
        local mx, my = state.x - lastX, state.y - lastY
        if mx * mx + my * my < 200 * 200 then
            ou = ou + (mx * wx + my * wy) / cw
            ov = ov + (mx * nx + my * ny) / cn
        end
    end
    lastX, lastY = state.x, state.y

    -- Y lo que ha desfilado el agua, a sotavento.
    ou = ou - (DRIFT[1] + DRIFT[2] * sea) * dt / cw

    ou = ou % Surface.WRAP
    ov = ov % Surface.WRAP
end

--==========================================================================
-- Los uniformes
--==========================================================================

-- La derrota, estirada a los TRACK puntos que espera el shader. Lo que sobra se
-- rellena repitiendo el ultimo punto: asi los segmentos de mas miden cero y
-- nunca ganan la distancia, que es mas barato que preguntar en cada pixel
-- cuantos puntos hay de verdad (y ademas GLSL ES no deja recorrer un bucle
-- hasta un uniforme).
local FAR = { -4000, -4000, 0, 0 }

local function pad(track)
    local out, last = {}, FAR
    for i = 1, Surface.TRACK do
        local p = track and track[i]
        if p then
            last = { p.x, p.y, p.run, p.left }
        end
        out[i] = last
    end
    return out
end

-- Todo lo que el shader necesita saber, en Lua y sin tocar love: aqui vive el
-- balance del mar (cuanta espuma da cada viento, cuanto se estiran las vetas)
-- y aqui se puede medir sin ventana. El shader solo evalua.
--
-- `wake` es lo que trae src/sea.lua de la estela: la derrota ya proyectada a
-- pixeles de arte, la manga y la eslora del casco con las que se dibuja, y lo
-- que anda el barco. Puede faltar -- entonces el mar sale sin barco.
function Surface.frame(state, sea, wake)
    local stretch = Surface.STRETCH[1] + Surface.STRETCH[2] * sea
    local cw = Surface.CELL
    local cn = cw * stretch

    local wx, wy, nx, ny = axes(state)
    -- Los dos ejes de la pantalla, en el mundo. Son los mismos que invierte
    -- Sea.project: un pixel a estribor y un pixel hacia abajo.
    local sinH, cosH = math.sin(state.heading), math.cos(state.heading)
    local ex, ey =  cosH,  sinH
    local fx, fy = -sinH,  cosH

    local cx, cy = Constants.shipAnchor()

    -- Las celdas enteras del origen y su decimal. `ou`/`ov` ya vienen
    -- envueltos en WRAP, asi que `iu`/`iv` caben de sobra en un float corto.
    local iu, iv = math.floor(ou), math.floor(ov)

    -- Las fases del oleaje, envueltas en una vuelta. Los ritmos son multiplos
    -- enteros de 2*pi/PERIOD, asi que envolver aqui no da tiron: es el mismo
    -- angulo, solo que con la parte que no dice nada quitada antes de mandarlo.
    local t = state.time % Surface.PERIOD
    local function rock(n)
        return (t * n * Util.TAU / Surface.PERIOD) % Util.TAU
    end

    -- El blanco solo aparece con viento hecho, y no de golpe: por debajo de
    -- 0,35 el escalon queda por encima de uno, que es mas de lo que la cuenta
    -- de espuma puede dar, asi que en calma no hay un pixel blanco. No es que
    -- salgan pocos: es que no puede salir ninguno.
    local white = 1.01 - 0.22 * Util.clamp((sea - 0.35) / 0.65, 0, 1)

    return {
        size    = { Constants.ART_W, Constants.ART_H },
        track   = pad(wake and wake.track),
        beam    = (wake and wake.beam) or 0,
        hull    = (wake and wake.hull) or 1,
        spread  = Surface.SPREAD,
        arm     = Surface.ARM,
        bow     = (wake and wake.bow) or 0,
        wash    = (wake and wake.wash) or 0,
        -- El escalon del blanco de la ESTELA. Va aparte del del mar (uCut.z)
        -- y no se mueve con el viento: una estela es blanca en calma igual que
        -- con racha, y atarla al techo del oleaje la dejaba de color de bajio
        -- justo los dias de poco viento.
        brk     = 0.62,
        anchor  = { cx, cy },
        -- El origen, partido: el decimal va al shader como coordenada del
        -- campo y las celdas enteras como desplazamiento DENTRO de la textura
        -- de grano. Mandar el total, que es lo natural, es lo que se veia en
        -- PC y no en el movil.
        origin  = { ou - iu, ov - iv },
        seed    = { iu / Surface.WRAP, iv / Surface.WRAP },
        -- La octava fina muerde la misma textura tres veces mas apretado, asi
        -- que su desplazamiento es el triple. Los dos numeros sueltos la apartan
        -- del campo gordo: sin ellos, al pasar el origen por cero las dos capas
        -- caerian en el mismo sitio de la textura y la fina saldria calcada a la
        -- gruesa. Son multiplos exactos de un texel, asi que no descuadran nada.
        seedOct = { ((iu * 3 + 96)  % Surface.WRAP) / Surface.WRAP,
                    ((iv * 3 + 181) % Surface.WRAP) / Surface.WRAP },
        -- La fase que le toca a ESE trozo de mundo en la comba. Va aparte
        -- porque `sin(celda * K)` con la celda en las centenas son cientos de
        -- radianes, y de ahi para abajo no hay maquina que acierte.
        phi     = { (iu * K2) % Util.TAU, (iv * K1) % Util.TAU },
        wave    = { rock(13), rock(5), rock(9), rock(27) },
        basisX  = { (ex * wx + ey * wy) / cw, (ex * nx + ey * ny) / cn },
        basisY  = { (fx * wx + fy * wy) / cw, (fx * nx + fy * ny) / cn },
        warp    = 0.30 * (0.35 + 0.65 * sea),
        -- Estos cuatro numeros NO se han tocado al cambiar el grano de cuenta
        -- a textura, y no por pereza: se volvieron a ajustar midiendo, y el
        -- ajuste que mas se parecia al mar de antes era dejarlos donde
        -- estaban. Con el grano bien repartido, el reparto de los cinco
        -- colores sale solo -- cuatro por ciento de agua honda, diecisiete de
        -- bajio, dos y medio de espuma y uno de rompiente con viento hecho --,
        -- que es lo que dice que el cambio fue de fontaneria y no de aspecto.
        gain    = 0.30 + 0.70 * sea,
        dark    = 0.45,
        cut     = { 0.24, 0.60, white },
    }
end

--==========================================================================
-- Dibujo
--==========================================================================

local shader, canvas, quad, noise, tried

-- El mar se pinta en un lienzo a escala de ARTE y se sube entero de un tiron.
-- No es un ahorro cualquiera: una pantalla de movil son veinticinco veces mas
-- pixeles que el area de arte, y ademas asi cada invocacion del shader ES un
-- pixel del juego, con lo que la rejilla sale cuadrada sola.
-- Los cuatro canales del grano tienen que ser cuatro numeros distintos de la
-- misma celda, y ademas no parecerse a los de la celda de al lado. Eso es justo
-- lo que `Util.hash01` no sabe hacer -- su tercer argumento se anula y es casi
-- afin --, y por eso existe `Util.hashGrid`, que lo explica entero.
--
-- Se nota enseguida cuando se usa el que no es: con los cuatro canales iguales,
-- los dos numeros del meneo de la semilla salen el mismo, las celdas se mueven
-- todas en diagonal y el mar se convierte en una escalera.

-- El grano del mar: cuatro numeros por celda -- los dos del meneo de la
-- semilla, el del corte que tira una de cada tres y el de las manchas de mar
-- liso -- metidos en los cuatro canales de una textura de WRAP x WRAP.
--
-- Se calcula y no se guarda como PNG, como todo lo variado de este juego: es la
-- misma textura en cada arranque y en cada maquina, asi que el mar de una
-- captura de pantalla es el mar de cualquier otra.
--
-- Se repite (`setWrap`) y se lee al vecino mas cercano: la repeticion es la que
-- hace el modulo del campo sin que nadie tenga que calcularlo, y el vecino mas
-- cercano es obligatorio -- interpolar el grano seria promediar semillas de
-- celdas distintas y el voronoi se deshace.
-- Se saca aparte de la imagen porque es lo unico del mar que no viaja como
-- uniforme: la prueba sin ventana lo pide asi para poder mirarlo.
function Surface.testGrain()
    local n = Surface.WRAP
    local data = love.image.newImageData(n, n)
    data:mapPixel(function(x, y)
        return Util.hashGrid(x, y, 1), Util.hashGrid(x, y, 2),
               Util.hashGrid(x, y, 3), Util.hashGrid(x, y, 4)
    end)
    return data
end

local function grain()
    local img = love.graphics.newImage(Surface.testGrain())
    img:setFilter('nearest', 'nearest')
    img:setWrap('repeat', 'repeat')
    return img
end

local function ensure()
    if not tried then
        tried = true
        -- Highp a secas primero y con guarda despues. El orden importa: hay
        -- moviles que tienen highp en el fragmento y no definen la macro que
        -- lo anuncia, y creerles cuesta el mar entero. Si la primera no
        -- compila es que el aparato de verdad no lo tiene, y entonces la
        -- segunda si -- con menos mar, pero con mar.
        local made, why, grado
        for _, intento in ipairs({ { "highp", HIGHP }, { "con guarda", GUARDED } }) do
            local ok, res = pcall(love.graphics.newShader, intento[2] .. BODY)
            if ok and res then made, grado = res, intento[1] break end
            why = res
        end
        if made then
            shader = made
            -- Una linea en consola, que es la unica forma de saber desde fuera
            -- si el mar lo esta pintando el shader o el azul de respaldo, y
            -- con que precision -- que es lo que separa el mar de PC del que
            -- se veia en el movil.
            print(string.format("Rumbo | mar por shader: ok, %s (%dx%d, derrota de %d puntos)",
                                grado, Constants.ART_W, Constants.ART_H, Surface.TRACK))
            -- El shader necesita algo sobre lo que correr, y un pixel blanco
            -- estirado a toda la pantalla es lo mas barato que hay: de la
            -- imagen no se lee nada, solo se aprovechan sus coordenadas.
            local data = love.image.newImageData(1, 1)
            data:setPixel(0, 0, 1, 1, 1, 1)
            quad = love.graphics.newImage(data)
            noise = grain()
        else
            print("Rumbo | el mar por shader no compila: " .. tostring(why))
        end
    end
    if not shader then return false end
    if not canvas or canvas:getWidth() ~= Constants.ART_W
                  or canvas:getHeight() ~= Constants.ART_H then
        if canvas then canvas:release() end
        canvas = love.graphics.newCanvas(Constants.ART_W, Constants.ART_H)
        canvas:setFilter('nearest', 'nearest')
    end
    return canvas ~= nil
end

function Surface.draw(state, sea, wake)
    if not ensure() then
        -- Sin shader no hay mar, pero tampoco un agujero: queda el azul de
        -- fondo, y encima siguen las islas, los puertos y las salpicaduras.
        -- La estela se pierde, porque vive dentro del agua.
        love.graphics.setColor(Palette.sea)
        love.graphics.rectangle("fill", 0, 0, Constants.ART_W, Constants.ART_H)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    local f = Surface.frame(state, sea, wake)
    shader:send("uSize",   f.size)
    shader:send("uAnchor", f.anchor)
    shader:send("uOrigin", f.origin)
    shader:send("uNoise",  noise)
    shader:send("uSeed",   f.seed)
    shader:send("uSeedOct", f.seedOct)
    shader:send("uPhi",    f.phi)
    shader:send("uWave",   f.wave)
    shader:send("uBasisX", f.basisX)
    shader:send("uBasisY", f.basisY)
    shader:send("uWarp",   f.warp)
    shader:send("uGain",   f.gain)
    shader:send("uDark",   f.dark)
    shader:send("uCut",    f.cut)
    shader:send("uTrack",  unpack(f.track))
    shader:send("uBeam",   f.beam)
    shader:send("uHull",   f.hull)
    shader:send("uSpread", f.spread)
    shader:send("uArm",    f.arm)
    shader:send("uBow",    f.bow)
    shader:send("uWash",   f.wash)
    shader:send("uBreak",  f.brk)
    shader:send("uDeep",     { Palette.deep[1],    Palette.deep[2],    Palette.deep[3] })
    shader:send("uWater",    { Palette.sea[1],     Palette.sea[2],     Palette.sea[3] })
    shader:send("uShallow",  { Palette.shallow[1], Palette.shallow[2], Palette.shallow[3] })
    shader:send("uFoam",     { Palette.foam[1],    Palette.foam[2],    Palette.foam[3] })
    shader:send("uWhite",    { Palette.white[1],   Palette.white[2],   Palette.white[3] })

    local prev = love.graphics.getCanvas()
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setCanvas(canvas)
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
    -- Angulo cero, como todo en este juego.
    love.graphics.draw(quad, 0, 0, 0, Constants.ART_W, Constants.ART_H)
    love.graphics.setShader()
    love.graphics.setCanvas(prev)
    love.graphics.pop()

    love.graphics.draw(canvas, 0, 0)
end

return Surface
