-- Each invocation owns its cache and each loaded chunk owns its import closure.
local read_text, decode, is_array = fs.read_text, json.decode, json.is_array
local load_chunk, unpack_args = load, table.unpack
local function normalize(path)
  if path == '' or path:find('\0', 1, true) then error('invalid source/import path', 0) end
  local absolute, parts = path:sub(1, 1) == '/', {}
  for part in path:gmatch('[^/]+') do
    if part == '..' then
      if #parts == 0 then error('import path escapes its root', 0) end
      parts[#parts] = nil
    elseif part ~= '.' then
      parts[#parts + 1] = part
    end
  end
  return (absolute and '/' or '') .. table.concat(parts, '/')
end
return function(source, entry, args_json, source_path)
  local cache, loading = {}, {}
  local function environment(origin, root)
    local env = root or setmetatable({}, {__index = _G})
    env._G = env
    env.import = function(path)
      if type(path) ~= 'string' then error('import path must be a string', 0) end
      local resolved
      if path:sub(1, 1) == '/' then
        resolved = normalize(path)
      else
        resolved = normalize((origin:match('^(.*[/])') or '') .. path)
      end
      if cache[resolved] ~= nil then return cache[resolved] end
      if loading[resolved] then error('import cycle: ' .. resolved, 0) end
      loading[resolved] = true
      local ok, exports = pcall(function()
        local chunk, message = load_chunk(read_text(resolved), '@' .. resolved, 't', environment(resolved))
        if not chunk then error(message, 0) end
        return chunk()
      end)
      loading[resolved] = nil
      if not ok then error(exports, 0) end
      if exports == nil then error('import module must return exports: ' .. resolved, 0) end
      cache[resolved] = exports
      return exports
    end
    return env
  end
  local origin = source_path and normalize(source_path) or '(input)'
  local env = environment(origin, _G)
  local chunk, message = load_chunk(source, source_path and '@' .. origin or '=(input)', 't', env)
  if not chunk then error(message, 0) end
  chunk()
  local name = entry or 'main'
  local fn = env[name]
  if type(fn) ~= 'function' then error("entry '" .. name .. "' is not a function", 0) end
  local args = args_json and decode(args_json) or nil
  if args_json and not is_array(args) then error('args-json must encode an array', 0) end
  if not args then return fn() end
  -- Explicit null arguments become Lua nil, retaining their argument positions.
  local count = #args
  for i = 1, count do if args[i] == json.null then args[i] = nil end end
  return fn(unpack_args(args, 1, count))
end
