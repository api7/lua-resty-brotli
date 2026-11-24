-- SPDX-License-Identifier: Apache-2.0
local ffi = require("ffi")

ffi.cdef[[
typedef struct BrotliEncoderStateStruct BrotliEncoderState;
typedef struct BrotliDecoderStateStruct BrotliDecoderState;
typedef void *(*brotli_alloc_func)(void *, size_t);
typedef void (*brotli_free_func)(void *, void *);

BrotliEncoderState *BrotliEncoderCreateInstance(brotli_alloc_func, brotli_free_func, void *);
void BrotliEncoderDestroyInstance(BrotliEncoderState *);
int BrotliEncoderSetParameter(BrotliEncoderState *, int, uint32_t);
int BrotliEncoderCompressStream(BrotliEncoderState *, int, size_t *, const uint8_t **,
                                size_t *, uint8_t **, size_t *);
int BrotliEncoderHasMoreOutput(BrotliEncoderState *);

BrotliDecoderState *BrotliDecoderCreateInstance(brotli_alloc_func, brotli_free_func, void *);
void BrotliDecoderDestroyInstance(BrotliDecoderState *);
int BrotliDecoderDecompressStream(BrotliDecoderState *, size_t *, const uint8_t **,
                                  size_t *, uint8_t **, size_t *);
int BrotliDecoderGetErrorCode(const BrotliDecoderState *);
const char *BrotliDecoderErrorString(int);
]]

local function load_library(name)
    if ffi.os == "Linux" then
        return ffi.load("lib" .. name .. ".so.1")
    end
    return ffi.load(name)
end

local enc = load_library("brotlienc")
local dec = load_library("brotlidec")
local CHUNK_SIZE = 16384
local FLUSH, FINISH = 1, 2
local ERROR, SUCCESS, NEEDS_INPUT = 0, 1, 2

local cursor = ffi.typeof([[
    struct {
        size_t available_in[1], available_out[1];
        const uint8_t *next_in[1];
        uint8_t *next_out[1];
    }
]])
local buffer = ffi.typeof("uint8_t[?]")
local bytes = ffi.typeof("const uint8_t *")

local function prepare(c, input, out, capacity)
    c.next_in[0] = ffi.cast(bytes, input) + (#input - tonumber(c.available_in[0]))
    c.next_out[0] = out
    c.available_out[0] = capacity
end

local encoder = {}
encoder.__index = encoder
local M = {}

local function close_encoder(self)
    enc.BrotliEncoderDestroyInstance(ffi.gc(self.state, nil))
    self.state = nil
end

local parameters = {
    mode = {0, 0, 2},
    quality = {1, 0, 11},
    lgwin = {2, 10, 24},
    lgblock = {3, 16, 24},
}

function M.new_encoder(options)
    if options ~= nil and type(options) ~= "table" then
        return nil, "expected an encoder options table"
    end
    local state = enc.BrotliEncoderCreateInstance(nil, nil, nil)
    if state == nil then
        return nil, "could not allocate Brotli encoder"
    end
    local self = setmetatable({state = ffi.gc(state, enc.BrotliEncoderDestroyInstance)},
                              encoder)
    for key, value in pairs(options or {}) do
        local p = parameters[key]
        if not p then
            close_encoder(self)
            return nil, "unknown Brotli encoder option: " .. tostring(key)
        end
        if (key == "lgwin" or key == "lgblock") and value == 0 then
            -- Keep libbrotli's automatic setting.
        elseif type(value) ~= "number" or value % 1 ~= 0 or value < p[2] or value > p[3]
               or enc.BrotliEncoderSetParameter(state, p[1], value) == 0 then
            close_encoder(self)
            return nil, "invalid Brotli encoder option: " .. key
        end
    end
    self.cursor = cursor()
    self.out = buffer(CHUNK_SIZE)
    return self
end

local function encode(self, input, operation)
    if not self.state then
        return nil, "Brotli encoder is closed"
    end
    if type(input) ~= "string" then
        return nil, "expected a string"
    end
    local c = self.cursor
    c.available_in[0] = #input
    local chunks = {}
    repeat
        prepare(c, input, self.out, CHUNK_SIZE)
        if enc.BrotliEncoderCompressStream(self.state, operation, c.available_in, c.next_in,
                                           c.available_out, c.next_out, nil) == 0 then
            close_encoder(self)
            return nil, "Brotli compression failed"
        end
        chunks[#chunks + 1] = ffi.string(self.out, CHUNK_SIZE - tonumber(c.available_out[0]))
    until c.available_in[0] == 0 and enc.BrotliEncoderHasMoreOutput(self.state) == 0
    if operation == FINISH then
        close_encoder(self)
    end
    if #chunks == 1 then
        return chunks[1]
    end
    return table.concat(chunks)
end

function encoder:write(input)
    return encode(self, input, FLUSH)
end

function encoder:finish()
    return encode(self, "", FINISH)
end

function M.decode(input, max_output)
    if type(input) ~= "string" then
        return nil, "expected a string"
    end
    if max_output ~= nil then
        if type(max_output) ~= "number" or max_output % 1 ~= 0 or max_output < 0 then
            return nil, "expected a nonnegative integer output limit"
        end
        if max_output == 0 then
            return ""
        end
    end
    local state = dec.BrotliDecoderCreateInstance(nil, nil, nil)
    if state == nil then
        return nil, "could not allocate Brotli decoder"
    end
    state = ffi.gc(state, dec.BrotliDecoderDestroyInstance)
    local remaining = max_output or math.huge
    local out = buffer(math.min(remaining, CHUNK_SIZE))
    local c = cursor()
    c.available_in[0] = #input
    local chunks, err = {}
    local input_exhausted
    repeat
        local capacity = math.min(remaining, CHUNK_SIZE)
        prepare(c, input, out, capacity)
        local status = dec.BrotliDecoderDecompressStream(state, c.available_in, c.next_in,
                                                         c.available_out, c.next_out, nil)
        local written = capacity - tonumber(c.available_out[0])
        chunks[#chunks + 1] = ffi.string(out, written)
        remaining = remaining - written
        -- NEEDS_INPUT can still leave decoded bytes in the native ring buffer.
        input_exhausted = status == NEEDS_INPUT and written < capacity
        if status == ERROR then
            err = ffi.string(dec.BrotliDecoderErrorString(dec.BrotliDecoderGetErrorCode(state)))
        elseif input_exhausted and max_output == nil then
            err = "incomplete Brotli stream"
        elseif status == SUCCESS and max_output == nil and c.available_in[0] ~= 0 then
            err = "trailing data after Brotli stream"
        end
    until status == SUCCESS or input_exhausted or err or remaining == 0
    dec.BrotliDecoderDestroyInstance(ffi.gc(state, nil))
    if err then
        return nil, err
    end
    return table.concat(chunks)
end

return M
