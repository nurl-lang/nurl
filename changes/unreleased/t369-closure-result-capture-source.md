### Fixed

- **A closure's result that views its capture is tied to that capture**
  (Agora #369; probes closure_returns_a_struct_viewing_its_capture,
  closure_returns_a_value_viewing_a_live_capture_runs_clean). `: ( @ T2 ) mk
  \ → T2 { ^ @ T2 { ( string_data line ) ( string_from `owned` ) } }`,
  with `line` a captured String, handed back a value with no source:
  pushed into a Vec that outlived `line`, it was read after `line` was
  freed. A closure call's result now depends on the closure's captures
  as well as on its arguments. (An enum payload that views its source,
  in closures and functions alike, is Agora #442.)
