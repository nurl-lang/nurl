### Fixed

- **A view stored through a copy of an owner's handle reaches the owner**
  (Agora #414; probes view_pushed_through_a_join_of_names_outlives_its_source,
  view_pushed_into_a_join_of_names_outlives_its_source,
  view_pushed_through_a_loop_element_outlives_its_source and 15 more).
  `( vec_push [s] w ( string_data loc ) )` with `w` a binding of a join of
  names (`: ( Vec s ) w ? c { vs } { vs2 }`, or a `??`), a `~` loop's
  element, a program enum's payload, or a value handed back through a call
  (`( id ( vec_at vv 0 ) )`, `( opt_unwrap ( vec_get vv 0 ) )`), or with
  such a join or call written as the container itself, recorded the view in
  `w` only. The owner read after `loc` ended read freed memory. The store
  now lands in every owner the container may be a part of, as it does
  through a borrow (#292), and that read is refused. Reading while `loc`
  is in scope is unchanged, and so is a binding given a new value since, or
  an owner whose value moved away for good.
