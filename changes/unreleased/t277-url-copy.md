### Performance

- **An http-client request costs a fifth fewer instructions** (Agora
  #277). Three stdlib routines built their strings one byte at a time,
  through `string_push_char` and its buffer regrowth. The worst was
  `_hp_blob_has`, which lowercased the caller's whole header blob into
  a fresh string for each of the three names it looks for.
  - `url_parse` now copies each component once, from its byte range of
    the input. The scheme is lowercased in one reserved write.
  - `url_percent_decode` and `url_query_decode` decode straight from
    the input's bytes through a reserved cursor. The query decoder used
    to copy each key and value byte by byte before decoding them.
  - `_hp_blob_has` (stdlib/ext/http_pure.nu) compares names in place,
    case folded per byte, from line start to line start. The header
    parser's `__hp_to_lower` writes its copy in one reserved write.

  Measured with callgrind over 3,000 keep-alive GETs from
  `packages/http-client` to its test server: 34.4K → 27.6K instructions
  per request on the client. The parsers' output is unchanged. The new
  `compiler/tests/url_parse_edges` was checked against the old
  implementation: '%' escapes cut short at a component's end, '+' in
  both decoders, '=' and '&' inside a query, empty parts, IPv6 and the
  scheme's case.
