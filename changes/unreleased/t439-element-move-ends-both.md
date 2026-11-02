### Fixed

- **A view taken through an element ends when that element's buffer
  moves** (Agora #439, #349; probes element_view_kept_past_*). `: s v (
  string_data ( vec_at vs 0 ) )` survived the element growing through a
  binding of it (`: String e ( vec_at vs 0 )`), a `vec_get` payload, or a
  callee that grows an element of the Vec it is handed (heap-use-after-free). Where an element's buffer may move, the
  owner's views end now: the ones into its elements and the ones recorded
  of the owner itself, as such a view is. A slice of the Vec itself is
  ended there too. That is safe but stricter than it needs to be until
  views through an element are marked so (#430).
