### Fixed

- **A second name of a fresh `s` binding's buffer cannot be handed back**
  (Agora #478). After `: s a ( nurl_str_cat … )`, `^ ( mem_dup a )`,
  `^ ( same a )` with `same` defined below, and `^ @ W { ( mem_dup a ) }`
  handed back a's buffer, which the return released: a heap-use-after-free
  in safe code. The walk took a value written as a call or a literal whose
  source expression names `a` for `a` handed over by name, as `^ a` is. A
  return's row now says when its value is no binding named (`n` for a bare
  `s`, `x` for another view), and such a value points into a's buffer. All
  of these are refused, as their bound spellings already were. `^ a` still
  hands the string over. `^ ( same a )` with `same` defined above runs
  clean: codegen knows the call hands its argument back and hands a's own
  value over.
