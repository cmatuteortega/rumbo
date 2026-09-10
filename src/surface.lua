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
-- sin decimales y el mar hierve; con eso, los numeros no pasan nunca de
-- quinientos y pico y la vuelta del campo no se ve porque cae a cinco mil
-- pixeles de mundo, que son veinte pantallas largas.
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

-- El campo se repite cada tantas celdas, y el origen se envuelve ahi. Son
-- 5120 pixeles de mundo a lo largo del viento: veinte pantallas largas.
Surface.WRAP = 512

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

--==========================================================================
-- El shader
--==========================================================================

local SOURCE = [[
#define TAU 6.2831853
#define WRAP 512.0
#define OCT 3.0
#define RATE (TAU / 240.0)
#define TRACK 24

// Frecuencias de la comba. NO son redondas a proposito: tienen que caber un
// numero entero de veces en WRAP, o al envolver el origen la pantalla entera
// pegaria un salto de fase.
#define K1 (122.0 * TAU / WRAP)
#define K2 (65.0  * TAU / WRAP)

extern vec2 uSize;      // el lienzo, en pixeles de arte
extern vec2 uAnchor;    // donde esta el barco, en pixeles de arte
extern vec2 uOrigin;    // el campo bajo el barco
extern vec2 uBasisX;    // lo que corre el campo por pixel a estribor
extern vec2 uBasisY;    // ... y por pixel hacia abajo de la pantalla
extern float uTime;
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
extern float uWork;     // lo que anda el barco; parado no levanta agua

// Los hashes del shader original, con la celda mordida en modulo: es lo que
// hace el campo periodico y lo que mantiene los numeros pequenos.
float hash12(vec2 p, float per) {
    p = mod(p, per);
    vec3 p3 = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p, float per) {
    p = mod(p, per);
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Distancia entre la celda mas cercana y la segunda. Vale casi cero justo en
// la frontera entre dos celdas -- que es donde va la espuma -- y crece hacia
// dentro. Una de cada tres semillas se cae (el pow contra 0.5), y eso es lo
// que rompe la reticula en trozos sueltos en vez de una malla cerrada.
float cells(vec2 st, float phase, float per) {
    vec2 i = floor(st), f = fract(st);
    float m1 = 9.0, m2 = 9.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 n = vec2(float(x), float(y));
            vec2 c = i + n;
            if (pow(hash12(c, per), .6) < 0.5) continue;
            vec2 p = 0.5 + .3 * sin(TAU * hash22(c, per) + phase);
            float d = length(n + p - f);
            if (d < m1) { m2 = m1; m1 = d; }
            else if (d < m2) m2 = d;
        }
    }
    return m2 - m1;
}

// Ruido de valor: las manchas de mar picado y de mar liso. Sin el, la espuma
// sale repartida por igual y el mar se lee como un papel pintado.
float vnoise(vec2 p, float per) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i, per);
    float b = hash12(i + vec2(1.0, 0.0), per);
    float c = hash12(i + vec2(0.0, 1.0), per);
    float d = hash12(i + vec2(1.0, 1.0), per);
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
    vec2 st = uOrigin + px.x * uBasisX + px.y * uBasisY;

    // La comba. Una linea de cresta recta de punta a punta es un peine; con
    // esto respira y se dobla como el agua.
    st.x += sin(st.y * K1 + uTime * RATE * 13.0) * uWarp;
    st.y += sin(st.x * K2 - uTime * RATE *  5.0) * 0.10;

    float d1 = cells(st,       uTime * RATE *  9.0, WRAP);
    float d2 = cells(st * OCT, uTime * RATE * 27.0, WRAP * OCT);
    // La sombra va MEDIA celda a barlovento de la cresta: es el dorso de la
    // ola, y es lo que le da bulto en vez de dejarla plana.
    float d3 = cells(st + vec2(0.45, 0.0), uTime * RATE * 9.0, WRAP);

    float vein = 1.0 - smoothstep(0.0, 0.50, d1);
    float fine = 1.0 - smoothstep(0.0, 0.25, d2 * d2);
    float dark = 1.0 - smoothstep(0.0, 0.30, d3);

    // La mancha manda sobre la veta: donde el mar esta liso no hay espuma por
    // mucho que pase una frontera de celda por encima.
    float lift = pow(0.10 + 0.90 * vnoise(st, WRAP), 1.6) * uGain;

    // Y aqui pasa el barco.
    vec3 wk = wakeAt(pix);
    // `manga` y no `half`: half es palabra reservada en GLSL ES y no compila.
    float manga = beamAt(wk.y);
    float lane = (1.0 - smoothstep(manga - 2.0, manga + 3.0, wk.x)) * wk.z;

    // EL SURCO. Dentro de la calle el oleaje se aplasta: no es que se pinte
    // espuma encima, es que el mar deja de haber. Se nota aunque el barco no
    // ande, porque el casco sigue metido en el agua.
    lift *= 1.0 - 0.85 * lane * (0.40 + 0.60 * uWork);

    float foam = vein * (0.5 + 0.5 * fine) * lift;

    // EL HERVOR de popa: lo mas macizo de todo el mar, y dura poco -- media
    // eslora y se ha deshecho. Va elevado a una y media para que se concentre
    // en la crujia en vez de salir del ancho entero del espejo, y picado por la
    // octava fina: un rectangulo blanco detras del barco se lee como un babero.
    foam += 0.95 * pow(lane, 1.5) * uWork
                 * (1.0 - smoothstep(0.0, 18.0, wk.y)) * (0.45 + 0.55 * fine);

    // LOS BRAZOS. Nacen en la roda -- ahi beamAt vale cero y la V cierra en
    // punta -- y se abren con lo que el barco ha ANDADO desde cada trozo de
    // derrota, no con el reloj: por eso en una virada la V se dobla sola.
    // Van multiplicados por la veta del propio mar para que salgan rotos a
    // trozos; una linea limpia a este grano se lee como pintada encima.
    float arm = manga + min(max(wk.y, 0.0) * uSpread, uArm);
    foam += 1.00 * (1.0 - smoothstep(0.0, 3.5, abs(wk.x - arm)))
                 * wk.z * uWork * (0.60 + 0.40 * vein);

    // Cinco escalones y ni un color entre medias. Con uCut.z por encima de uno
    // -- que es lo que manda src/surface.lua en calma -- el AGUA no puede
    // romper en blanco por mucho que se mire. La estela si: el hervor de popa
    // pasa de uno a proposito, porque una estela es blanca haga el tiempo que
    // haga.
    vec3 c = uWater;
    c = mix(c, uDeep,    step(uDark,  dark * lift));
    c = mix(c, uShallow, step(uCut.x, foam));
    c = mix(c, uFoam,    step(uCut.y, foam));
    c = mix(c, uWhite,   step(uCut.z, foam));
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
        work    = (wake and wake.work) or 0,
        anchor  = { cx, cy },
        origin  = { ou, ov },
        basisX  = { (ex * wx + ey * wy) / cw, (ex * nx + ey * ny) / cn },
        basisY  = { (fx * wx + fy * wy) / cw, (fx * nx + fy * ny) / cn },
        time    = state.time % Surface.PERIOD,
        warp    = 0.30 * (0.35 + 0.65 * sea),
        gain    = 0.30 + 0.70 * sea,
        dark    = 0.45,
        cut     = { 0.24, 0.60, white },
    }
