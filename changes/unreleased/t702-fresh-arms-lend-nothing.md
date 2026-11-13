### Fixed

- **A returned `??` whose arms hand over values of their own lends
  nothing of its scrutinee** (Agora #702). `^ ?? ( vec_get [String] p 0 )
  { T v → ( string_clone v ) F → ( string_from … ) }` was summarised as
  borrowing `p` in expression form (its statement and bound forms were
  exact), so the caller was refused once `p` moved. The join publishes its
  scrutinee's lend only when an arm may hand the payload back as it is.
