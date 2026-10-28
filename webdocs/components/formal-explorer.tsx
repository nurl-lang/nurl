'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Code2,
  ExternalLink,
  FileCode,
  GitBranch,
  Lock,
  Play,
  RotateCcw,
  Search,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
  ZoomIn,
  ZoomOut,
} from 'lucide-react';
import {
  formalData,
  type BlueprintNode,
  type FormalDecl,
  type FormalModuleFull,
  type FormalModuleSummary,
  type HoleProbe,
} from '@/lib/formal-data.generated';

type Lang = 'fi' | 'en';
type MainTab = 'visual' | 'blueprint' | 'browser' | 'holes';
type GraphMode = 'theorems' | 'modules-a2' | 'modules-a1';

const GITHUB_BASE = 'https://github.com/nurl-lang/nurl/blob/main';

const TABS: { id: MainTab; icon: typeof Sparkles; fi: string; en: string }[] = [
  { id: 'visual', icon: Sparkles, fi: '1. Visuaalinen selitys & Simulaattori', en: '1. Visual Story & Step Simulator' },
  { id: 'blueprint', icon: GitBranch, fi: '2. Matemaatikon Blueprint-verkko (DAG)', en: '2. Mathematician’s Blueprint Graph' },
  { id: 'browser', icon: Code2, fi: '3. Lean 4 -koodi & lauseselain (1 766)', en: '3. Lean 4 Proof & Code Browser (1,766)' },
  {
    id: 'holes',
    icon: ShieldAlert,
    fi: `4. ${formalData.stats.holesCount} Reikäkoetta & Sääntömatriisi`,
    en: `4. ${formalData.stats.holesCount} Soundness Holes & Rules`,
  },
];

interface SimBinding {
  name: string;
  mode: 'own' | 'bor' | 'slice' | 'pkg';
  ty: string;
  live: boolean;
  deps: string[];
  noteFi: string;
  noteEn: string;
}

interface SimSlot {
  varName: string;
  own: boolean;
  val: string | null;
  targetHeapIds: number[];
}

interface SimHeapBlock {
  id: number;
  kind: 'node' | 'buffer';
  label: string;
  allocated: boolean;
  owner: string;
}

interface SimStep {
  line: number;
  stmtLean: string;
  ruleName: string;
  status: 'ok' | 'rejected' | 'panic-unwind';
  titleFi: string;
  titleEn: string;
  descFi: string;
  descEn: string;
  ctx: SimBinding[];
  slots: SimSlot[];
  heap: SimHeapBlock[];
}

interface SimScenario {
  id: string;
  badge: string;
  titleFi: string;
  titleEn: string;
  subtitleFi: string;
  subtitleEn: string;
  nurlCode: string[];
  steps: SimStep[];
}

