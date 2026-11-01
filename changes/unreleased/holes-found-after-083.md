### Known issues

- **Four more soundness holes were open in 0.83.0 already; they were
  found after its fold** (Agora #311, #312, #314, #315; claude-formal's
  design maps for #272 and #295, each re-run under ASan on main). They are
  #311 (a binding re-pointed on one path of a `?` keeps no borrow source
  on the other), #312 (a view a closure gives one of its captures by a
  route nurlc does not record), #314 (a container change through a `?` /
  `??` join argument) and #315 (a callee that changes what is inside its
  parameter's elements). `docs/LIMITATIONS.md` lists them with how to
  stay clear of each, from now on, and 0.83.0's own list missed them.
