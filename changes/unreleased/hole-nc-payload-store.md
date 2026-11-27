### Security

- **A `??` payload that cannot be copied is no longer released twice.** A
  payload whose type has no copy, such as a struct holding a trait object
  (`: Pet { % Speaker s }`), was bound in its arm as a plain value. The
  compiler-made drop gave it no cursor over the option binding or
  parameter it came out of, and no lent registration for an enum or a
  field's option. Moving it out of the arm (`( vec_push vs p )`,
  `( chan_send ch p )`) left the option's drop flag set, so the option
  released the payload again: a double free, which Windows reports as
  heap corruption. Matching the option again after the move also
  compiled, and read freed memory.
  - **An option binding's or parameter's payload** is now a cursor over it,
    as a String or Vec payload is. Moving the payload out takes the
    option's ownership along.
  - **The payload of an enum, or of an option in a struct's field,** is now
    lent to the arm (h231). Reading it is unchanged. Storing it is refused:
    it would need a copy, and one cannot be made.
  - **Migration:** a program that is refused now was unsound before, and
    every in-repo program that compiled before still does. Three shapes
    change:
    - matching the option again after its payload moved out: match it
      once and keep what the arm needs, or hand the value back out of the
      arm (`: ?Pet back ?? got { T p → … }`) instead of reading `got`
      again;
    - moving the same payload out twice (two pushes): move it once;
    - storing a payload of an enum, or of an option in a struct's field
      (`( vec_push vs p )` in its arm): take the value out of its owner
      first, moving the enum or replacing the field, then store it.
