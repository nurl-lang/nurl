### Added

- **`vec_split_off_packed v at` and `vec_with_cap_packed n`** (core/vec.nu; `raw`: for an element type aligned to at most 8). Each makes a Vec whose buffer shares its handle's allocation, the packed layout `string_from_bytes_packed` gives a String:
  - `vec_split_off_packed` moves the elements `[at, len)` out of `v`, exactly that many;
  - `vec_with_cap_packed` makes an empty one with room for `n`.
  
  That is one allocation instead of two, for a container assembled on a scratch stack and closed once its count is known.

### Fixed

- **`vec_shrink_to_fit` on a packed buffer** handed realloc (or free, when the Vec was empty) a pointer into the middle of the handle's block. A packed String never reached it; a parsed JSON array or object now can (`?? j { JArr v → ( vec_shrink_to_fit [Json] v ) }`). Such a buffer is already exact, and the call now leaves it as it is.

### Performance

- **json.nu's parser does less per value** (Agora #291):
  - A step answers whether it succeeded. Values go onto one stack, and a failure records its kind and byte for the root to locate. Before, every value returned a `!Json JsonError`: a value and a four-field error, written whole at each return and copied at every level.
  - An array or object is one allocation of exactly its members (`vec_split_off_packed`). Before, it was a handle, an 8-slot buffer and a reallocation past eight members; `[]` now keeps 24 bytes, not 152.
  - A string's end is found sixteen bytes at a time. `nurl_v128_ldn` takes a short string's last bytes, so there is no byte loop at either end, on any alignment.
  - The whitespace skip stops at the first token byte.

  Results, error positions and line/column, and JSONTestSuite verdicts are unchanged: a differential run over 15,770 documents (the suite plus generated, truncated and mutated ones) prints the same value or error for every one. `bench/json_parse`: 88.1M → 64.2M instructions. A two-string jsonb cell: 126 → 96 ns.
- **The JSON writer's escaper** copies each run of plain bytes with one partial vector store (the same 16-byte scan). A key goes out with its comma and colon in one reservation. `bytes_push_int` writes through the buffer's control block: one capacity check and one length commit. The HTTP peer benchmark's `/async-db` (50 items): 505.6k → 415.7k instructions per request (hyper + tokio-postgres: 362k); `/json`, `/db`, `/queries` and `/updates` take 1–3 % fewer.
