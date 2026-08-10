// diag_ascii_arrow.nu — '->' where NURL's '→' belongs.
//
// The ASCII pair does not lex as an arrow at all: '-' and '>' are two
// separate operators, so the parse died asking for a TYPE and never
// mentioned the arrow. A model that cannot emit U+2192 had no way to
// learn that from "expected a type, found '-'".
//
// The token table was telling the same lie from the other side: it
// rendered TT_ARROW as '->', naming a spelling that cannot produce that
// token, so "found '->'" sent the reader looking for two characters
// their source does not contain.
//
// The line below reads '- >' rather than '->' because nurlfmt made it
// so, and that is the whole point restated by the formatter: it sees a
// minus and a greater-than, spaces them as the two operators they are,
// and never considers them an arrow. Both spellings reach the check.
@ f i x - > i { ^ x }

@ main → i { ^ ( f 1 ) }
