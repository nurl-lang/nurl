### Performance

- **The compiler keeps its list of `unsafe` items only for `--unsafe-report`** (AGORA-766). Each `unsafe` function, foreign declaration or `unsafe` impl was checked against a copy of every item listed before it, so the cost grew quadratically with the program's `unsafe` items. Only the report reads the list. With the rest of AGORA-766's change included, nurlc's self-compile runs 0.56 % fewer instructions (26,000M → 25,854M) and peaks 44 KB lower. Output is byte-identical, and `--unsafe-report` lists the same items.