const SIM_SCENARIOS: SimScenario[] = [
  {
    id: 'realloc-view',
    badge: '§2.10 · Eff.realloc',
    titleFi: '1. Miksi vec_push mitätöi Slice-näkymän (mutta säilyttää alkiolainan)?',
    titleEn: '1. Why vec_push Kills a Slice View (While Preserving Element Borrows)',
    subtitleFi: 'Havainnollistaa sääntöä StmtT.push, efektihilaa Eff.kills .realloc ja reikäkokeita h07 / h33.',
    subtitleEn: 'Illustrates StmtT.push, the Eff.kills .realloc lattice rule, and soundness probes h07 / h33.',
    nurlCode: [
      ': ( Vec i ) v ( vec_new [i] )',
      '( vec_push [i] v 42 )',
      ': ( Slice i ) s ( slice_from_vec [i] v )',
      '( vec_push [i] v 99 )   // reallocates buffer d=1 → d=2!',
      ': i x ( slice_get [i] s 0 ) // COMPILE ERROR: s is dead',
    ],
    steps: [
      {
        line: 1,
        stmtLean: 'Stmt.letv v (Rhs.new .int) …',
        ruleName: 'RhsT.new',
        status: 'ok',
        titleFi: 'Vaihe 1: Luodaan omistettu Vec v',
        titleEn: 'Step 1: Allocate Owned Vec v',
        descFi:
          'Muuttuja v saa omistavan paikan Slot⟨own: true, some(node c=0 d=1 [])⟩. Kekoon varataan ohjaussolmu #0 ja datapuskuri #1.',
        descEn:
          'Binding v gets an owning slot Slot⟨own: true, some(node c=0 d=1 [])⟩. Heap node #0 and backing buffer #1 are allocated.',
        ctx: [
          {
            name: 'v',
            mode: 'own',
            ty: ' Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Ainoa omistaja puulle (#0, #1)',
            noteEn: 'Single owner of tree (#0, #1)',
          },
        ],
        slots: [{ varName: 'v', own: true, val: 'node(c=#0, d=#1, [42])', targetHeapIds: [0, 1] }],
        heap: [
          { id: 0, kind: 'node', label: 'Vec header c=#0', allocated: true, owner: 'v' },
          { id: 1, kind: 'buffer', label: 'Buffer d=#1 [42]', allocated: true, owner: 'v' },
        ],
      },
      {
        line: 3,
        stmtLean: 'Stmt.letv s (Rhs.view v) …',
        ruleName: 'RhsT.view',
        status: 'ok',
        titleFi: 'Vaihe 2: Otetaan Slice-näkymä s puskuriin d=#1',
        titleEn: 'Step 2: Take Slice View s into Buffer d=#1',
        descFi:
          's on lainattu näkymä Val.view(d=#1, off=0, len=1). Konteksti Γ kirjaa riippuvuuden Dep(root: v, kind: .view).',
        descEn:
          's holds Val.view(d=#1, off=0, len=1). Context Γ records dependency Dep(root: v, kind: .view).',
        ctx: [
          {
            name: 'v',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Omistaa solmun #0 ja puskurin #1',
            noteEn: 'Owns header #0 and buffer #1',
          },
          {
            name: 's',
            mode: 'slice',
            ty: 'Ty.slice .int',
            live: true,
            deps: ['v (.view)'],
            noteFi: 'Osoittaa suoraan puskuriin d=#1',
            noteEn: 'Points directly at buffer d=#1',
          },
        ],
        slots: [
          { varName: 'v', own: true, val: 'node(c=#0, d=#1, [42])', targetHeapIds: [0, 1] },
          { varName: 's', own: false, val: 'view(d=#1, off=0, len=1)', targetHeapIds: [1] },
        ],
        heap: [
          { id: 0, kind: 'node', label: 'Vec header c=#0', allocated: true, owner: 'v' },
          { id: 1, kind: 'buffer', label: 'Buffer d=#1 [42]', allocated: true, owner: 'v' },
        ],
      },
      {
        line: 4,
        stmtLean: 'Stmt.push v y  (runs kill Γ .realloc v)',
        ruleName: 'StmtT.push',
        status: 'ok',
        titleFi: 'Vaihe 3: vec_push kasvattaa puskuria (d=#1 vapautuu, d=#2 varataan)',
        titleEn: 'Step 3: vec_push Reallocates Buffer (d=#1 Freed, d=#2 Allocated)',
        descFi:
          'Ajonaikaisesti Step.push varaa uuden puskurin d=#2 ja vapauttaa vanhan puskurin d=#1 (alloc #1 := false). Käännösaikana StmtT.push ajaa kill Γ .realloc v: koska Eff.kills .realloc false .view = true, näkymä s merkitään kuolleeksi (live := false)!',
        descEn:
          'At runtime, Step.push allocates fresh buffer d=#2 and frees old buffer d=#1 (alloc #1 := false). At compile time, StmtT.push runs kill Γ .realloc v: since Eff.kills .realloc false .view = true, view s becomes dead (live := false)!',
        ctx: [
          {
            name: 'v',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Päivitetty puskuriin d=#2',
            noteEn: 'Updated to buffer d=#2',
          },
          {
            name: 's',
            mode: 'slice',
            ty: 'Ty.slice .int',
            live: false,
            deps: ['v (.view) — KILLED by .realloc'],
            noteFi: 'MITÄTÖITY (live = false): osoittaisi vapautettuun puskuriin #1!',
            noteEn: 'KILLED (live = false): points to freed buffer #1!',
          },
        ],
        slots: [
          { varName: 'v', own: true, val: 'node(c=#0, d=#2, [42, 99])', targetHeapIds: [0, 2] },
          { varName: 's', own: false, val: 'view(d=#1, off=0, len=1)', targetHeapIds: [1] },
        ],
        heap: [
          { id: 0, kind: 'node', label: 'Vec header c=#0', allocated: true, owner: 'v' },
          { id: 1, kind: 'buffer', label: 'FREED old buffer d=#1', allocated: false, owner: '—' },
          { id: 2, kind: 'buffer', label: 'NEW buffer d=#2 [42, 99]', allocated: true, owner: 'v' },
        ],
      },
      {
        line: 5,
        stmtLean: 'Rhs.sat s 0  (requires Γ(s).live = true)',
        ruleName: 'RhsT.sat',
        status: 'rejected',
        titleFi: 'Vaihe 4: Kääntäjä estää vanhentuneen näkymän s lukemisen!',
        titleEn: 'Step 4: Typechecker Rejects Reading Stale View s!',
        descFi:
          'Jos ajo jatkuisi, Step.letvSat vaatisi m.alloc(#1) = true, mutta #1 on vapautettu — suoritus joutuisi Stuck-tilaan (Use-After-Free). Koska RhsT.sat vaatii Γ(s).live = true, kääntäjä hylkää ohjelman käännösaikana!',
        descEn:
          'At runtime, reading s would require m.alloc(#1) = true, which is false (Stuck / Use-After-Free). Because RhsT.sat requires Γ(s).live = true, the typechecker rejects this program before it can ever run!',
        ctx: [
          {
            name: 'v',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Elossa',
            noteEn: 'Live',
          },
          {
            name: 's',
            mode: 'slice',
            ty: 'Ty.slice .int',
            live: false,
            deps: ['v (.view)'],
            noteFi: 'Estetty säännöllä RhsT.sat (vaatii live = true)',
            noteEn: 'Rejected by RhsT.sat (requires live = true)',
          },
        ],
        slots: [
          { varName: 'v', own: true, val: 'node(c=#0, d=#2, [42, 99])', targetHeapIds: [0, 2] },
          { varName: 's', own: false, val: 'view(d=#1, off=0, len=1)', targetHeapIds: [1] },
        ],
        heap: [
          { id: 0, kind: 'node', label: 'Vec header c=#0', allocated: true, owner: 'v' },
          { id: 1, kind: 'buffer', label: 'FREED old buffer d=#1', allocated: false, owner: '—' },
          { id: 2, kind: 'buffer', label: 'NEW buffer d=#2 [42, 99]', allocated: true, owner: 'v' },
        ],
      },
    ],
  },
  {
    id: 'move-dropflag',
    badge: '§2.1 & §7.6 · DropSlot',
    titleFi: '2. Siirto (Move) ja pudotusliput: miksi Double-Free on mahdoton?',
    titleEn: '2. Move Semantics & Drop Flags: Why Double-Free Is Impossible',
    subtitleFi: 'Näyttää kuinka RhsT.moveOwn, TakeVal.own ja DropSlot.moved estävät sekä Use-After-Move- että Double-Free-virheet.',
    subtitleEn: 'Shows how RhsT.moveOwn, TakeVal.own, and DropSlot.moved prevent both Use-After-Move and Double-Free.',
    nurlCode: [
      ': ( Vec i ) a ( vec_new [i] )',
      ': ( Vec i ) b a              // moves tree from a to b',
      '// end of scope: b drops tree (#0, #1); a has val=none (no-op)',
    ],
    steps: [
      {
        line: 1,
        stmtLean: 'Stmt.letv a (Rhs.new .int) …',
        ruleName: 'RhsT.new',
        status: 'ok',
        titleFi: 'Vaihe 1: a omistaa puun (#0, #1)',
        titleEn: 'Step 1: a Owns Tree (#0, #1)',
        descFi:
          'Muuttujan a paikka muistissa on Slot⟨own: true, val: some(T)⟩. HeapOK takaa, että mikään muu muuttuja ei omista osoitteita #0 ja #1.',
        descEn:
          'Slot a holds Slot⟨own: true, val: some(T)⟩. HeapOK guarantees no other binding owns addresses #0 and #1.',
        ctx: [
          {
            name: 'a',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Aktiivinen omistaja (live = true)',
            noteEn: 'Active owner (live = true)',
          },
        ],
        slots: [{ varName: 'a', own: true, val: 'some(node #0 #1)', targetHeapIds: [0, 1] }],
        heap: [
          { id: 0, kind: 'node', label: 'Vec header c=#0', allocated: true, owner: 'a' },
          { id: 1, kind: 'buffer', label: 'Buffer d=#1', allocated: true, owner: 'a' },
        ],
      },
      {
        line: 2,
        stmtLean: 'Stmt.letv b (Rhs.var a) …  (TakeVal.own)',
        ruleName: 'RhsT.moveOwn',
        status: 'ok',
        titleFi: 'Vaihe 2: Omistajuus siirtyy a → b (pudotuslippu nollataan)',
        titleEn: 'Step 2: Ownership Moves a → b (Drop Flag Cleared)',
        descFi:
          'Ajonaikaisesti TakeVal.own asettaa a:n paikaksi Slot⟨own: true, val: none⟩ (pudotuslippu tyhjä!) ja luo b:lle Slot⟨own: true, val: some(T)⟩. Käännösaikana kill Γ .replace a merkitsee a:n kuolleeksi.',
        descEn:
          'At runtime, TakeVal.own updates a to Slot⟨own: true, val: none⟩ (drop flag disarmed!) and binds b to Slot⟨own: true, val: some(T)⟩. In Γ, kill Γ .replace a marks a dead.',
        ctx: [
          {
            name: 'a',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: false,
            deps: [],
            noteFi: 'Siirretty (live = false) — ei voi lukea eikä vapauttaa uudelleen',
            noteEn: 'Moved (live = false) — cannot be read or manually freed',
          },
          {
            name: 'b',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Uusi ainoa omistaja puulle (#0, #1)',
            noteEn: 'New sole owner of tree (#0, #1)',
          },
        ],
        slots: [
          { varName: 'a', own: true, val: null, targetHeapIds: [] },
          { varName: 'b', own: true, val: 'some(node #0 #1)', targetHeapIds: [0, 1] },
        ],
        heap: [
          { id: 0, kind: 'node', label: 'Vec header c=#0', allocated: true, owner: 'b' },
          { id: 1, kind: 'buffer', label: 'Buffer d=#1', allocated: true, owner: 'b' },
        ],
      },
      {
        line: 3,
        stmtLean: 'Step.scopeSkip (DropSlot.owned b + DropSlot.moved a)',
        ruleName: 'DropSlot',
        status: 'ok',
        titleFi: 'Vaihe 3: Lohkon loppu — b vapauttaa puun, a ohitetaan (0 vuotoa!)',
        titleEn: 'Step 3: Scope Exit — b Frees Tree, a Is a Safe No-Op (0 Leaks!)',
        descFi:
          'Sisempi lohko b poistuu säännöllä DropSlot.owned ja vapauttaa osoitteet #0 ja #1. Ulompi lohko a poistuu säännöllä DropSlot.moved (koska val = none), joten vapautusta ei yritetä toista kertaa. Lopputilassa ∀ i, m.alloc i = false (no_leak_end).',
        descEn:
          'Inner scope b exits via DropSlot.owned, freeing #0 and #1. Outer scope a exits via DropSlot.moved (val = none), avoiding double-free. At program end, ∀ i, m.alloc i = false (no_leak_end).',
        ctx: [],
        slots: [],
        heap: [
          { id: 0, kind: 'node', label: 'FREED c=#0', allocated: false, owner: '—' },
          { id: 1, kind: 'buffer', label: 'FREED d=#1', allocated: false, owner: '—' },
        ],
      },
    ],
  },
  {
    id: 'panic-unwind',
    badge: '§7.2 · no_leak_panic',
    titleFi: '3. Paniikin purkaminen (Drop Journal): miksi paniikkikaan ei vuoda muistia?',
    titleEn: '3. Panic Unwinding (Drop Journal): Why Even Panics Never Leak Memory',
    subtitleFi: 'Näyttää kuinka panic_unwind ja A2.no_leak_panic purkavat ajonaikaiset kehykset (s.spine) ja vapauttavat jokaisen omistetun puun.',
    subtitleEn: 'Demonstrates how panic_unwind and A2.no_leak_panic unwind active scopes (s.spine) and free every owned tree.',
    nurlCode: [
      ': ( Vec i ) outer ( vec_new [i] )',
      ': ( Vec i ) inner ( vec_new [i] )',
      ': i bad ( vec_get [i] inner 99 ) // out-of-bounds → PANIC!',
      '// Unwinds inner scope, then outer scope → all heap nodes freed',
    ],
    steps: [
      {
        line: 2,
        stmtLean: 'Stmt.scope outer (Stmt.scope inner …)',
        ruleName: 'Covers',
        status: 'ok',
        titleFi: 'Vaihe 1: Kaksi aktiivista kehystä suoritusrangassa (s.spine = [outer, inner])',
        titleEn: 'Step 1: Two Active Scopes on the Spine (s.spine = [outer, inner])',
        descFi:
          'Sekä outer (#0, #1) että inner (#2, #3) ovat aktiivisia omistajia. Invariantti Covers takaa, että jokainen varattu osoite (#0..#3) kuuluu jollekin s.spine-listan omistajalle.',
        descEn:
          'Both outer (#0, #1) and inner (#2, #3) are active owners on s.spine. The Covers invariant guarantees every allocated address (#0..#3) belongs to an owner in s.spine.',
        ctx: [
          {
            name: 'outer',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Kehys 1 (omistaa #0, #1)',
            noteEn: 'Scope 1 (owns #0, #1)',
          },
          {
            name: 'inner',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Kehys 2 (omistaa #2, #3)',
            noteEn: 'Scope 2 (owns #2, #3)',
          },
        ],
        slots: [
          { varName: 'outer', own: true, val: 'some(node #0 #1)', targetHeapIds: [0, 1] },
          { varName: 'inner', own: true, val: 'some(node #2 #3)', targetHeapIds: [2, 3] },
        ],
        heap: [
          { id: 0, kind: 'node', label: 'outer c=#0', allocated: true, owner: 'outer' },
          { id: 1, kind: 'buffer', label: 'outer d=#1', allocated: true, owner: 'outer' },
          { id: 2, kind: 'node', label: 'inner c=#2', allocated: true, owner: 'inner' },
          { id: 3, kind: 'buffer', label: 'inner d=#3', allocated: true, owner: 'inner' },
        ],
      },
      {
        line: 3,
        stmtLean: 'Step.letvP (EvalRhsP.atOob : idx 99 ≥ len 0)',
        ruleName: 'panic_unwind',
        status: 'panic-unwind',
        titleFi: 'Vaihe 2: Indeksitarkistus epäonnistuu → hallittu paniikki (.panic m)',
        titleEn: 'Step 2: Bounds Check Fails → Controlled Panic (.panic m)',
        descFi:
          'Sen sijaan että ohjelma lukisi puskurin ulkopuolelta (Undefined Behavior), EvalRhsP.atOob käynnistää paniikkiaskeleen. Step.scopeP purkaa s.spine-kehykset sisimmästä ulompaan.',
        descEn:
          'Instead of reading out-of-bounds memory (UB), EvalRhsP.atOob steps to a panic result. Step.scopeP unwinds s.spine from innermost to outermost.',
        ctx: [
          {
            name: 'outer',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: true,
            deps: [],
            noteFi: 'Odottaa purkua drop-lokissa',
            noteEn: 'Queued in drop journal',
          },
          {
            name: 'inner',
            mode: 'own',
            ty: 'Ty.vec .int',
            live: false,
            deps: [],
            noteFi: 'Puretaan ensimmäisenä (Step.scopeP)',
            noteEn: 'Unwound first (Step.scopeP)',
          },
        ],
        slots: [{ varName: 'outer', own: true, val: 'some(node #0 #1)', targetHeapIds: [0, 1] }],
        heap: [
          { id: 0, kind: 'node', label: 'outer c=#0', allocated: true, owner: 'outer' },
          { id: 1, kind: 'buffer', label: 'outer d=#1', allocated: true, owner: 'outer' },
          { id: 2, kind: 'node', label: 'FREED inner c=#2', allocated: false, owner: '—' },
          { id: 3, kind: 'buffer', label: 'FREED inner d=#3', allocated: false, owner: '—' },
        ],
      },
      {
        line: 4,
        stmtLean: 'A2.no_leak_panic : ∀ i, m\'.alloc i = false',
        ruleName: 'no_leak_panic',
        status: 'ok',
        titleFi: 'Vaihe 3: Koko pino purettu — jokainen kekovaraus on vapautettu!',
        titleEn: 'Step 3: Spine Fully Unwound — Every Heap Allocation Is Freed!',
        descFi:
          'Lause panic_unwind todistaa, että jokainen s.spine-muuttuja poistetaan DropSlot-säännöllä ja Covers säilyy. Koska lopussa yhtään muuttujaa ei ole jäljellä (∀ v, m\'.st v = none), lause A2.no_leak_panic todistaa ∀ i, m\'.alloc i = false!',
        descEn:
          'Theorem panic_unwind proves every variable in s.spine is dropped via DropSlot while preserving Covers. With no bindings left (∀ v, m\'.st v = none), A2.no_leak_panic proves ∀ i, m\'.alloc i = false!',
        ctx: [],
        slots: [],
        heap: [
          { id: 0, kind: 'node', label: 'FREED outer c=#0', allocated: false, owner: '—' },
          { id: 1, kind: 'buffer', label: 'FREED outer d=#1', allocated: false, owner: '—' },
          { id: 2, kind: 'node', label: 'FREED inner c=#2', allocated: false, owner: '—' },
          { id: 3, kind: 'buffer', label: 'FREED inner d=#3', allocated: false, owner: '—' },
        ],
      },
    ],
  },
];

const EFF_ROWS = [
  {
    eff: 'none',
    rank: 0,
    opFi: 'Vain luku (vec_len, slice_len, in-parametri)',
    opEn: 'Read-only (vec_len, slice_len, in parameter)',
    nurlEx: '( vec_len [i] v )',
    killsView: false,
    killsInner: false,
    killsSelfNoView: false,
    killsSelfWithView: false,
    killsName: false,
  },
  {
    eff: 'realloc',
    rank: 1,
    opFi: 'Puskurin kasvatus (vec_push / string_push_str)',
    opEn: 'Buffer growth / reallocation (vec_push / string_push_str)',
    nurlEx: '( vec_push [i] v x )',
    killsView: true,
    killsInner: false,
    killsSelfNoView: false,
    killsSelfWithView: true,
    killsName: false,
  },
  {
    eff: 'drop',
    rank: 2,
    opFi: 'Alkion poisto (vec_pop)',
    opEn: 'Element removal / drop (vec_pop)',
    nurlEx: ': i last ( vec_pop [i] v )',
    killsView: true,
    killsInner: true,
    killsSelfNoView: false,
    killsSelfWithView: true,
    killsName: false,
  },
  {
    eff: 'replace',
    rank: 3,
    opFi: 'Siirto (move), sijoitus (=), vec_free tai lohkon loppu',
    opEn: 'Move, reassignment (=), vec_free, or scope exit',
    nurlEx: '( vec_free [i] v )  tai  = v other',
    killsView: true,
    killsInner: true,
    killsSelfNoView: true,
    killsSelfWithView: true,
    killsName: false,
  },
] as const;

const LAYER_COLORS: Record<number, { bg: string; border: string; text: string; badge: string }> = {
  0: {
    bg: 'bg-sky-500/10',
    border: 'border-sky-500/40',
    text: 'text-sky-600 dark:text-sky-400',
    badge: 'bg-sky-500/15 text-sky-700 dark:text-sky-300',
  },
  1: {
    bg: 'bg-indigo-500/10',
    border: 'border-indigo-500/40',
    text: 'text-indigo-600 dark:text-indigo-400',
    badge: 'bg-indigo-500/15 text-indigo-700 dark:text-indigo-300',
  },
  2: {
    bg: 'bg-violet-500/10',
    border: 'border-violet-500/40',
    text: 'text-violet-600 dark:text-violet-400',
    badge: 'bg-violet-500/15 text-violet-700 dark:text-violet-300',
  },
  3: {
    bg: 'bg-amber-500/10',
    border: 'border-amber-500/40',
    text: 'text-amber-600 dark:text-amber-400',
    badge: 'bg-amber-500/15 text-amber-700 dark:text-amber-300',
  },
  4: {
    bg: 'bg-rose-500/10',
    border: 'border-rose-500/40',
    text: 'text-rose-600 dark:text-rose-400',
    badge: 'bg-rose-500/15 text-rose-700 dark:text-rose-300',
  },
  5: {
    bg: 'bg-emerald-500/10',
    border: 'border-emerald-500/50',
    text: 'text-emerald-600 dark:text-emerald-400',
    badge: 'bg-emerald-500/20 text-emerald-700 dark:text-emerald-300',
  },
};

export function FormalExplorer() {
  const [lang, setLang] = useState<Lang>('fi');
  const t = (fi: string, en: string) => (lang === 'fi' ? fi : en);
  const [activeTab, setActiveTab] = useState<MainTab>('visual');

  // Simulator state
  const [scenarioIdx, setScenarioIdx] = useState(0);
  const [stepIdx, setStepIdx] = useState(0);
  const [selectedEffIdx, setSelectedEffIdx] = useState(1); // default realloc
  const [holdsView, setHoldsView] = useState(false);

  // Blueprint Graph state
  const [graphMode, setGraphMode] = useState<GraphMode>('theorems');
  const [selectedBpNodeId, setSelectedBpNodeId] = useState<string>('memory_safe');
  const [selectedModName, setSelectedModName] = useState<string>('Soundness');
  const [zoom, setZoom] = useState<number>(1);

  // Full declarations state (loaded from /formal-decls.json)
  const [fullData, setFullData] = useState<{ A2: FormalModuleFull[]; A1: FormalModuleFull[] } | null>(null);
  const [loadingDecls, setLoadingDecls] = useState(false);

  // Code browser state
  const [browserPhase, setBrowserPhase] = useState<'A2' | 'A1'>('A2');
  const [browserModule, setBrowserModule] = useState<string>('Soundness');
  const [browserKind, setBrowserKind] = useState<string>('all');
  const [browserSearch, setBrowserSearch] = useState<string>('');
  const [selectedDeclName, setSelectedDeclName] = useState<string>('memory_safe');

  // Holes explorer state
  const [holesSubTab, setHolesSubTab] = useState<'probes' | 'rules'>('probes');
  const [holePhaseFilter, setHolePhaseFilter] = useState<string>('all');
  const [holeSearch, setHoleSearch] = useState<string>('');
  const [selectedHole, setSelectedHole] = useState<HoleProbe>(formalData.holes[4]); // h07_stale_view_after_push

  // Load full declarations JSON when needed
  useEffect(() => {
    if (fullData || loadingDecls) return;
    setLoadingDecls(true);
    fetch('/formal-decls.json')
      .then((r) => r.json())
      .then((data) => {
        setFullData(data);
        setLoadingDecls(false);
      })
      .catch(() => {
        setLoadingDecls(false);
      });
  }, [fullData, loadingDecls]);

  const currentScenario = SIM_SCENARIOS[scenarioIdx];
  const currentStep = currentScenario.steps[Math.min(stepIdx, currentScenario.steps.length - 1)];

  // Lookup helper for declarations
  const declLookup = useMemo(() => {
    const map = new Map<string, FormalDecl>();
    for (const [k, v] of Object.entries(formalData.initialDecls)) {
      map.set(k, v);
    }
    if (fullData) {
      for (const mod of fullData[browserPhase]) {
        for (const d of mod.decls) {
          map.set(d.name, d);
        }
      }
    }
    return map;
  }, [fullData, browserPhase]);

  function openDeclInBrowser(name: string, phase: 'A2' | 'A1' = 'A2') {
    const clean = name.replace(/^A[12]\./, '').split('.')[0];
    setBrowserPhase(phase);
    const d = declLookup.get(name) ?? declLookup.get(clean);
    if (d) {
      setBrowserModule(d.module);
      setSelectedDeclName(d.name);
      setBrowserSearch('');
      setBrowserKind('all');
    } else {
      setBrowserModule('all');
      setBrowserSearch(clean);
    }
    setActiveTab('browser');
  }

  // Blueprint Graph layout calculation
  const blueprintLayout = useMemo(() => {
    const nodes = formalData.blueprintNodes;
    const tiers: BlueprintNode[][] = [[], [], [], [], [], []];
    for (const n of nodes) {
      tiers[n.tier]?.push(n);
    }
    const width = 940;
    const height = 560;
    const pos = new Map<string, { x: number; y: number; node: BlueprintNode }>();
    tiers.forEach((tierNodes, tIdx) => {
      // Top-down or bottom-up: place Tier 0 at top, Tier 5 (Main Theorems) at bottom
      const y = 52 + tIdx * 90;
      const count = tierNodes.length;
      tierNodes.forEach((n, i) => {
        const x = ((i + 1) * width) / (count + 1);
        pos.set(n.id, { x, y, node: n });
      });
    });
    const edges: Array<{ from: string; to: string; x1: number; y1: number; x2: number; y2: number }> = [];
    for (const n of nodes) {
      const target = pos.get(n.id);
      if (!target) continue;
      for (const depId of n.deps) {
        const src = pos.get(depId);
        if (src) {
          edges.push({
            from: depId,
            to: n.id,
            x1: src.x,
            y1: src.y + 22,
            x2: target.x,
            y2: target.y - 22,
          });
        }
      }
    }
    return { width, height, pos, edges };
  }, []);

  // Module DAG layout calculation
  const moduleLayout = useMemo(() => {
    const phaseKey: 'A1' | 'A2' = graphMode === 'modules-a1' ? 'A1' : 'A2';
    const mods = formalData.modules[phaseKey];
    const layers: FormalModuleSummary[][] = [[], [], [], [], [], []];
    for (const m of mods) {
      layers[m.layer]?.push(m);
    }
    const width = 980;
    const height = 610;
    const pos = new Map<string, { x: number; y: number; mod: FormalModuleSummary }>();
    layers.forEach((layerMods, lIdx) => {
      const y = 50 + lIdx * 98;
      const count = layerMods.length;
      layerMods.forEach((m, i) => {
        const x = ((i + 1) * width) / (count + 1);
        pos.set(m.name, { x, y, mod: m });
      });
    });
    const edges: Array<{ from: string; to: string; x1: number; y1: number; x2: number; y2: number }> = [];
    for (const m of mods) {
      const target = pos.get(m.name);
      if (!target) continue;
      for (const imp of m.imports) {
        const src = pos.get(imp);
        if (src) {
          edges.push({
            from: imp,
            to: m.name,
            x1: src.x,
            y1: src.y + 20,
            x2: target.x,
            y2: target.y - 20,
          });
        }
      }
    }
    return { width, height, pos, edges, mods, phaseKey };
  }, [graphMode]);

  // Filtered declarations for Code Browser
  const filteredDecls = useMemo(() => {
    const mods = fullData ? fullData[browserPhase] : [];
    if (mods.length === 0) {
      return Object.values(formalData.initialDecls);
    }
    const q = browserSearch.trim().toLowerCase();
    const list: FormalDecl[] = [];
    for (const m of mods) {
      if (browserModule !== 'all' && m.name !== browserModule) continue;
      for (const d of m.decls) {
        if (browserKind !== 'all') {
          if (browserKind === 'def' && d.kind !== 'def' && d.kind !== 'abbrev') continue;
          if (browserKind !== 'def' && d.kind !== browserKind) continue;
        }
        if (
          q &&
          !d.name.toLowerCase().includes(q) &&
          !d.doc.toLowerCase().includes(q) &&
          !d.signature.toLowerCase().includes(q)
        ) {
          continue;
        }
        list.push(d);
      }
    }
    return list;
  }, [fullData, browserPhase, browserModule, browserKind, browserSearch]);

  const activeDecl = useMemo(() => {
    return (
      filteredDecls.find((d) => d.name === selectedDeclName) ??
      declLookup.get(selectedDeclName) ??
      filteredDecls[0] ??
      formalData.initialDecls.memory_safe
    );
  }, [filteredDecls, selectedDeclName, declLookup]);

  // Filtered holes
  const filteredHoles = useMemo(() => {
    const q = holeSearch.trim().toLowerCase();
    return formalData.holes.filter((h) => {
      if (holePhaseFilter !== 'all' && h.phase !== holePhaseFilter) return false;
      if (
        q &&
        !h.probe.toLowerCase().includes(q) &&
        !h.rule.toLowerCase().includes(q) &&
        !h.note.toLowerCase().includes(q) &&
        !h.code.toLowerCase().includes(q)
      ) {
        return false;
      }
      return true;
    });
  }, [holePhaseFilter, holeSearch]);

  const selectedBpNode =
    formalData.blueprintNodes.find((n) => n.id === selectedBpNodeId) ??
    formalData.blueprintNodes[formalData.blueprintNodes.length - 3];

  const selectedBpDecl = declLookup.get(selectedBpNode.name);

  return (
    <div className="my-6 flex flex-col gap-6 text-sm">
      {/* Top Hero Banner with Stats & Language Switcher */}
      <div className="rounded-xl border bg-gradient-to-br from-fd-card via-fd-card to-emerald-500/5 p-5 shadow-sm">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="max-w-3xl">
            <div className="inline-flex items-center gap-2 rounded-full border border-emerald-500/30 bg-emerald-500/10 px-3 py-1 text-xs font-semibold text-emerald-700 dark:text-emerald-300">
              <ShieldCheck className="h-3.5 w-3.5" />
              <span>
                {t('Lean 4 -koneistettu todistus · A1 & A2 todistettu (0 sorrya)', 'Lean 4 Mechanized Proof · Phases A1 & A2 Proven (0 sorrys)')}
              </span>
            </div>
            <h2 className="mt-2.5 text-xl font-bold tracking-tight text-fd-foreground sm:text-2xl">
              {t('NURLin muistimallin visuaalinen ja interaktiivinen todistusselain', 'Interactive Visual Explorer of NURL’s Mechanized Memory Proof')}
            </h2>
            <p className="mt-1.5 text-sm text-fd-muted-foreground">
              {t('Tutki sekä visuaalisesti ("tavalliselle ihmiselle") että matemaattisen tarkasti (Lean Blueprint -riippuvuusverkko ja kaikki 1 766 Lean 4 -määritelmää), miten NURL todistaa muistiturvallisuuden (A2.memory_safe) ja vuodottomuuden (A2.no_leak_end, A2.no_leak_panic).', 'Explore both visually (step-by-step memory & borrow simulator) and mathematically (Lean Blueprint dependency DAG + 1,766 Lean 4 declarations) how NURL proves memory safety (A2.memory_safe) and leak freedom (A2.no_leak_end, A2.no_leak_panic).')}
            </p>
          </div>

          {/* Language Switcher */}
          <div className="flex items-center gap-1 rounded-lg border bg-fd-muted/60 p-1">
            <button
              type="button"
              onClick={() => setLang('fi')}
              className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
                lang === 'fi'
                  ? 'bg-fd-background text-fd-foreground shadow-sm'
                  : 'text-fd-muted-foreground hover:text-fd-foreground'
              }`}
            >
              🇫🇮 Suomi
            </button>
            <button
              type="button"
              onClick={() => setLang('en')}
              className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
                lang === 'en'
                  ? 'bg-fd-background text-fd-foreground shadow-sm'
                  : 'text-fd-muted-foreground hover:text-fd-foreground'
              }`}
            >
              🇬🇧 English
            </button>
          </div>
        </div>

        {/* Key metrics strip */}
        <div className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-5">
          <div className="rounded-lg border bg-fd-background/70 px-3.5 py-2.5">
            <div className="text-lg font-bold text-fd-foreground">
              {(formalData.stats.a1.lines + formalData.stats.a2.lines).toLocaleString('en-US')}
            </div>
            <div className="text-xs text-fd-muted-foreground">
              {t('riviä Lean 4 -todistusta', 'lines of Lean 4 proof')}
            </div>
          </div>
          <div className="rounded-lg border bg-fd-background/70 px-3.5 py-2.5">
            <div className="text-lg font-bold text-emerald-600 dark:text-emerald-400">
              {(formalData.stats.a1.theorems + formalData.stats.a2.theorems).toLocaleString('en-US')}
            </div>
            <div className="text-xs text-fd-muted-foreground">
              {t('todistettua lausetta (0 sorry)', 'proven theorems (0 sorry)')}
            </div>
          </div>
          <div className="rounded-lg border bg-fd-background/70 px-3.5 py-2.5">
            <div className="text-lg font-bold text-fd-foreground">
              {formalData.stats.a1.modules + formalData.stats.a2.modules}
            </div>
            <div className="text-xs text-fd-muted-foreground">
              {t('Lean-moduulia (A1 + A2)', 'Lean modules (A1 + A2)')}
            </div>
          </div>
          <div className="rounded-lg border bg-fd-background/70 px-3.5 py-2.5">
            <div className="text-lg font-bold text-amber-600 dark:text-amber-400">{formalData.stats.holesCount}</div>
            <div className="text-xs text-fd-muted-foreground">
              {t('reikäkoetta', 'soundness hole probes')}
            </div>
          </div>
          <div className="col-span-2 rounded-lg border bg-fd-background/70 px-3.5 py-2.5 sm:col-span-1">
            <div className="font-mono text-sm font-bold text-fd-foreground">v4.35.0</div>
            <div className="text-xs text-fd-muted-foreground">
              {t('Vain standardiaksioomat', 'Standard axioms only')}
            </div>
          </div>
        </div>

        {/* Navigation Tabs */}
        <div className="mt-5 flex flex-wrap gap-2 border-t pt-4">
          {TABS.map(({ id, icon: Icon, fi, en }) => (
            <button
              key={id}
              type="button"
              onClick={() => setActiveTab(id)}
              className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-semibold transition-all ${
                activeTab === id
                  ? 'bg-fd-primary text-fd-primary-foreground shadow-sm'
                  : 'border bg-fd-background text-fd-muted-foreground hover:text-fd-foreground'
              }`}
            >
              <Icon className="h-4 w-4" />
              <span>{t(fi, en)}</span>
            </button>
          ))}
        </div>
      </div>

      {/* =====================================================================
          TAB 1: VISUAL EXPLANATION & INTERACTIVE SIMULATOR (FOR EVERYONE)
         ===================================================================== */}
      {activeTab === 'visual' && (
        <div className="flex flex-col gap-6">
          {/* Section 1A: Plain-Language Visual Overview of What Lean Proves */}
          <div className="rounded-xl border bg-fd-card p-5">
            <h3 className="text-base font-bold text-fd-foreground">
              {t('Mitä Lean 4 -todistus oikeasti todistaa? (Kansantajuinen kokonaiskuva)', 'What Does the Lean 4 Proof Actually Prove? (Plain-Language Picture)')}
            </h3>
            <p className="mt-1.5 text-sm text-fd-muted-foreground">
              {t('Ohjelmointikielissä, joissa ei ole roskienkerääjää (GC), on viisi klassista tapaa rikkoa muisti: (1) luku vapautuksen jälkeen (Use-After-Free), (2) saman muistin vapautus kahdesti (Double-Free), (3) luku vanhentuneen näkymän läpi kun puskuri kasvaa (Iterator/View Invalidation), (4) jaetun arvon muokkaus lainan aikana, ja (5) muistivuoto (Memory Leak) normaalin poistumisen tai paniikin yhteydessä. Lean-todistus rakentaa matemaattisen koneen, jossa jokainen näistä virheistä pysäyttäisi koneen Stuck-tilaan — ja todistaa sitten, ettei yksikään tyyppitarkistuksen läpäissyt ohjelma voi koskaan päätyä Stuck-tilaan tai jättää muistia vapauttamatta.', 'In languages without a garbage collector, there are five classic memory bugs: (1) Use-After-Free, (2) Double-Free, (3) Dangling View / Iterator Invalidation when a buffer grows, (4) Aliased Mutation while borrowed, and (5) Memory Leaks on exit or panic. The Lean proof defines a formal machine where any such bug makes the machine Stuck — and then proves that no well-typed program can ever get Stuck or leave memory allocated.')}
            </p>

            {/* 3 Crown Guarantees */}
            <div className="mt-4 grid gap-4 md:grid-cols-3">
              <div className="flex flex-col justify-between rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-4">
                <div>
                  <div className="flex items-center justify-between">
                    <span className="rounded bg-emerald-500/20 px-2 py-0.5 font-mono text-xs font-bold text-emerald-700 dark:text-emerald-300">
                      A2.memory_safe
                    </span>
                    <ShieldCheck className="h-4 w-4 text-emerald-600 dark:text-emerald-400" />
                  </div>
                  <h4 className="mt-2 font-semibold text-fd-foreground">
                    {t('1. Ei koskaan muistivirhettä (¬ Stuck)', '1. Zero Memory Errors (¬ Stuck)')}
                  </h4>
                  <p className="mt-1 text-xs leading-relaxed text-fd-muted-foreground">
                    {t('Jokainen muistiluku tarkistaa, että keko-osoite on varattu (m.alloc c = true) ja indeksit ovat rajoissa. Jos ohjelma yrittäisi lukea vapautettua muistia tai vanhentunutta Slice-näkymää, sääntöä ei ole (Stuck). Lause todistaa, että jokainen saavutettava tila on joko valmis (.skip), panikoi turvallisesti tai ottaa laillisen askeleen.', 'Every memory access requires the heap address to be live (m.alloc c = true). Any Use-After-Free, Double-Free, or dangling view access has no step rule (Stuck). The theorem proves no reachable configuration is ever Stuck.')}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => openDeclInBrowser('memory_safe', 'A2')}
                  className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-emerald-700 hover:underline dark:text-emerald-300"
                >
                  <span>{t('Avaa lause A2.memory_safe →', 'Inspect A2.memory_safe →')}</span>
                </button>
              </div>

              <div className="flex flex-col justify-between rounded-xl border border-sky-500/30 bg-sky-500/5 p-4">
                <div>
                  <div className="flex items-center justify-between">
                    <span className="rounded bg-sky-500/20 px-2 py-0.5 font-mono text-xs font-bold text-sky-700 dark:text-sky-300">
                      A2.no_leak_end
                    </span>
                    <CheckCircle2 className="h-4 w-4 text-sky-600 dark:text-sky-400" />
                  </div>
                  <h4 className="mt-2 font-semibold text-fd-foreground">
                    {t('2. Ei muistivuotoja valmistuessa', '2. Zero Leaks on Normal Exit')}
                  </h4>
                  <p className="mt-1 text-xs leading-relaxed text-fd-muted-foreground">
                    {t('Invariantti Covers m takaa jokaisella askeleella, että jokainen varattu osoite (m.alloc i = true) kuuluu täsmälleen yhdelle aktiivisen lohkon omistajalle. Kun ohjelma päättyy (.ok m\' .skip), kaikki lohkot ovat poistuneet, joten ∀ i, m\'.alloc i = false.', 'The Covers m invariant guarantees at every step that every live heap address belongs to an active owner on the scope spine. When the program reaches .skip, all scopes have exited, forcing ∀ i, m\'.alloc i = false.')}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => openDeclInBrowser('no_leak_end', 'A2')}
                  className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-sky-700 hover:underline dark:text-sky-300"
                >
                  <span>{t('Avaa lause A2.no_leak_end →', 'Inspect A2.no_leak_end →')}</span>
                </button>
              </div>

              <div className="flex flex-col justify-between rounded-xl border border-amber-500/30 bg-amber-500/5 p-4">
                <div>
                  <div className="flex items-center justify-between">
                    <span className="rounded bg-amber-500/20 px-2 py-0.5 font-mono text-xs font-bold text-amber-700 dark:text-amber-300">
                      A2.no_leak_panic
                    </span>
                    <Lock className="h-4 w-4 text-amber-600 dark:text-amber-400" />
                  </div>
                  <h4 className="mt-2 font-semibold text-fd-foreground">
                    {t('3. Ei muistivuotoja edes paniikissa', '3. Zero Leaks on Uncaught Panic')}
                  </h4>
                  <p className="mt-1 text-xs leading-relaxed text-fd-muted-foreground">
                    {t('Kun rajatarkistus tai panic laukeaa, ajonaikainen pino purkautuu (panic_unwind) sisimmästä kehyksestä ulompaan (drop journal). Jokainen poistuva kehys vapauttaa omistamansa puut (DropSlot), joten lopputilassa ∀ i, m\'.alloc i = false.', 'When a bounds check or explicit panic fires, panic_unwind walks the active scope spine from innermost to outermost (the drop journal), freeing every owned tree via DropSlot so that ∀ i, m\'.alloc i = false.')}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => openDeclInBrowser('no_leak_panic', 'A2')}
                  className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-amber-700 hover:underline dark:text-amber-300"
                >
                  <span>{t('Avaa lause A2.no_leak_panic →', 'Inspect A2.no_leak_panic →')}</span>
                </button>
              </div>
            </div>
          </div>

          {/* Section 1B: Interactive Step-by-Step Memory & Borrow-Checker Simulator */}
          <div className="rounded-xl border bg-fd-card p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="flex items-center gap-2 text-base font-bold text-fd-foreground">
                  <Play className="h-4 w-4 text-fd-primary" />
                  <span>
                    {t('Interaktiivinen muisti- ja lainantarkistussimulaattori', 'Interactive Memory & Borrow-Checker Step Simulator')}
                  </span>
                </h3>
                <p className="mt-0.5 text-xs text-fd-muted-foreground">
                  {t('Valitse skenaario ja astu eteenpäin nähdäksesi rinnakkain käännösaikaisen kontekstin Γ (Typing.lean) ja ajonaikaisen muistin Mem (Semantics.lean).', 'Pick a scenario and step through to watch compile-time context Γ (Typing.lean) and runtime store Mem (Semantics.lean) side by side.')}
                </p>
              </div>

              {/* Scenario selector buttons */}
              <div className="flex flex-wrap gap-1.5">
                {SIM_SCENARIOS.map((sc, idx) => (
                  <button
                    key={sc.id}
                    type="button"
                    onClick={() => {
                      setScenarioIdx(idx);
                      setStepIdx(0);
                    }}
                    className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${
                      scenarioIdx === idx
                        ? 'bg-fd-primary text-fd-primary-foreground'
                        : 'border bg-fd-background text-fd-muted-foreground hover:text-fd-foreground'
                    }`}
                  >
                    {sc.badge}
                  </button>
                ))}
              </div>
            </div>

            {/* Scenario Header & Step Controls */}
            <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-fd-muted/40 p-3.5">
              <div>
                <div className="font-semibold text-fd-foreground">
                  {lang === 'fi' ? currentScenario.titleFi : currentScenario.titleEn}
                </div>
                <div className="text-xs text-fd-muted-foreground">
                  {lang === 'fi' ? currentScenario.subtitleFi : currentScenario.subtitleEn}
                </div>
              </div>

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setStepIdx(0)}
                  disabled={stepIdx === 0}
                  className="inline-flex items-center gap-1 rounded-md border bg-fd-background px-2.5 py-1.5 text-xs font-medium disabled:opacity-40"
                  title="Reset"
                >
                  <RotateCcw className="h-3.5 w-3.5" />
                </button>
                <button
                  type="button"
                  onClick={() => setStepIdx((s) => Math.max(0, s - 1))}
                  disabled={stepIdx === 0}
                  className="inline-flex items-center gap-1 rounded-md border bg-fd-background px-3 py-1.5 text-xs font-medium disabled:opacity-40"
                >
                  <ChevronLeft className="h-3.5 w-3.5" />
                  <span>{t('Edellinen', 'Prev')}</span>
                </button>
                <span className="px-2 font-mono text-xs font-semibold">
                  {stepIdx + 1} / {currentScenario.steps.length}
                </span>
                <button
                  type="button"
                  onClick={() => setStepIdx((s) => Math.min(currentScenario.steps.length - 1, s + 1))}
                  disabled={stepIdx >= currentScenario.steps.length - 1}
                  className="inline-flex items-center gap-1 rounded-md bg-fd-primary px-3 py-1.5 text-xs font-medium text-fd-primary-foreground disabled:opacity-40"
                >
                  <span>{t('Seuraava askel', 'Next Step')}</span>
                  <ChevronRight className="h-3.5 w-3.5" />
                </button>
              </div>
            </div>

            {/* Active Step Banner */}
            <div
              className={`mt-4 rounded-lg border p-4 ${
                currentStep.status === 'rejected'
                  ? 'border-rose-500/50 bg-rose-500/10'
                  : currentStep.status === 'panic-unwind'
                    ? 'border-amber-500/50 bg-amber-500/10'
                    : 'border-emerald-500/40 bg-emerald-500/5'
              }`}
            >
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span
                    className={`rounded px-2 py-0.5 font-mono text-xs font-bold ${
                      currentStep.status === 'rejected'
                        ? 'bg-rose-500/20 text-rose-700 dark:text-rose-300'
                        : currentStep.status === 'panic-unwind'
                          ? 'bg-amber-500/20 text-amber-700 dark:text-amber-300'
                          : 'bg-emerald-500/20 text-emerald-700 dark:text-emerald-300'
                    }`}
                  >
                    {currentStep.stmtLean}
                  </span>
                  <span className="font-semibold text-fd-foreground">
                    {lang === 'fi' ? currentStep.titleFi : currentStep.titleEn}
                  </span>
                </div>

                <button
                  type="button"
                  onClick={() => openDeclInBrowser(currentStep.ruleName, 'A2')}
                  className="inline-flex items-center gap-1.5 rounded-md border bg-fd-background px-2.5 py-1 font-mono text-xs font-semibold text-fd-primary hover:underline"
                >
                  <span>Lean: {currentStep.ruleName}</span>
                  <ExternalLink className="h-3 w-3" />
                </button>
              </div>
              <p className="mt-2 text-xs leading-relaxed text-fd-foreground/90">
                {lang === 'fi' ? currentStep.descFi : currentStep.descEn}
              </p>
            </div>

            {/* 3-Column Visual State: NURL Code | Compile-time Context Γ | Runtime Store Mem */}
            <div className="mt-4 grid gap-4 lg:grid-cols-3">
              {/* Column 1: NURL Source Code */}
              <div className="rounded-lg border bg-fd-background p-3.5">
                <div className="mb-2 flex items-center justify-between border-b pb-2">
                  <span className="text-xs font-bold uppercase tracking-wider text-fd-muted-foreground">
                    1. NURL Source Code
                  </span>
                  <span className="font-mono text-[11px] text-fd-muted-foreground">line {currentStep.line}</span>
                </div>
                <pre className="overflow-x-auto font-mono text-xs leading-6">
                  {currentScenario.nurlCode.map((line, idx) => {
                    const lineNo = idx + 1;
                    const active = lineNo === currentStep.line;
                    return (
                      <div
                        key={lineNo}
                        className={`rounded px-2 ${
                          active
                            ? currentStep.status === 'rejected'
                              ? 'bg-rose-500/20 font-semibold text-rose-700 dark:text-rose-300'
                              : 'bg-fd-primary/15 font-semibold text-fd-foreground'
                            : 'text-fd-muted-foreground'
                        }`}
                      >
                        <span className="mr-2 select-none opacity-50">{lineNo}</span>
                        {line}
                      </div>
                    );
                  })}
                </pre>
              </div>

              {/* Column 2: Compile-Time Context Γ (Typing.lean) */}
              <div className="rounded-lg border bg-fd-background p-3.5">
                <div className="mb-2 flex items-center justify-between border-b pb-2">
                  <span className="text-xs font-bold uppercase tracking-wider text-fd-muted-foreground">
                    {t('2. Käännösaikainen konteksti Γ', '2. Compile-Time Context Γ')}
                  </span>
                  <span className="font-mono text-[11px] text-indigo-600 dark:text-indigo-400">A2/Typing.lean</span>
                </div>
                {currentStep.ctx.length === 0 ? (
                  <div className="py-6 text-center text-xs text-fd-muted-foreground">
                    {t('Konteksti Γ on tyhjä (kaikki lohkot ovat päättyneet).', 'Context Γ is empty (all scopes have exited).')}
                  </div>
                ) : (
                  <div className="flex flex-col gap-2.5">
                    {currentStep.ctx.map((b) => (
                      <div
                        key={b.name}
                        className={`rounded-lg border p-2.5 ${
                          b.live
                            ? 'border-emerald-500/30 bg-emerald-500/5'
                            : 'border-rose-500/40 bg-rose-500/10 opacity-90'
                        }`}
                      >
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2">
                            <span className="font-mono text-xs font-bold text-fd-foreground">{b.name}</span>
                            <span className="rounded bg-fd-muted px-1.5 py-0.5 font-mono text-[11px]">
                              mode: .{b.mode}
                            </span>
                            <span className="font-mono text-[11px] text-fd-muted-foreground">{b.ty}</span>
                          </div>
                          <span
                            className={`rounded px-1.5 py-0.5 font-mono text-[10px] font-bold ${
                              b.live
                                ? 'bg-emerald-500/20 text-emerald-700 dark:text-emerald-300'
                                : 'bg-rose-500/20 text-rose-700 dark:text-rose-300'
                            }`}
                          >
                            {b.live ? 'live = true' : 'live = false'}
                          </span>
                        </div>
                        {b.deps.length > 0 && (
                          <div className="mt-1.5 flex flex-wrap gap-1">
                            {b.deps.map((dep) => (
                              <span
                                key={dep}
                                className="rounded border border-indigo-500/30 bg-indigo-500/10 px-1.5 py-0.5 font-mono text-[10px] text-indigo-700 dark:text-indigo-300"
                              >
                                path → {dep}
                              </span>
                            ))}
                          </div>
                        )}
                        <div className="mt-1 text-[11px] text-fd-muted-foreground">
                          {lang === 'fi' ? b.noteFi : b.noteEn}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              {/* Column 3: Runtime Store Mem (Slots + Heap Allocations) */}
              <div className="rounded-lg border bg-fd-background p-3.5">
                <div className="mb-2 flex items-center justify-between border-b pb-2">
                  <span className="text-xs font-bold uppercase tracking-wider text-fd-muted-foreground">
                    {t('3. Ajonaikainen muisti Mem', '3. Runtime Store Mem')}
                  </span>
                  <span className="font-mono text-[11px] text-sky-600 dark:text-sky-400">A2/Semantics.lean</span>
                </div>

                <div className="text-[11px] font-semibold text-fd-muted-foreground">
                  {t('Pinopaikat (m.st : Var → Option Slot):', 'Variable Slots (m.st : Var → Option Slot):')}
                </div>
                <div className="mt-1.5 flex flex-col gap-1.5">
                  {currentStep.slots.length === 0 ? (
                    <div className="rounded border border-dashed p-2 text-center font-mono text-[11px] text-fd-muted-foreground">
                      ∀ v, m.st v = none
                    </div>
                  ) : (
                    currentStep.slots.map((sl) => (
                      <div
                        key={sl.varName}
                        className="flex items-center justify-between rounded border bg-fd-muted/30 px-2.5 py-1.5 font-mono text-xs"
                      >
                        <div>
                          <span className="font-bold text-fd-foreground">{sl.varName}</span>
                          <span className="ml-2 text-[11px] text-fd-muted-foreground">
                            own={sl.own ? 'true' : 'false'}
                          </span>
                        </div>
                        <span
                          className={`rounded px-1.5 py-0.5 text-[11px] ${
                            sl.val === null
                              ? 'bg-amber-500/15 text-amber-700 dark:text-amber-300'
                              : 'bg-sky-500/15 text-sky-700 dark:text-sky-300'
                          }`}
                        >
                          {sl.val ?? 'none (drop flag empty)'}
                        </span>
                      </div>
                    ))
                  )}
                </div>

                <div className="mt-3 text-[11px] font-semibold text-fd-muted-foreground">
                  {t('Keko-osoitteet (m.alloc : Nat → Bool):', 'Heap Addresses (m.alloc : Nat → Bool):')}
                </div>
                <div className="mt-1.5 grid grid-cols-1 gap-1.5">
                  {currentStep.heap.map((hb) => (
                    <div
                      key={hb.id}
                      className={`flex items-center justify-between rounded border px-2.5 py-1.5 font-mono text-xs ${
                        hb.allocated
                          ? 'border-emerald-500/40 bg-emerald-500/10 text-emerald-800 dark:text-emerald-200'
                          : 'border-dashed bg-fd-muted/40 text-fd-muted-foreground line-through'
                      }`}
                    >
                      <span>{hb.label}</span>
                      <span className="text-[10px] font-bold">
                        {hb.allocated ? `alloc=true (owner: ${hb.owner})` : 'alloc=false (freed)'}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Section 1C: Interactive Eff.kills Lattice Explorer */}
          <div className="rounded-xl border bg-fd-card p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-base font-bold text-fd-foreground">
                  {t('Interaktiivinen efektihila (Eff.kills): Mitkä lainat säilyvät ja mitkä kuolevat?', 'Interactive Effect & Invalidation Lattice (Eff.kills)')}
                </h3>
                <p className="mt-0.5 text-xs text-fd-muted-foreground">
                  {t('Kokeile mitä tahansa operaatiota säiliölle v (A2/Syntax.lean: Eff.kills e hv k) ja katso mitkä v:stä riippuvat sidonnat pysyvät elossa.', 'Select an operation on root container v (A2/Syntax.lean: Eff.kills e hv k) to see which dependent bindings stay live vs get invalidated.')}
                </p>
              </div>
              <button
                type="button"
                onClick={() => openDeclInBrowser('Eff.kills', 'A2')}
                className="inline-flex items-center gap-1 rounded-md border bg-fd-background px-3 py-1.5 font-mono text-xs font-semibold text-fd-primary hover:underline"
              >
                <span>A2.Eff.kills</span>
                <ExternalLink className="h-3.5 w-3.5" />
              </button>
            </div>

            <div className="mt-4 flex flex-wrap items-center gap-3">
              <div className="flex flex-wrap gap-1.5">
                {EFF_ROWS.map((row, idx) => (
                  <button
                    key={row.eff}
                    type="button"
                    onClick={() => setSelectedEffIdx(idx)}
                    className={`rounded-lg px-3 py-1.5 font-mono text-xs font-semibold transition-colors ${
                      selectedEffIdx === idx
                        ? 'bg-fd-primary text-fd-primary-foreground'
                        : 'border bg-fd-background text-fd-muted-foreground hover:text-fd-foreground'
                    }`}
                  >
                    Eff.{row.eff} (rank {row.rank})
                  </button>
                ))}
              </div>

              <label className="ml-auto inline-flex cursor-pointer items-center gap-2 rounded-lg border bg-fd-background px-3 py-1.5 text-xs">
                <input
                  type="checkbox"
                  checked={holdsView}
                  onChange={(e) => setHoldsView(e.target.checked)}
                  className="rounded"
                />
                <span>
                  {t('Säiliön alkiot sisältävät näkymiä (Ty.holdsView = true)', 'Container elements hold views (Ty.holdsView = true)')}
                </span>
              </label>
            </div>

            {/* Active Effect Outcome Cards */}
            {(() => {
              const row = EFF_ROWS[selectedEffIdx];
              const killsSelf = holdsView ? row.killsSelfWithView : row.killsSelfNoView;
              const cards = [
                {
                  kind: 'Kind.view',
                  titleFi: 'Näkymä puskuriin (.view)',
                  titleEn: 'Buffer View (.view)',
                  example: ': ( Slice i ) s ( slice_from_vec [i] v )',
                  killed: row.killsView,
                  whyFi: row.killsView
                    ? 'Puskuri voi siirtyä uuteen osoitteeseen tai vapautua → näkymä osoittaisi vanhaan puskuriin.'
                    : 'Vain luku ei siirrä eikä vapauta puskuria.',
                  whyEn: row.killsView
                    ? 'Buffer may reallocate or be freed → view would point to freed memory.'
                    : 'Read-only access never moves or frees the buffer.',
                },
                {
                  kind: 'Kind.inner',
                  titleFi: 'Alkiolaina (.inner)',
                  titleEn: 'Element Borrow (.inner)',
                  example: ': ~ ( Vec i ) elem ( vec_at v 0 )',
                  killed: row.killsInner,
                  whyFi: row.killsInner
                    ? 'Alkio saatetaan pudottaa (vec_pop) tai koko säiliö korvata.'
                    : 'Ulomman Vecin puskurin siirto (realloc) säilyttää alkioiden omat ohjaussolmut ehjinä!',
                  whyEn: row.killsInner
                    ? 'Element may be dropped (vec_pop) or whole container replaced.'
                    : 'Reallocating the outer Vec buffer leaves inner element heap nodes intact!',
                },
                {
                  kind: 'Kind.self',
                  titleFi: 'Kahvalaina (.self)',
                  titleEn: 'Handle Borrow (.self)',
                  example: ': ~ ( Vec i ) cur v',
                  killed: killsSelf,
                  whyFi: killsSelf
                    ? holdsView && row.eff !== 'replace'
                      ? 'Koska säiliö sisältää näkymiä (hv = true), alkion lisäys/poisto muuttaa mitä näkymiä kahvasta voi lukea (§2.10).'
                      : 'Koko omistaja siirrettiin, korvattiin tai vapautettiin.'
                    : 'Kahva osoittaa samaan ohjaussolmuun c, joka pysyy voimassa.',
                  whyEn: killsSelf
                    ? holdsView && row.eff !== 'replace'
                      ? 'Because the container holds views (hv = true), mutating elements changes which views can be read out (§2.10).'
                      : 'The owner itself was moved, reassigned, or freed.'
                    : 'Handle still points to the same header node c.',
                },
              ];

              return (
                <div className="mt-4 grid gap-3 md:grid-cols-3">
                  {cards.map((c) => (
                    <div
                      key={c.kind}
                      className={`rounded-lg border p-3.5 ${
                        c.killed
                          ? 'border-rose-500/40 bg-rose-500/10'
                          : 'border-emerald-500/40 bg-emerald-500/5'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-xs font-bold">{c.kind}</span>
                        <span
                          className={`rounded px-2 py-0.5 font-mono text-[11px] font-bold ${
                            c.killed
                              ? 'bg-rose-500/20 text-rose-700 dark:text-rose-300'
                              : 'bg-emerald-500/20 text-emerald-700 dark:text-emerald-300'
                          }`}
                        >
                          {c.killed ? 'KILLED (live := false)' : t('SÄILYY (live = true)', 'SURVIVES (live = true)')}
                        </span>
                      </div>
                      <div className="mt-1.5 font-semibold text-fd-foreground">
                        {lang === 'fi' ? c.titleFi : c.titleEn}
                      </div>
                      <code className="mt-1 block rounded bg-fd-background/80 px-2 py-1 font-mono text-[11px]">
                        {c.example}
                      </code>
                      <p className="mt-2 text-xs text-fd-muted-foreground">
                        {lang === 'fi' ? c.whyFi : c.whyEn}
                      </p>
                    </div>
                  ))}
                </div>
              );
            })()}
          </div>
        </div>
      )}

      {/* =====================================================================
          TAB 2: MATHEMATICIAN'S INTERACTIVE LEAN BLUEPRINT GRAPH (DAG)
         ===================================================================== */}
      {activeTab === 'blueprint' && (
        <div className="flex flex-col gap-6">
          <div className="rounded-xl border bg-fd-card p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-base font-bold text-fd-foreground">
                  {t('Lean Blueprint -riippuvuusverkko (Lauseet & Moduulit)', 'Interactive Lean Blueprint Dependency Graph (Theorems & Modules)')}
                </h3>
                <p className="mt-0.5 text-xs text-fd-muted-foreground">
                  {t('Klikkaa mitä tahansa solmua nähdäksesi sen välittömät riippuvuudet (oranssi), siitä riippuvat lauseet (vihreä) sekä täydellisen Lean 4 -määritelmän.', 'Click any node in the DAG to highlight its upstream dependencies (amber), downstream dependents (emerald), and inspect its formal Lean 4 statement.')}
                </p>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <div className="flex rounded-lg border bg-fd-muted/50 p-1">
                  <button
                    type="button"
                    onClick={() => setGraphMode('theorems')}
                    className={`rounded-md px-3 py-1 text-xs font-semibold ${
                      graphMode === 'theorems'
                        ? 'bg-fd-background text-fd-foreground shadow-sm'
                        : 'text-fd-muted-foreground hover:text-fd-foreground'
                    }`}
                  >
                    {t('Päälauseiden Blueprint (21)', 'Theorem Blueprint (21)')}
                  </button>
                  <button
                    type="button"
                    onClick={() => setGraphMode('modules-a2')}
                    className={`rounded-md px-3 py-1 text-xs font-semibold ${
                      graphMode === 'modules-a2'
                        ? 'bg-fd-background text-fd-foreground shadow-sm'
                        : 'text-fd-muted-foreground hover:text-fd-foreground'
                    }`}
                  >
                    {t('A2-modueliverkko (28)', 'A2 Module DAG (28)')}
                  </button>
                  <button
                    type="button"
                    onClick={() => setGraphMode('modules-a1')}
                    className={`rounded-md px-3 py-1 text-xs font-semibold ${
                      graphMode === 'modules-a1'
                        ? 'bg-fd-background text-fd-foreground shadow-sm'
                        : 'text-fd-muted-foreground hover:text-fd-foreground'
                    }`}
                  >
                    {t('A1-modueliverkko (22)', 'A1 Module DAG (22)')}
                  </button>
                </div>

                {/* Zoom controls */}
                <div className="flex items-center gap-1 rounded-lg border bg-fd-background p-1">
                  <button
                    type="button"
                    onClick={() => setZoom((z) => Math.max(0.75, +(z - 0.15).toFixed(2)))}
                    className="rounded p-1 hover:bg-fd-muted"
                    title="Zoom out"
                  >
                    <ZoomOut className="h-3.5 w-3.5" />
                  </button>
                  <span className="px-1.5 font-mono text-[11px]">{Math.round(zoom * 100)}%</span>
                  <button
                    type="button"
                    onClick={() => setZoom((z) => Math.min(1.5, +(z + 0.15).toFixed(2)))}
                    className="rounded p-1 hover:bg-fd-muted"
                    title="Zoom in"
                  >
                    <ZoomIn className="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
            </div>

            {/* Interactive SVG DAG Canvas */}
            <div className="mt-4 overflow-x-auto rounded-xl border bg-fd-background/90 p-3">
              {graphMode === 'theorems' ? (
                <svg
                  viewBox={`0 0 ${blueprintLayout.width} ${blueprintLayout.height}`}
                  style={{ minWidth: `${Math.round(760 * zoom)}px`, width: `${Math.round(100 * zoom)}%` }}
                  className="mx-auto block select-none"
                >
                  <defs>
                    <marker id="arrow-muted" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                      <path d="M 0 1 L 10 5 L 0 9 z" fill="currentColor" className="text-fd-muted-foreground/40" />
                    </marker>
                    <marker id="arrow-dep" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                      <path d="M 0 1 L 10 5 L 0 9 z" fill="#f59e0b" />
                    </marker>
                    <marker id="arrow-use" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                      <path d="M 0 1 L 10 5 L 0 9 z" fill="#10b981" />
                    </marker>
                  </defs>

                  {/* Edges */}
                  {blueprintLayout.edges.map((e) => {
                    const isUpstream = e.to === selectedBpNodeId;
                    const isDownstream = e.from === selectedBpNodeId;
                    const stroke = isUpstream ? '#f59e0b' : isDownstream ? '#10b981' : 'currentColor';
                    const marker = isUpstream
                      ? 'url(#arrow-dep)'
                      : isDownstream
                        ? 'url(#arrow-use)'
                        : 'url(#arrow-muted)';
                    const midY = (e.y1 + e.y2) / 2;
                    return (
                      <path
                        key={`${e.from}->${e.to}`}
                        d={`M ${e.x1} ${e.y1} C ${e.x1} ${midY}, ${e.x2} ${midY}, ${e.x2} ${e.y2}`}
                        fill="none"
                        stroke={stroke}
                        strokeWidth={isUpstream || isDownstream ? 2.5 : 1.25}
                        className={isUpstream || isDownstream ? '' : 'text-fd-muted-foreground/30'}
                        markerEnd={marker}
                      />
                    );
                  })}

                  {/* Nodes */}
                  {formalData.blueprintNodes.map((n) => {
                    const p = blueprintLayout.pos.get(n.id);
                    if (!p) return null;
                    const isSelected = n.id === selectedBpNodeId;
                    const isUpstream = selectedBpNode.deps.includes(n.id);
                    const isDownstream = n.deps.includes(selectedBpNodeId);
                    const boxW = 178;
                    const boxH = 44;

                    let strokeColor = 'rgba(148, 163, 184, 0.45)';
                    let fillColor = 'rgba(30, 41, 59, 0.06)';
                    if (n.tier === 5) {
                      strokeColor = '#10b981';
                      fillColor = 'rgba(16, 185, 129, 0.12)';
                    }
                    if (isSelected) {
                      strokeColor = '#3b82f6';
                      fillColor = 'rgba(59, 130, 246, 0.18)';
                    } else if (isUpstream) {
                      strokeColor = '#f59e0b';
                      fillColor = 'rgba(245, 158, 11, 0.14)';
                    } else if (isDownstream) {
                      strokeColor = '#10b981';
                      fillColor = 'rgba(16, 185, 129, 0.14)';
                    }

                    return (
                      <g
                        key={n.id}
                        transform={`translate(${p.x - boxW / 2}, ${p.y - boxH / 2})`}
                        onClick={() => setSelectedBpNodeId(n.id)}
                        className="cursor-pointer transition-opacity hover:opacity-90"
                      >
                        <rect
                          width={boxW}
                          height={boxH}
                          rx={8}
                          fill={fillColor}
                          stroke={strokeColor}
                          strokeWidth={isSelected ? 2.5 : 1.5}
                        />
                        <text
                          x={boxW / 2}
                          y={18}
                          textAnchor="middle"
                          className="fill-fd-foreground font-mono text-[12px] font-bold"
                        >
                          {n.tier === 5 ? `★ ${n.name}` : n.name}
                        </text>
                        <text
                          x={boxW / 2}
                          y={34}
                          textAnchor="middle"
                          className="fill-fd-muted-foreground font-sans text-[10px]"
                        >
                          {n.module}.lean · {n.kind}
                        </text>
                      </g>
                    );
                  })}
                </svg>
              ) : (
                <svg
                  viewBox={`0 0 ${moduleLayout.width} ${moduleLayout.height}`}
                  style={{ minWidth: `${Math.round(780 * zoom)}px`, width: `${Math.round(100 * zoom)}%` }}
                  className="mx-auto block select-none"
                >
                  <defs>
                    <marker id="mod-arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                      <path d="M 0 1 L 10 5 L 0 9 z" fill="currentColor" className="text-fd-muted-foreground/35" />
                    </marker>
                    <marker id="mod-arrow-up" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                      <path d="M 0 1 L 10 5 L 0 9 z" fill="#f59e0b" />
                    </marker>
                    <marker id="mod-arrow-down" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                      <path d="M 0 1 L 10 5 L 0 9 z" fill="#10b981" />
                    </marker>
                  </defs>

                  {moduleLayout.edges.map((e) => {
                    const isUpstream = e.to === selectedModName;
                    const isDownstream = e.from === selectedModName;
                    const stroke = isUpstream ? '#f59e0b' : isDownstream ? '#10b981' : 'currentColor';
                    const marker = isUpstream
                      ? 'url(#mod-arrow-up)'
                      : isDownstream
                        ? 'url(#mod-arrow-down)'
                        : 'url(#mod-arrow)';
                    const midY = (e.y1 + e.y2) / 2;
                    return (
                      <path
                        key={`${e.from}->${e.to}`}
                        d={`M ${e.x1} ${e.y1} C ${e.x1} ${midY}, ${e.x2} ${midY}, ${e.x2} ${e.y2}`}
                        fill="none"
                        stroke={stroke}
                        strokeWidth={isUpstream || isDownstream ? 2.5 : 1.15}
                        className={isUpstream || isDownstream ? '' : 'text-fd-muted-foreground/30'}
                        markerEnd={marker}
                      />
                    );
                  })}

                  {moduleLayout.mods.map((m) => {
                    const p = moduleLayout.pos.get(m.name);
                    if (!p) return null;
                    const isSelected = m.name === selectedModName;
                    const boxW = 114;
                    const boxH = 40;
                    const strokeColor = isSelected
                      ? '#3b82f6'
                      : m.layer === 5
                        ? '#10b981'
                        : 'rgba(148, 163, 184, 0.45)';
                    const fillColor = isSelected
                      ? 'rgba(59, 130, 246, 0.18)'
                      : m.layer === 5
                        ? 'rgba(16, 185, 129, 0.12)'
                        : 'rgba(30, 41, 59, 0.06)';

                    return (
                      <g
                        key={m.name}
                        transform={`translate(${p.x - boxW / 2}, ${p.y - boxH / 2})`}
                        onClick={() => setSelectedModName(m.name)}
                        className="cursor-pointer transition-opacity hover:opacity-90"
                      >
                        <rect
                          width={boxW}
                          height={boxH}
                          rx={7}
                          fill={fillColor}
                          stroke={strokeColor}
                          strokeWidth={isSelected ? 2.5 : 1.4}
                        />
                        <text
                          x={boxW / 2}
                          y={17}
                          textAnchor="middle"
                          className="fill-fd-foreground font-mono text-[11px] font-bold"
                        >
                          {m.name}
                        </text>
                        <text
                          x={boxW / 2}
                          y={31}
                          textAnchor="middle"
                          className="fill-fd-muted-foreground font-sans text-[9.5px]"
                        >
                          {m.lineCount}L · {m.counts.theorem} thm
                        </text>
                      </g>
                    );
                  })}
                </svg>
              )}
            </div>

            {/* Selected Node / Module Inspector Card */}
            {graphMode === 'theorems' ? (
              <div className="mt-4 rounded-xl border bg-fd-muted/30 p-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="rounded bg-fd-primary/15 px-2 py-0.5 font-mono text-xs font-bold text-fd-primary">
                        {selectedBpNode.kind} A2.{selectedBpNode.name}
                      </span>
                      <span className="font-mono text-xs text-fd-muted-foreground">
                        formal/A2/{selectedBpNode.module}.lean
                      </span>
                    </div>
                    <h4 className="mt-1.5 text-base font-bold text-fd-foreground">
                      {lang === 'fi' ? selectedBpNode.titleFi : selectedBpNode.titleEn}
                    </h4>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() => openDeclInBrowser(selectedBpNode.name, 'A2')}
                      className="inline-flex items-center gap-1.5 rounded-lg bg-fd-primary px-3 py-1.5 text-xs font-semibold text-fd-primary-foreground"
                    >
                      <Code2 className="h-3.5 w-3.5" />
                      <span>{t('Avaa koodiselaimessa', 'Open in Proof Browser')}</span>
                    </button>
                    <a
                      href={`${GITHUB_BASE}/formal/A2/${selectedBpNode.module}.lean${
                        selectedBpDecl ? `#L${selectedBpDecl.startLine}-L${selectedBpDecl.endLine}` : ''
                      }`}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center gap-1.5 rounded-lg border bg-fd-background px-3 py-1.5 text-xs font-medium hover:bg-fd-muted"
                    >
                      <span>GitHub</span>
                      <ExternalLink className="h-3.5 w-3.5" />
                    </a>
                  </div>
                </div>

                <p className="mt-2 text-xs leading-relaxed text-fd-foreground/90">
                  {lang === 'fi' ? selectedBpNode.explainFi : selectedBpNode.explainEn}
                </p>

                {/* Dependency pills */}
                <div className="mt-3 flex flex-wrap items-center gap-2 text-xs">
                  <span className="font-semibold text-amber-600 dark:text-amber-400">
                    {t('Käyttää (Uses):', 'Depends on (Uses):')}
                  </span>
                  {selectedBpNode.deps.length === 0 ? (
                    <span className="text-fd-muted-foreground">
                      {t('Perusmääritelmä (ei riippuvuuksia)', 'Foundational definition')}
                    </span>
                  ) : (
                    selectedBpNode.deps.map((depId) => (
                      <button
                        key={depId}
                        type="button"
                        onClick={() => setSelectedBpNodeId(depId)}
                        className="rounded border border-amber-500/40 bg-amber-500/10 px-2 py-0.5 font-mono text-xs text-amber-700 hover:underline dark:text-amber-300"
                      >
                        {depId}
                      </button>
                    ))
                  )}
                </div>

                {selectedBpDecl && (
                  <pre className="mt-3 max-h-72 overflow-auto rounded-lg border bg-fd-background p-3 font-mono text-xs leading-relaxed">
                    {selectedBpDecl.code}
                  </pre>
                )}
              </div>
            ) : (
              (() => {
                const mod =
                  moduleLayout.mods.find((m) => m.name === selectedModName) ?? moduleLayout.mods[0];
                const colors = LAYER_COLORS[mod.layer] ?? LAYER_COLORS[3];
                return (
                  <div className="mt-4 rounded-xl border bg-fd-muted/30 p-4">
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className={`rounded px-2 py-0.5 text-xs font-bold ${colors.badge}`}>
                            Layer {mod.layer}: {mod.category}
                          </span>
                          <span className="font-mono text-xs font-bold text-fd-foreground">{mod.path}</span>
                          <span className="text-xs text-fd-muted-foreground">
                            ({mod.lineCount} lines · {mod.counts.theorem} theorems · {mod.counts.total} decls)
                          </span>
                        </div>
                        <p className="mt-2 text-xs font-medium text-fd-foreground">
                          {lang === 'fi' ? mod.summaryFi : mod.summaryEn}
                        </p>
                        {mod.doc && (
                          <p className="mt-1.5 whitespace-pre-line text-xs text-fd-muted-foreground">{mod.doc}</p>
                        )}
                      </div>

                      <div className="flex gap-2">
                        <button
                          type="button"
                          onClick={() => {
                            setBrowserPhase(moduleLayout.phaseKey);
                            setBrowserModule(mod.name);
                            setBrowserKind('all');
                            setBrowserSearch('');
                            if (mod.declNames[0]) setSelectedDeclName(mod.declNames[0]);
                            setActiveTab('browser');
                          }}
                          className="inline-flex items-center gap-1.5 rounded-lg bg-fd-primary px-3 py-1.5 text-xs font-semibold text-fd-primary-foreground"
                        >
                          <FileCode className="h-3.5 w-3.5" />
                          <span>
                            {t(`Selaa moduulin ${mod.counts.total} määritelmää`, `Browse all ${mod.counts.total} declarations`)}
                          </span>
                        </button>
                        <a
                          href={`${GITHUB_BASE}/${mod.path}`}
                          target="_blank"
                          rel="noreferrer"
                          className="inline-flex items-center gap-1.5 rounded-lg border bg-fd-background px-3 py-1.5 text-xs font-medium hover:bg-fd-muted"
                        >
                          <span>GitHub</span>
                          <ExternalLink className="h-3.5 w-3.5" />
                        </a>
                      </div>
                    </div>

                    <div className="mt-3 flex flex-wrap items-center gap-1.5">
                      <span className="text-xs font-semibold text-fd-muted-foreground">
                        {t('Tuonnit (Imports):', 'Imports:')}
                      </span>
                      {mod.imports.length === 0 ? (
                        <span className="text-xs text-fd-muted-foreground">none (root module)</span>
                      ) : (
                        mod.imports.map((imp) => (
                          <button
                            key={imp}
                            type="button"
                            onClick={() => setSelectedModName(imp)}
                            className="rounded border bg-fd-background px-2 py-0.5 font-mono text-xs hover:underline"
                          >
                            {moduleLayout.phaseKey}.{imp}
                          </button>
                        ))
                      )}
                    </div>
                  </div>
                );
              })()
            )}
          </div>
        </div>
      )}

      {/* =====================================================================
          TAB 3: FULL LEAN 4 CODE & PROOF BROWSER (1,766 DECLARATIONS)
         ===================================================================== */}
      {activeTab === 'browser' && (
        <div className="rounded-xl border bg-fd-card p-5">
          {/* Filter Bar */}
          <div className="flex flex-wrap items-center gap-2.5 border-b pb-4">
            {/* Phase toggle A2 / A1 */}
            <div className="flex rounded-lg border bg-fd-muted/50 p-1">
              <button
                type="button"
                onClick={() => {
                  setBrowserPhase('A2');
                  setBrowserModule('all');
                }}
                className={`rounded-md px-3 py-1 text-xs font-semibold ${
                  browserPhase === 'A2'
                    ? 'bg-fd-background text-fd-foreground shadow-sm'
                    : 'text-fd-muted-foreground'
                }`}
              >
                Phase A2 ({formalData.stats.a2.totalDecls})
              </button>
              <button
                type="button"
                onClick={() => {
                  setBrowserPhase('A1');
                  setBrowserModule('all');
                }}
                className={`rounded-md px-3 py-1 text-xs font-semibold ${
                  browserPhase === 'A1'
                    ? 'bg-fd-background text-fd-foreground shadow-sm'
                    : 'text-fd-muted-foreground'
                }`}
              >
                Phase A1 ({formalData.stats.a1.totalDecls})
              </button>
            </div>

            {/* Module selector */}
            <select
              value={browserModule}
              onChange={(e) => setBrowserModule(e.target.value)}
              className="rounded-lg border bg-fd-background px-3 py-1.5 text-xs font-medium"
            >
              <option value="all">
                {t(`Kaikki moduulit (${formalData.modules[browserPhase].length})`, `All modules (${formalData.modules[browserPhase].length})`)}
              </option>
              {formalData.modules[browserPhase].map((m) => (
                <option key={m.name} value={m.name}>
                  {browserPhase}.{m.name} ({m.counts.total})
                </option>
              ))}
            </select>

            {/* Kind filter */}
            <select
              value={browserKind}
              onChange={(e) => setBrowserKind(e.target.value)}
              className="rounded-lg border bg-fd-background px-3 py-1.5 text-xs font-medium"
            >
              <option value="all">{t('Kaikki tyypit', 'All kinds')}</option>
              <option value="theorem">theorem / lemma</option>
              <option value="inductive">inductive</option>
              <option value="structure">structure</option>
              <option value="def">def / abbrev</option>
            </select>

            {/* Search input */}
            <div className="relative flex-1 min-w-[200px]">
              <Search className="pointer-events-none absolute left-2.5 top-2 h-3.5 w-3.5 text-fd-muted-foreground" />
              <input
                type="text"
                value={browserSearch}
                onChange={(e) => setBrowserSearch(e.target.value)}
                placeholder={t(
                  'Hae lauseen nimellä, tyypillä tai selitteellä (esim. no_leak, panic_unwind, Eff.kills)…',
                  'Search theorem name, signature, or docstring (e.g. no_leak, panic_unwind, Eff.kills)…',
                )}
                className="w-full rounded-lg border bg-fd-background py-1.5 pl-8 pr-3 text-xs"
              />
            </div>

            <span className="font-mono text-xs text-fd-muted-foreground">
              {filteredDecls.length} {t('osumaa', 'results')}
            </span>
          </div>

          {/* Master-Detail Split View */}
          <div className="mt-4 grid gap-4 lg:grid-cols-12">
            {/* Left Sidebar: Declaration List */}
            <div className="max-h-[600px] overflow-y-auto rounded-lg border bg-fd-background lg:col-span-4">
              {filteredDecls.slice(0, 250).map((d) => {
                const selected = activeDecl?.name === d.name && activeDecl?.module === d.module;
                const badgeColor =
                  d.kind === 'theorem'
                    ? 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300'
                    : d.kind === 'inductive' || d.kind === 'structure'
                      ? 'bg-violet-500/15 text-violet-700 dark:text-violet-300'
                      : 'bg-sky-500/15 text-sky-700 dark:text-sky-300';
                return (
                  <button
                    key={`${d.module}:${d.name}:${d.startLine}`}
                    type="button"
                    onClick={() => setSelectedDeclName(d.name)}
                    className={`flex w-full flex-col items-start border-b px-3 py-2.5 text-left transition-colors ${
                      selected ? 'bg-fd-primary/10' : 'hover:bg-fd-muted/50'
                    }`}
                  >
                    <div className="flex w-full items-center justify-between gap-2">
                      <span className="truncate font-mono text-xs font-bold text-fd-foreground">{d.name}</span>
                      <span className={`shrink-0 rounded px-1.5 py-0.5 font-mono text-[10px] font-semibold ${badgeColor}`}>
                        {d.kind}
                      </span>
                    </div>
                    <div className="mt-0.5 flex w-full items-center justify-between text-[11px] text-fd-muted-foreground">
                      <span>
                        {d.phase}.{d.module}
                      </span>
                      <span>
                        L{d.startLine}–{d.endLine}
                      </span>
                    </div>
                  </button>
                );
              })}
              {filteredDecls.length > 250 && (
                <div className="p-3 text-center text-xs text-fd-muted-foreground">
                  {t(`Näytetään ensimmäiset 250 / ${filteredDecls.length}. Tarkenna hakua.`, `Showing first 250 of ${filteredDecls.length}. Refine search or module filter.`)}
                </div>
              )}
            </div>

            {/* Right Inspector: Selected Declaration Details & Code */}
            <div className="flex flex-col gap-3 rounded-lg border bg-fd-background p-4 lg:col-span-8">
              {activeDecl ? (
                <>
                  <div className="flex flex-wrap items-start justify-between gap-2 border-b pb-3">
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="rounded bg-fd-primary/15 px-2 py-0.5 font-mono text-xs font-bold text-fd-primary">
                          {activeDecl.kind}
                        </span>
                        <h4 className="font-mono text-base font-bold text-fd-foreground">
                          {activeDecl.phase}.{activeDecl.name}
                        </h4>
                      </div>
                      <div className="mt-1 font-mono text-xs text-fd-muted-foreground">
                        formal/{activeDecl.phase}/{activeDecl.module}.lean · lines {activeDecl.startLine}–
                        {activeDecl.endLine} ({activeDecl.lineCount} lines)
                      </div>
                    </div>

                    <a
                      href={`${GITHUB_BASE}/formal/${activeDecl.phase}/${activeDecl.module}.lean#L${activeDecl.startLine}-L${activeDecl.endLine}`}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center gap-1.5 rounded-lg border bg-fd-muted/40 px-3 py-1.5 text-xs font-medium hover:bg-fd-muted"
                    >
                      <span>{t('Katso GitHubissa', 'View on GitHub')}</span>
                      <ExternalLink className="h-3.5 w-3.5" />
                    </a>
                  </div>

                  {/* Docstring */}
                  {activeDecl.doc && (
                    <div className="rounded-lg border border-indigo-500/25 bg-indigo-500/5 p-3 text-xs leading-relaxed text-fd-foreground">
                      {activeDecl.doc}
                    </div>
                  )}

                  {/* Dependencies (Uses & Used By) */}
                  <div className="grid gap-2 sm:grid-cols-2">
                    <div className="rounded-lg border bg-fd-muted/20 p-2.5">
                      <div className="text-[11px] font-bold uppercase text-amber-600 dark:text-amber-400">
                        {t(`Käyttää (${activeDecl.deps.length}):`, `Uses / Depends on (${activeDecl.deps.length}):`)}
                      </div>
                      <div className="mt-1.5 flex flex-wrap gap-1">
                        {activeDecl.deps.length === 0 ? (
                          <span className="text-xs text-fd-muted-foreground">—</span>
                        ) : (
                          activeDecl.deps.map((dep) => (
                            <button
                              key={dep}
                              type="button"
                              onClick={() => openDeclInBrowser(dep, activeDecl.phase)}
                              className="rounded border bg-fd-background px-1.5 py-0.5 font-mono text-[11px] text-fd-primary hover:underline"
                            >
                              {dep}
                            </button>
                          ))
                        )}
                      </div>
                    </div>

                    <div className="rounded-lg border bg-fd-muted/20 p-2.5">
                      <div className="text-[11px] font-bold uppercase text-emerald-600 dark:text-emerald-400">
                        {t(`Käytetään lauseissa (${activeDecl.usedBy.length}):`, `Used by (${activeDecl.usedBy.length}):`)}
                      </div>
                      <div className="mt-1.5 flex flex-wrap gap-1">
                        {activeDecl.usedBy.length === 0 ? (
                          <span className="text-xs text-fd-muted-foreground">
                            {t('Huippulause / päätelmä', 'Top-level theorem')}
                          </span>
                        ) : (
                          activeDecl.usedBy.map((u) => (
                            <button
                              key={u}
                              type="button"
                              onClick={() => openDeclInBrowser(u, activeDecl.phase)}
                              className="rounded border bg-fd-background px-1.5 py-0.5 font-mono text-[11px] text-emerald-700 hover:underline dark:text-emerald-300"
                            >
                              {u}
                            </button>
                          ))
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Lean 4 Source Code */}
                  <div className="relative">
                    <div className="mb-1 flex items-center justify-between text-[11px] text-fd-muted-foreground">
                      <span>Lean 4 Source</span>
                      {activeDecl.truncated && (
                        <a
                          href={`${GITHUB_BASE}/formal/${activeDecl.phase}/${activeDecl.module}.lean#L${activeDecl.startLine}-L${activeDecl.endLine}`}
                          target="_blank"
                          rel="noreferrer"
                          className="text-fd-primary hover:underline"
                        >
                          {t('Avaa koko todistus GitHubissa →', 'Open full proof on GitHub →')}
                        </a>
                      )}
                    </div>
                    <pre className="max-h-[420px] overflow-auto rounded-lg border bg-fd-muted/30 p-3.5 font-mono text-xs leading-6 text-fd-foreground">
                      {activeDecl.code}
                    </pre>
                  </div>
                </>
              ) : null}
            </div>
          </div>
        </div>
      )}

      {/* =====================================================================
          TAB 4: SOUNDNESS HOLES CORPUS & FORMAL RULES MATRIX
         ===================================================================== */}
      {activeTab === 'holes' && (
        <div className="rounded-xl border bg-fd-card p-5">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b pb-4">
            <div className="flex rounded-lg border bg-fd-muted/50 p-1">
              <button
                type="button"
                onClick={() => setHolesSubTab('probes')}
                className={`rounded-md px-3 py-1.5 text-xs font-semibold ${
                  holesSubTab === 'probes'
                    ? 'bg-fd-background text-fd-foreground shadow-sm'
                    : 'text-fd-muted-foreground'
                }`}
              >
                {t(
                  `${formalData.stats.holesCount} Reikäkoetta (tools/fuzz/holes/)`,
                  `${formalData.stats.holesCount} Soundness Hole Probes`,
                )}
              </button>
              <button
                type="button"
                onClick={() => setHolesSubTab('rules')}
                className={`rounded-md px-3 py-1.5 text-xs font-semibold ${
                  holesSubTab === 'rules'
                    ? 'bg-fd-background text-fd-foreground shadow-sm'
                    : 'text-fd-muted-foreground'
                }`}
              >
                {t(`docs/MEMORY.md → Lean-sääntömatriisi (${formalData.rules.length})`, `docs/MEMORY.md → Formal Rules Matrix (${formalData.rules.length})`)}
              </button>
            </div>

            {holesSubTab === 'probes' && (
              <div className="flex flex-wrap items-center gap-2">
                {(['all', 'A1', 'A2', 'A3', 'B'] as const).map((ph) => (
                  <button
                    key={ph}
                    type="button"
                    onClick={() => setHolePhaseFilter(ph)}
                    className={`rounded-md px-2.5 py-1 text-xs font-semibold ${
                      holePhaseFilter === ph
                        ? 'bg-fd-primary text-fd-primary-foreground'
                        : 'border bg-fd-background text-fd-muted-foreground'
                    }`}
                  >
                    {ph === 'all'
                      ? `${t('Kaikki', 'All')} (${formalData.stats.holesCount})`
                      : `${ph} (${formalData.stats.holesByPhase[ph]})`}
                  </button>
                ))}
                <div className="relative min-w-[200px]">
                  <Search className="pointer-events-none absolute left-2.5 top-2 h-3.5 w-3.5 text-fd-muted-foreground" />
                  <input
                    type="text"
                    value={holeSearch}
                    onChange={(e) => setHoleSearch(e.target.value)}
                    placeholder={t('Hae reikää (esim. slice, closure)…', 'Filter holes (e.g. slice, closure)…')}
                    className="w-full rounded-lg border bg-fd-background py-1.5 pl-8 pr-3 text-xs"
                  />
                </div>
              </div>
            )}
          </div>

          {holesSubTab === 'probes' ? (
            <div className="mt-4 grid gap-4 lg:grid-cols-12">
              {/* Left list of probes */}
              <div className="max-h-[540px] overflow-y-auto rounded-lg border bg-fd-background lg:col-span-5">
                {filteredHoles.map((h) => {
                  const selected = selectedHole.probe === h.probe;
                  return (
                    <button
                      key={h.probe}
                      type="button"
                      onClick={() => setSelectedHole(h)}
                      className={`flex w-full flex-col items-start border-b px-3 py-2.5 text-left transition-colors ${
                        selected ? 'bg-fd-primary/10' : 'hover:bg-fd-muted/50'
                      }`}
                    >
                      <div className="flex w-full items-center justify-between gap-2">
                        <span className="truncate font-mono text-xs font-bold text-fd-foreground">{h.probe}</span>
                        <div className="flex shrink-0 items-center gap-1">
                          <span className="rounded bg-fd-muted px-1.5 py-0.5 font-mono text-[10px] font-semibold">
                            {h.phase}
                          </span>
                          <span className="rounded bg-indigo-500/15 px-1.5 py-0.5 font-mono text-[10px] text-indigo-700 dark:text-indigo-300">
                            {h.rule}
                          </span>
                        </div>
                      </div>
                      <p className="mt-1 line-clamp-1 text-xs text-fd-muted-foreground">{h.note}</p>
                    </button>
                  );
                })}
              </div>

              {/* Right detail of selected hole probe */}
              <div className="flex flex-col gap-3 rounded-lg border bg-fd-background p-4 lg:col-span-7">
                <div className="flex flex-wrap items-start justify-between gap-2 border-b pb-3">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="rounded bg-rose-500/15 px-2 py-0.5 font-mono text-xs font-bold text-rose-700 dark:text-rose-300">
                        nurlc: {selectedHole.nurlc}
                      </span>
                      <span className="rounded bg-indigo-500/15 px-2 py-0.5 font-mono text-xs font-bold text-indigo-700 dark:text-indigo-300">
                        Phase {selectedHole.phase} · Rule: {selectedHole.rule}
                      </span>
                    </div>
                    <h4 className="mt-1.5 font-mono text-base font-bold text-fd-foreground">
                      tools/fuzz/holes/{selectedHole.probe}.nu
                    </h4>
                  </div>

                  <div className="flex gap-2">
                    {!selectedHole.rule.startsWith('§') && (
                      <button
                        type="button"
                        onClick={() => openDeclInBrowser(selectedHole.rule.split('.')[0], 'A2')}
                        className="inline-flex items-center gap-1 rounded-lg bg-fd-primary px-3 py-1.5 text-xs font-semibold text-fd-primary-foreground"
                      >
                        <Code2 className="h-3.5 w-3.5" />
                        <span>Lean: {selectedHole.rule}</span>
                      </button>
                    )}
                    <a
                      href={`${GITHUB_BASE}/tools/fuzz/holes/${selectedHole.probe}.nu`}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center gap-1 rounded-lg border px-2.5 py-1.5 text-xs hover:bg-fd-muted"
                    >
                      <span>GitHub</span>
                      <ExternalLink className="h-3 w-3" />
                    </a>
                  </div>
                </div>

                <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 text-xs">
                  <span className="font-bold text-fd-foreground">
                    {t('Mitä reikäkoe yrittää tehdä: ', 'What this soundness probe attempts: ')}
                  </span>
                  <span className="text-fd-foreground/90">{selectedHole.note}</span>
                </div>

                <div>
                  <div className="mb-1 font-mono text-[11px] text-fd-muted-foreground">
                    NURL Probe Source ({selectedHole.probe}.nu)
                  </div>
                  <pre className="max-h-[380px] overflow-auto rounded-lg border bg-fd-muted/30 p-3.5 font-mono text-xs leading-6 text-fd-foreground">
                    {selectedHole.code || '// Source file on GitHub'}
                  </pre>
                </div>
              </div>
            </div>
          ) : (
            <div className="mt-4 overflow-x-auto">
              <table className="w-full border-collapse text-left text-xs">
                <thead>
                  <tr className="border-b bg-fd-muted/40">
                    <th className="p-2.5 font-semibold">docs/MEMORY.md</th>
                    <th className="p-2.5 font-semibold">{t('Omistajuussääntö', 'Ownership Rule')}</th>
                    <th className="p-2.5 font-semibold">Phase</th>
                    <th className="p-2.5 font-semibold">
                      {t('Formaali Lean-vastine', 'Formal Lean Counterpart')}
                    </th>
                    <th className="p-2.5 font-semibold">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {formalData.rules.map((r) => (
                    <tr key={r.section} className="border-b hover:bg-fd-muted/20">
                      <td className="p-2.5 font-mono font-bold whitespace-nowrap">{r.section}</td>
                      <td className="p-2.5 font-medium">{r.rule}</td>
                      <td className="p-2.5 font-mono whitespace-nowrap">{r.phase}</td>
                      <td className="p-2.5 font-mono text-[11px] text-fd-muted-foreground">{r.formalRule}</td>
                      <td className="p-2.5 whitespace-nowrap">
                        <span
                          className={`rounded px-2 py-0.5 font-mono text-[10px] font-bold ${
                            r.status.startsWith('done')
                              ? 'bg-emerald-500/20 text-emerald-700 dark:text-emerald-300'
                              : 'bg-fd-muted text-fd-muted-foreground'
                          }`}
                        >
                          {r.status}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
