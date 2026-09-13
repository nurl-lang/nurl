// A failed try must point to its own backslash, even across line breaks.
: | FirstError { First }
: | SecondError { Second }

@ first → !v FirstError { ^ @ !v FirstError { F First } }

@ main → !v SecondError {
    \
    ( first )
    ^ @ !v SecondError { T 0 }
}
