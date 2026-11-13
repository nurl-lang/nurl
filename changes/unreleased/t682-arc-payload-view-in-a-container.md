### Fixed

- **A view of an Arc's payload kept in a container stays one** (Agora
  #682). A `( Slice T )` over an Arc's payload went through a local `Vec`,
  a `HashMap`, a struct a `Vec` holds, or a struct a helper builds. Read
  back out with `vec_get`, `vec_at`, `map_get` or a helper, it was taken
  for a view of nothing, so `( slice_put w 0 x )` through it compiled. That
  changed what every thread holding a clone reads: a data race, and a
  double free where the element owns memory. The same held for a struct's
  view field given a payload view after the struct was built. These are
  refused now, as the view bound directly was. Reading through such views,
  and changing the container itself, still compile.
