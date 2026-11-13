### Fixed

- **A call's lend of a value block argument's binding is copied when
  returned** (Agora #833). `^ ( id { : String t ( mk c ) t } )` handed
  back `t`, which the function released on its way out; it is copied now,
  as `^ ( id t )`'s result is.
