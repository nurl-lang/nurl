### Fixed

- **A lend handed to a callee compiled after its caller is copied where
  the callee takes it over** (Agora #459; probes
  option_lend_handed_to_a_generic_keeper,
  option_lend_handed_to_a_keeper_defined_below,
  result_lend_handed_to_a_library_keeper and three more).
  `( unwrap_or [String] ( maybe o 0 ) d )`, with `unwrap_or` taking its
  option over and `maybe` handing back `o` on that run, gave `o`'s own
  value to the callee. The value was released under `o`, which read freed
  memory. The same happened with stdlib's `res_unwrap_or` and with any
  such callee defined below its caller. The call's result is now copied on
  the runs it lends whenever the callee takes it over, decided from the
  callee's final summary at the end of the module, as it already was for a
  callee defined above.
- **A generic forwarder compiled after its callee hands on the callee's
  answer** (Agora #459; probes
  lend_handed_back_through_a_generic_forwarder_compiled_after_its_callee
  and its String form). `: T r ( g2 [T] a k f ) ^ r`, instantiated after
  `g2 [?String]`, called `r` its own on every run and handed it back as
  such, so its caller released what `o` still held. A call to a generic
  instance compiled already now reads that instance's per-call answer.
- **A forwarder of a keeper says per call whether it hands its result
  over** (Agora #459; probes
  forwarder_of_a_generic_keeper_hands_on_its_answer and three more).
  `@ gfw [A] ? A o A d → A { : A x ( ug [A] o d ) ^ x }`, with `ug` taking
  `o` over and handing back `d` otherwise, told its caller "lent" on every
  run. The caller copied what it was given, and the value `gfw` had handed
  over leaked. The binding's own per-call answer is now handed on, when it
  is returned bare, rebound, as a value block's tail or wrapped in an
  option.
- **A join over a binding a call may have handed a value of its own keeps
  that value alive** (Agora #459; probes
  block_tail_join_over_a_call_bound_binding,
  bound_block_join_over_a_call_bound_binding and
  block_arm_join_over_a_call_bound_binding). `^ { : String x ( pick a k )
  ? c x a }` handed back x's value and then released it, as x was dropped
  on the way out (heap-use-after-free). The same happened with a binding
  of such a join (`: String r { ? c x a } ^ r`) and with block arms
  (`? c { x } { a }`). On the runs x owns its value, the join now copies
  it, or takes it from x.
- **A join's arm hands over a parameter only where it holds that
  parameter's value** (Agora #459; probe
  joined_call_bound_binding_hands_over_its_source_only_by_identity).
  `: String x ( pick a k ) ^ ? c x a` stopped dropping `a` whenever the x
  arm was taken, also on the runs where `pick` handed back a fresh value,
  and `a` leaked. It is now told by the values themselves: an option or a
  result by its payload, an `Rc`, a `Box` or a map by its handle.