end

--==========================================================================
-- Dibujo
--==========================================================================

local shader, canvas, quad, tried

-- El mar se pinta en un lienzo a escala de ARTE y se sube entero de un tiron.
-- No es un ahorro cualquiera: una pantalla de movil son veinticinco veces mas
-- pixeles que el area de arte, y ademas asi cada invocacion del shader ES un
-- pixel del juego, con lo que la rejilla sale cuadrada sola.
local function ensure()
    if not tried then
        tried = true
        local ok, made = pcall(love.graphics.newShader, SOURCE)
        if ok and made then
            shader = made
            -- El shader necesita algo sobre lo que correr, y un pixel blanco
            -- estirado a toda la pantalla es lo mas barato que hay: de la
            -- imagen no se lee nada, solo se aprovechan sus coordenadas.
            local data = love.image.newImageData(1, 1)
            data:setPixel(0, 0, 1, 1, 1, 1)
            quad = love.graphics.newImage(data)
        elseif not ok then
            print("Rumbo | el mar por shader no compila: " .. tostring(made))
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
    shader:send("uBasisX", f.basisX)
    shader:send("uBasisY", f.basisY)
    shader:send("uTime",   f.time)
    shader:send("uWarp",   f.warp)
    shader:send("uGain",   f.gain)
    shader:send("uDark",   f.dark)
    shader:send("uCut",    f.cut)
    shader:send("uTrack",  unpack(f.track))
    shader:send("uBeam",   f.beam)
    shader:send("uHull",   f.hull)
    shader:send("uSpread", f.spread)
    shader:send("uArm",    f.arm)
    shader:send("uWork",   f.work)
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
