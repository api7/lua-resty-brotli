# lua-resty-brotli

LuaJIT bindings for the system Brotli library. Encode a response in chunks and flush each chunk as it arrives, or decode a whole stream or its prefix.

## Install

Install LuaJIT (or OpenResty) and the Brotli shared libraries. The dynamic loader must be able to find the encoder, decoder, and their common library. On Linux the module loads `libbrotlienc.so.1` and `libbrotlidec.so.1`.

```sh
luarocks --lua-version=5.1 install lua-resty-brotli
```

## Use

```lua
local brotli = require("resty.brotli")
local encoder = assert(brotli.new_encoder({quality = 6}))

local first = assert(encoder:write("first chunk"))
local second = assert(encoder:write(" and second chunk"))
local ending = assert(encoder:finish())

assert(brotli.decode(first, 100) == "first chunk")
assert(brotli.decode(first .. second .. ending) == "first chunk and second chunk")
```

- `new_encoder([options])` creates an independent stream. Options are integers. `mode` accepts 0 (generic), 1 (text), or 2 (font). `quality` ranges from 0 to 11, `lgwin` from 10 to 24, and `lgblock` from 16 to 24. Omitted options and zero for either size use the native defaults.
- `encoder:write(chunk)` consumes a binary string and returns compressed bytes ready to send. A decoder can read the plaintext through the end of this chunk.
- `encoder:finish()` returns the final bytes and closes the encoder. Append these bytes even when the input was empty.
- `decode(data)` returns the decoded contents of one complete stream. Malformed input, truncated input, and trailing bytes return an error.
- `decode(data, max_output)` returns up to the given number of decoded bytes. Input can end partway through a stream. Decoding stops when it reaches the limit, the end of the stream, or the end of the supplied input. The limit bounds the output passed back by the native decoder. The Brotli library also allocates its own decoding state.

Operations return `nil, error_message` on failure. Finished streams release native state immediately. LuaJIT's garbage collector releases abandoned encoders.

## Test

Install the Brotli command-line tool and run the interoperability tests from the repository root.

```sh
LUA_PATH='./lib/?.lua;;' ./test/run.sh
```

## Release

Publish a GitHub release tagged `vX.Y.Z` at the reviewed commit containing the matching rockspec. The release workflow uploads the rockspec and source rock to LuaRocks using `LUAROCKS_TOKEN`.

## License

Apache License 2.0. See [LICENSE](LICENSE).
