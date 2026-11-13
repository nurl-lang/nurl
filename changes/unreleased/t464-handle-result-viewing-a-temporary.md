### Fixed

- **A call's result that holds a view of its temporary argument** (Agora
  #464): `( show ( mk ( string_from … ) ) )`, with `mk` handing back an
  enum or a struct holding `( string_data line )`, freed the temporary
  right after `mk`, and `show` read freed memory. The temporary now lives
  until the statement's end. Binding such a result past its statement
  (`: Tok t ( mk ( string_from … ) )`) is refused with the same message
  as for a bare view: bind the argument to a name first.
