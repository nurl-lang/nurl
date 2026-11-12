### Fixed

- **A user enum field read out of a call's result and matched in place
  lends its payloads by that call** (Agora #681).
  `?? . ( arc_get [App] mine ) ev { Got p → { ( growp p k ) } Nil → {} }`
  passed the frozen-Arc rule, so eight threads pushing to the payload's
  Vec double-freed it. `?? . ( vec_at [App] apps 0 ) ev { Got p → … }`
  lent its payload from nothing, so growing it did not end a Slice of it
  (a use after free). Both are now refused, as the option field beside
  them and the enum bound to a name first already were. A field of a fresh
  call's result stays the arm's own.
