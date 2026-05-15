// alias_rewrite_types_mod.nu — helper module for the alias-rewrite-
// types regression. When imported with an alias `m`, every top-level
// decl name here gets renamed to `m__<name>` at compile time so callers
// can reach them via `m::<name>` namespacing:
//
//   * struct `Point`
//   * generic struct `Box [A]`
//   * enum `Shade` + variants `Light`, `Dark`
//   * global const `PI_FIXED`

: Point {
    i x
    i y
}

: | Shade {
    Light
    Dark
}

: i PI_FIXED 314

@ make_point i px i py → Point {
    ^ @ Point { px py }
}
