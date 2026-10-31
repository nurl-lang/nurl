### Added

- **`query_value qs key` and `request_query_int req key`** (stdlib/ext/http_request.nu): a query parameter read in place — the first value of `key` as a view of the query's bytes (raw, not percent-decoded), and that value as an integer — with nothing allocated, where `parse_query` decodes every pair into Strings of its own. **`slice_to_int b`** (core/string.nu) is `string_to_int` over a `( Slice u )`.

### Performance

- **The HTTP peer benchmark's `/async-db` reads its query parameters in place** (Agora #43), as the Rust peer's `split` does, instead of decoding the whole query into allocated pairs three times per request; psql's cell accessors read a cell's span once. Instructions per `/async-db` request (callgrind, 50 items): 536.9k → 505.9k (hyper + tokio-postgres: 362k); the rest of the gap is the drop journal's per-binding registrations inside a handler (agora #283) and calls the compiler emits with a constant NULL (agora #282).
