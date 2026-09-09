-- Persistencia.
--
-- El estado del mundo es datos planos (ver src/world.lua), asi que guardarlo
-- es volcarlo como codigo Lua y cargarlo es ejecutarlo. Sin libreria de JSON,
-- sin esquema que mantener en dos sitios: si anades un campo al estado, se
-- guarda solo.
--
-- El archivo vive en el directorio de guardado de LOVE:
--   Linux  ~/.local/share/love/rumbo/save.lua
--   macOS  ~/Library/Application Support/LOVE/rumbo/save.lua
-- Borrarlo empieza una partida nueva.

local Save = {}

Save.FILE = "save.lua"

local function encode(value, indent)
    local t = type(value)
    if t == "number" then
        -- Tres decimales: mas es ruido y engorda el archivo.
        if value == math.floor(value) then return tostring(math.floor(value)) end
        return string.format("%.3f", value)
    elseif t == "string" then
        return string.format("%q", value)
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        local pad = indent .. "  "
        local parts = {}
        -- Primero la parte de array, para que las listas se lean como listas.
        local n = #value
        for i = 1, n do
            parts[#parts + 1] = pad .. encode(value[i], pad)
        end
        local keys = {}
        for k in pairs(value) do
            if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local name
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                name = k .. " = "
            else
                name = "[" .. encode(k, pad) .. "] = "
            end
            parts[#parts + 1] = pad .. name .. encode(value[k], pad)
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

function Save.exists()
    return love.filesystem.getInfo(Save.FILE) ~= nil
end

function Save.write(state)
    state.savedAt = os.time()
    local ok, err = love.filesystem.write(Save.FILE, "return " .. encode(state, "") .. "\n")
    if not ok then print("[save] no se pudo guardar: " .. tostring(err)) end
    return ok
end

-- Devuelve el estado y los segundos transcurridos desde el ultimo guardado.
-- Un reloj movido hacia atras da negativo; se recorta a cero en vez de
-- regalar progreso o petar.
function Save.read()
    if not Save.exists() then return nil, 0 end
    local chunk, err = love.filesystem.load(Save.FILE)
    if not chunk then
        print("[save] partida ilegible: " .. tostring(err))
        return nil, 0
    end
    local ok, state = pcall(chunk)
    if not ok or type(state) ~= "table" then
        print("[save] partida corrupta, se empieza de cero")
        return nil, 0
    end
    local elapsed = math.max(0, os.time() - (state.savedAt or os.time()))
    return state, elapsed
end

function Save.delete()
    if Save.exists() then love.filesystem.remove(Save.FILE) end
end

return Save
