### Fixed

- **A struct whose index views its own arena's elements is tracked across
  calls and returns** (Agora #600). A callee that pushes `string_data` of
  an element of `. t arena` into `. t idx`, or a function that builds such
  a struct and returns it, left the caller's struct tied to nothing:
  clearing, popping or replacing the arena's Strings, or growing one,
  then reading the index was a heap-use-after-free. The callee's answer
  now says so (`h>.^arena`; `.^arena` for a returned value), and the
  caller's binding depends on that field of itself.
- **A call that changes one field of an argument no longer ends views of
  its other fields** (Agora #600). Drop summaries are per field now: a
  helper that inserts into a struct's map or clears another of its Vecs
  leaves views of the struct's arena alone. A self-viewing value moved
  into an Arc stays accepted (an Arc's payload is frozen).
