### Fixed

- **A function handing back its option parameter says it lent it**
  (Agora #388; probe option_owner_given_back_its_value_on_some_runs_by_a_call).
  `@ maybe ?String a i k → ?String`, returning `a` when `k` is 0 and a fresh
  value otherwise, told its caller the value it handed back was its own on
  both runs. `= o ( maybe o k )` then released `o`'s old value on the run
  that handed it back, and `o` went on to hold freed memory. A parameter
  handed back as is is now answered "lent" for options and results too, as
  it already was for a String or a Vec.
