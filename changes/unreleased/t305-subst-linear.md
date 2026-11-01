### Performance

- **A generic instantiation substitutes its type parameters in one pass**
  (Agora #305). `subst_source` copied the result built so far for every
  word of a generic body, and stepped through the body by copying all of
  what was left of it: quadratic in the body's length, once per type
  parameter per instantiation. It now sizes the result in one pass and
  writes it in a second, with the same word rules.
  - dst_flagship compiles in 2.7 % fewer instructions.
  - Output is byte-identical (tools/tree_sweep.sh, 3620 files).
