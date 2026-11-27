// A struct holding another struct: pairs inside pairs, handed to a function.
: In { i a i b }
: Out { In inner i c }

@ f Out o → i { ^ + . o c 0 }

@ main → i {
    : In i0 @ In { 1 2 }
    : Out o @ Out { i0 3 }
    ^ ( f o )
}
