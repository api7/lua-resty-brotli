-- SPDX-License-Identifier: Apache-2.0
local brotli = require("resty.brotli")

local function read(path)
    local f = assert(io.open(path, "rb"))
    local data = assert(f:read("*a"))
    assert(f:close())
    return data
end

local function write(path, data)
    local f = assert(io.open(path, "wb"))
    assert(f:write(data))
    assert(f:close())
end

local function fails(value, err)
    assert(value == nil and type(err) == "string" and #err > 0)
end

local input, compressed = read(arg[1]), read(arg[2])
assert(brotli.decode(compressed) == input)
for _, n in ipairs({0, 1, 16383, 16384, 16385, #input, #input + 1}) do
    assert(brotli.decode(compressed, n) == input:sub(1, n))
end

local stream = assert(brotli.new_encoder({quality = 4, mode = 0, lgwin = 19, lgblock = 16}))
local split = math.floor(#input / 2)
local prefix = assert(stream:write(input:sub(1, split)))
assert(brotli.decode(prefix, #input) == input:sub(1, split))
fails(brotli.decode(prefix))
local rest = assert(stream:write(input:sub(split + 1)))
local tail = assert(stream:finish())
write(arg[3], prefix .. rest .. tail)
fails(stream:finish())
fails(stream:write(""))

local empty = assert(brotli.new_encoder({lgwin = 0, lgblock = 0}))
assert(brotli.decode(assert(empty:write("")) .. assert(empty:finish())) == "")
fails(brotli.decode(""))
assert(brotli.decode("", 10) == "")
fails(brotli.decode(compressed .. "extra"))
fails(brotli.decode(string.rep(string.char(255), 20)))
fails(brotli.decode("x", -1))
fails(brotli.new_encoder({quality = 12}))
fails(brotli.new_encoder({lgwin = 1}))
fails(brotli.new_encoder({lgblock = 15}))

local large = ("abc"):rep(100000)
local high_ratio = assert(brotli.new_encoder({quality = 4}))
local small = assert(high_ratio:write(large)) .. assert(high_ratio:finish())
assert(#small < 100)
assert(brotli.decode(small, 63) == large:sub(1, 63))
assert(brotli.decode(small) == large)
