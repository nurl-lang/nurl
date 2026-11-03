### Fixed

- **A function that clears an element of its parameter through a local or
  a `??` payload says so in its summary** (Agora #447; probes
  function_clears_its_parameters_element_*,
  function_clears_a_payload_matched_out_of_its_parameter). `: e ( vec_at vv 0 ) ( clr e )`,
  the same through the function's closure parameter, and
  `?? ( vec_get vv 0 ) { T e → { ( clr e ) } … }` put no drop of `vv`'s
  elements in the function's summary, so a caller still reading a String
  inside that element read freed memory. These are refused now, as the
  element handed on directly was (#443). A reader stays accepted. The
  nested and generic forms are #461.
