# A2-handover — an owner's old value handed to the binding that reads it

## Status

**An encoding in A2's own rules, shown on two programs** (AGORA-885). No rule of the
calculus changes. An owner whose old value nurlc hands over is, in the
calculus, an **owner cell** plus a **borrow**, as in `DYN_DESIGN.md`. The
hand-over is a **take** of the old value into the cell (`TAKE_DESIGN.md`).
`A2/HandOver.lean` types the encoding with A2's own rules and applies the
crown theorems to it, on Lean's standard axioms only (`../check.sh`):

- `main_safe`, `main_no_leak`: the straight-line program below, run from
  the empty store, never gets stuck (`memory_safe`) and frees everything
  it allocated (`no_leak_end`);
- `mainJ_safe c`, `mainJ_no_leak c`: the same for `mainJ c`, with the
  hand-over decided at run time, for every value `c` of the condition:
  `o` reads `other` on the runs where `c ≠ 0`, as nurlc's buffer test
  decides.

The theorems are about these two programs. There is no general
translation of a program's hand-overs into the encoding, and no theorem
that one preserves typing. That translation, and the link from nurlc's
lowering to the encoded program (its drop flags and buffer test behaving
as the cell does), are phase C and D.

## What nurlc does

    : ~ String other ( mk )
    : ~ String o ( mk )
    = o other          // o's own value is freed; o reads other's value
    = other ( mk )     // other's old value goes to o, which owns it now
    ( read o )

At `= o other` nurlc releases `o`'s old value by its drop flag, then sets
the flag down. `o` now holds a copy of `other`'s handle, and is recorded
among `other`'s borrowers (`mem_udrop_link_alias`, `__borrowers`).

At `= other …`, `mem_udrop_hand_over` asks each live borrower, at run
time, whether its buffer is the old value's and `other` owns it (an
identity key compared with `icmp eq`, and `other`'s flag). Where both
hold, the borrower's flag goes up and `other`'s goes down. The old value
is then not freed by the `=`: the borrower owns it, and drops it at its
own end. Elsewhere the old value is freed as usual. The ownership engine
says the same thing statically (`eng_handover`: the first reader becomes
the owner, later readers borrow from it).

## The encoding

| nurlc | the encoding |
|---|---|
| `o`'s drop flag | "is `o`'s cell `some`?" (`oc : ?String`, an owner) |
| what `o` reads | the borrow `ob`, through which every read of `o` goes |
| `= o other`: `o`'s old value freed, flag down | `= oc none` (the cell drops what it held), `= ob ( borrow other )` |
| `= other …` where `o` holds the old buffer | `: q ( take other )  = oc ( some q )  = ob ( payload oc )`, then `= other …` |
| … where it does not | `= ob ( payload oc )` (`o`'s value is the cell's already), then `= other …` |
| the buffer test at run time | a flag `a`, set where `o` is given `other` |
| `o` dropped at its end | the cell drops its payload (`DropSlot`) |

`take` (`RhsT.take`) moves the `Vec` out of an owner and leaves a fresh
empty one in its place. It ends every borrow of the owner, `ob` among
them, as a replace does. `ob` is then pointed at the cell's payload. The
`=` that follows drops only the empty `Vec`, so the old value is freed
once, by the cell.

With the decision at run time (`mainJ`) the encoding has a join. After
`? c { = o other } {}`, `ob` may read `other` or the cell (`EobJ`, which
depends on both). The second `ite`, on `a`, ends with `ob` reading the
cell on both paths, so a later `= other …` ends nothing that `o` reads.
The path-insensitive typing needs no correlation between the two `ite`s:
the flag is a value, and each arm is typed on its own.

## What phase C / D has to show

nurlc's lowering of a hand-over has to simulate the encoding:

- a borrower's flag is up exactly when its cell would be `some`. The
  buffer test (`same && nonnull && other's flag`) is the flag `a` of
  `mainJ`;
- what the borrower reads is what `ob` reaches: `other`'s value before
  the hand-over, the cell's after it;
- the old value is freed once: by the `=` where no borrower took it, by
  the borrower's own end where one did.

`tools/fuzz/holes/` probes that link today. The by-name controls added with
AGORA-881 (`*_given_another_by_name_takes_its_old_value_*_runs_clean`)
run clean under ASan/LSan.

## What stays out

- **A field's reader** when the field is replaced (Agora #265, #354):
  the take would be of a field, and `RhsT.take` takes a whole binding.
- **The keep rule**, `= o ( f … o … )`, where a call may give the owner
  its own value back (#342, #375). That is an identity test on the
  owner itself, not a hand-over to a borrower.
- **A reader a call lent the old value to**, `= o ( id other )`. nurlc's
  `=` of a call's result links `o` to no owner, so `= other …` frees the
  old value whatever `o` holds. The walk and, since AGORA-881, the
  engine refuse a later read of `o`. A `:` binding of the call
  (`: o ( id other )`) is linked, and hands over as a by-name reader
  does. Its encoding is this one with the borrow made by the call.
- **A `Vec` whose elements hold views**, and **options and results**
  (nurlc hands over an option's payload to a cursor of it): `RhsT.take`
  is of a `Vec` whose elements hold no view (`TAKE_DESIGN.md`).
- **Several readers.** The first takes the old value. The rest borrow
  from it (`eng_handover`'s `ho` loan). That is one more borrow of the
  cell's payload in the encoding, and no witness types it yet.
