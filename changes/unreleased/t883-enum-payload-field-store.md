### Fixed

- **A field of an enum's `??` payload can no longer be given an owning value inside the arm** (AGORA-883). `?? e { ES b → { = . b name ( string_from … ) } … }` stored into the arm's copy of the payload: the enum kept its old name, and the new String was released by no one (a leak). It is refused now, as for the other borrowed copies, with the way out: give the enum a new value with the field changed (`= e @ E { ES @ H { … } }`), or `mem_dup` an owned copy and change that.
