### Fixed

- **More ways of putting a parameter into a local reach the helper's summary** (Agora #786). After #770, a helper that put its `Rc` parameter into a local and then replaced or grew the payload through it was still accepted for these spellings, and the caller's view through another handle dangled:
  - storing it into a field after building, `= . w a h`, by any value: a share `( rc_clone h )`, a call that keeps it, a literal or a join made of it, and through a nested path `= . . w a b …`;
  - a literal chosen by `?` or written in a block;
  - pushing it into a local's Vec field, `( vec_push . x hs h )`;
  - pushing a parameter's field, a literal made of it, or a `?` / block / `??` value of it;
  - a helper that puts its first argument into its second, `( addto2 h xs )`, or takes it as `sink` there, `( adds ( rc_clone h ) xs )`;
  - a struct holding it pushed into a Vec and handed on inline.

  These are refused now; reading what was put stays accepted.

### Known issues

- A helper that keeps an argument somewhere is taken to keep it in every local among its other arguments (`( register h reg mine )` then changing `mine`): the keep summary says that a callee keeps an argument, not where (Agora #780's family).
