// Function pointers do not name data elements writable through inout.
@ change inout i value → v { = value 1 }

@ main → i {
    : ~ * ( @ i ) data # *( @ i ) 0
    ( change . data 0 )
    ^ 0
}
