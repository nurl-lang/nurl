### Performance

- **The "may this drop read a view?" question is answered once per type,
  not once per path to it** (Agora #305). For each binding, the borrow
  checker asks whether dropping its type may run a destructor that reads a
  view. The walk through field types, payloads and elements is capped at
  depth 8, and it met the same types over and over on the way down:
  dst_flagship's 494 questions made 750,296 calls for 746 distinct
  (depth, type) pairs.
  - A question now keeps its answers in a table of its own, dropped when it
    is answered. The answers are the same.
  - dst_flagship compiles in 5.5 % fewer instructions and 2.5 % fewer
    cycles, with slightly lower peak RSS.
  - Output is byte-identical (tools/tree_sweep.sh).
