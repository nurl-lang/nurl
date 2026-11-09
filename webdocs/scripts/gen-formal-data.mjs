// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Extracts Lean 4 module graphs, declarations, theorem dependency graphs,
// ownership rules (formal/RULES.md), and the soundness hole corpus
// (the probe table of tools/fuzz/holes/map.sh + tools/fuzz/holes/*.nu) into:
//   1. webdocs/lib/formal-data.generated.ts (compact typed metadata, module DAGs, blueprint, rules, holes)
//   2. webdocs/public/formal-decls.json (all declarations across A1, A2 & A3 for the code browser)
//   3. formal/BLUEPRINT.md's counts, A2 module DAG, A2 module index and crown
//      theorem statements (the regions between its `BEGIN generated` markers)
//
// `--check` writes nothing: it exits 1 when formal/BLUEPRINT.md is not what
// the sources give (CI's "shared files are generated" job, Agora #246).

import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, '..', '..');
const FORMAL_DIR = join(ROOT, 'formal');
const HOLES_DIR = join(ROOT, 'tools', 'fuzz', 'holes');
const OUTPUT_TS = join(ROOT, 'webdocs', 'lib', 'formal-data.generated.ts');
const OUTPUT_JSON = join(ROOT, 'webdocs', 'public', 'formal-decls.json');
const BLUEPRINT_MD = join(FORMAL_DIR, 'BLUEPRINT.md');
const CHECK = process.argv.includes('--check');

const MODULE_LAYERS = {
  Syntax: {
    layer: 0,
    category: 'Syntax & Store',
    summaryEn: 'Types, effect & kill lattice (Eff.kills), expressions, statements, and store values (Mem, Slot, Val).',
  },
  Semantics: {
    layer: 0,
    category: 'Syntax & Store',
    summaryEn: 'Small-step operational semantics (Step, Steps), tree deallocation (Frees, DropSlot), call expansion, and Stuck.',
  },
  Typing: {
    layer: 1,
    category: 'Flow-Sensitive Typing',
    summaryEn: 'Flow-sensitive context Γ, kill operation, and typing rules for RHS, statements, calls, and functions (RhsT, StmtT, CallT, FnOK).',
  },
  Basic: {
    layer: 1,
    category: 'Flow-Sensitive Typing',
    summaryEn: 'Foundational lemmas for store updates (upd), value subtrees, and contexts.',
  },
  Ctx: {
    layer: 1,
    category: 'Flow-Sensitive Typing',
    summaryEn: 'Algebraic properties and monotonicity of context operations (kill, exitScope, derive).',
  },
  TypingFacts: {
    layer: 1,
    category: 'Flow-Sensitive Typing',
    summaryEn: 'Inversion lemmas and structural properties of well-typed statements (StmtT).',
  },
  Invariant: {
    layer: 2,
    category: 'Memory Invariant',
    summaryEn: 'Configuration invariant (Inv, HeapOK, Covers, ValOK, ViewsOK): single ownership and valid borrows/views.',
  },
  Stability: {
    layer: 2,
    category: 'Memory Invariant',
    summaryEn: 'Stability of borrows and views under store and context updates.',
  },
  Heap: {
    layer: 2,
    category: 'Memory Invariant',
    summaryEn: 'Preservation of heap disjointness and allocation validity (HeapOK) across store operations.',
  },
  Values: {
    layer: 2,
    category: 'Memory Invariant',
    summaryEn: 'Well-formedness lemmas for values, structs (pair), enums (inl/inr), and views.',
  },
  Wf: {
    layer: 2,
    category: 'Memory Invariant',
    summaryEn: 'Preservation of context well-formedness (WfCtx) across typing transitions.',
  },
  NameWf: {
    layer: 2,
    category: 'Memory Invariant',
    summaryEn: 'Well-formedness and invariants for by-name closure captures (Kind.name).',
  },
  Frame: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryEn: 'How runtime frames (scope, rbind, frozen) interact with the memory invariant.',
  },
  StepFrame: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryEn: 'Invariant preservation across frame steps and panic unwinding frames.',
  },
  Rhs: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryEn: 'Stepping and invariant preservation for right-hand side evaluations (Rhs).',
  },
  Steps: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryEn: 'Preservation lemmas for individual statement steps (letv, assign, push, free, unpair).',
  },
  Leak: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryEn: 'Leak-freedom invariant (Covers): every allocated address is owned by a live binding.',
  },
  Panic: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryEn: 'Panic unwinding (panic_unwind): every exited scope drops its owned trees via the drop journal.',
  },
  EditB: {
    layer: 3,
    category: 'Proof Infrastructure',
    summaryEn: 'Element edits through borrows (StmtT.editB): push, truncate, and element set through borrowed paths.',
  },
  EditBV: {
    layer: 3,
    category: 'Proof Infrastructure',
    summaryEn: 'A view stored through a borrow (StmtT.editBV): every view-holding root of the borrow\'s path holds what the stored value depends on.',
  },
  Elem: {
    layer: 3,
    category: 'Proof Infrastructure',
    summaryEn: 'An element handed over (withElem, insert): the invariant does not see the order of an owned Vec\'s elements (MInv.perm).',
  },
  EnvHand: {
    layer: 3,
    category: 'Proof Infrastructure',
    summaryEn: 'Closure and trait-object environment hand-over (StmtT.callcE) for inout receivers.',
  },
  Repl: {
    layer: 3,
    category: 'Proof Infrastructure',
    summaryEn: 'One-hole replacement (Repl): a change through a borrowed handle rewrites one node of its owner\'s tree and leaves the rest.',
  },
  Sweep: {
    layer: 3,
    category: 'Proof Infrastructure',
    summaryEn: 'The sweep (Mem.sweep): shared blocks (Arc, lock blocks) that nothing reaches are removed and their payloads freed, from every thread\'s roots.',
  },
  Rename: {
    layer: 4,
    category: 'Calls & Closures',
    summaryEn: 'Alpha-renaming of function body variables to fresh variables at a call site.',
  },
  Call: {
    layer: 4,
    category: 'Calls & Closures',
    summaryEn: 'Typing of expanded function calls (callStmt) from function summaries (FnOK + CallT).',
  },
  Bind: {
    layer: 4,
    category: 'Calls & Closures',
    summaryEn: 'Binding call arguments (in, inout, sink) from caller context into callee frame.',
  },
  CallMem: {
    layer: 4,
    category: 'Calls & Closures',
    summaryEn: 'Store state and owned trees immediately after binding parameters in a call.',
  },
  CallInv: {
    layer: 4,
    category: 'Calls & Closures',
    summaryEn: 'Full invariant preservation (callCase, recCase) across function call and recover expansion.',
  },
  Closure: {
    layer: 4,
    category: 'Calls & Closures',
    summaryEn: 'Closure and trait-object package calls (callc, cloCase, cloProgress) and by-name capture soundness.',
  },
  SrcKeep: {
    layer: 2,
    category: 'Memory Invariant',
    summaryEn: 'Source typing keeps a borrowed parameter\'s entry (StmtT.ctxRel), so a destructor\'s frame gets KeepOut, CtxWF and NameWF of its body without premises on letd (srcCase).',
  },
  Codes: {
    layer: 4,
    category: 'Calls & Closures',
    summaryEn: 'Package code-pointer integrity (ProgCodes, MemCodes, codes_step) across execution steps.',
  },
  Preservation: {
    layer: 5,
    category: 'Soundness Theorems',
    summaryEn: 'Preservation theorem (preserve): every execution step preserves typing StmtT and memory invariant Inv.',
  },
  Progress: {
    layer: 5,
    category: 'Soundness Theorems',
    summaryEn: 'Progress theorem (progress): a well-typed statement is either .skip or can step (never Stuck).',
  },
  Soundness: {
    layer: 5,
    category: 'Soundness Theorems',
    summaryEn: 'Main theorems: soundness, memory_safe, no_leak_end, and no_leak_panic.',
  },
  DynCell: {
    layer: 5,
    category: 'Worked Examples',
    summaryEn: 'Per-call ownership through an owner cell: the pick example typed with A2\'s rules, and memory_safe and no_leak_end applied to it (pick_ok, main_safe, main_no_leak).',
  },
};

const A3_MODULE_LAYERS = {
  Defs: {
    layer: 0,
    category: 'Configuration & Claims',
    summaryEn: 'Concurrent configurations (Cfg, Thread), thread steps (TStep, spawn), memory touches (Touch), races (Race), and the A3 claims (MemorySafe, RaceFree, NoLeak, Claim).',
  },
  Frame: {
    layer: 1,
    category: 'Address-Space Partition',
    summaryEn: 'Address-space partitions (Split, minus, union), owned addresses (OwnedId), and disjointness.',
  },
  Rel: {
    layer: 1,
    category: 'Address-Space Partition',
    summaryEn: 'Ghost-store relation (GhostRel) equating stores up to snapshots remembered by recover frames.',
  },
  Fresh: {
    layer: 1,
    category: 'Address-Space Partition',
    summaryEn: 'Fresh-allocation lemmas: every step allocates only addresses at or above nid.',
  },
  BorFree: {
    layer: 1,
    category: 'Address-Space Partition',
    summaryEn: 'Borrowed slots hold no owned heap addresses; ownership resides exclusively in owning slots and shared blocks.',
  },
  Owned: {
    layer: 1,
    category: 'Address-Space Partition',
    summaryEn: 'Every address in an owned tree after a step was either already owned by that thread or freshly allocated.',
  },
  Keep: {
    layer: 1,
    category: 'Address-Space Partition',
    summaryEn: 'Frame preservation: a thread step leaves every other thread\'s address-space partition untouched.',
  },
  Nid: {
    layer: 2,
    category: 'Per-Thread Invariants & Touch',
    summaryEn: 'Monotonicity of per-thread invariants under advances of the global fresh-address counter nid.',
  },
  Ghost: {
    layer: 2,
    category: 'Per-Thread Invariants & Touch',
    summaryEn: 'Stability of per-thread invariants across GhostRel store updates.',
  },
  Thread: {
    layer: 2,
    category: 'Per-Thread Invariants & Touch',
    summaryEn: 'Per-thread invariant bundle (ThreadOK) lifting A2\'s preservation, progress, and no-leak to a thread\'s view.',
  },
  Touch: {
    layer: 2,
    category: 'Per-Thread Invariants & Touch',
    summaryEn: 'Footprint confinement (touch_owned): every address a thread\'s next step touches lies in its own partition or shared frozen blocks.',
  },
  Cell: {
    layer: 2,
    category: 'Per-Thread Invariants & Touch',
    summaryEn: 'Confinement of Send-not-Sync library handles (CellInv) across steps and SendCheck crossings; CellRace freedom.',
  },
  Restrict: {
    layer: 3,
    category: 'Frame Lemmas',
    summaryEn: 'Step restriction (Step.restrict): a step on the shared configuration store restricts to a step on the thread\'s own partition.',
  },
  Lift: {
    layer: 3,
    category: 'Frame Lemmas',
    summaryEn: 'Step lifting (Step.lift): a step on a thread\'s partition lifts to the shared configuration store.',
  },
  Config: {
    layer: 4,
    category: 'Configuration & Spawn',
    summaryEn: 'Global configuration invariant (CInv): pairwise disjoint thread partitions, shared block invariants, and ThreadOK on every thread.',
  },
  Pres: {
    layer: 4,
    category: 'Configuration & Spawn',
    summaryEn: 'Preservation of the global configuration invariant (CInv) across normal and panic thread steps.',
  },
  SpawnOld: {
    layer: 4,
    category: 'Configuration & Spawn',
    summaryEn: 'Spawner-side soundness: moving sink arguments to a newly spawned thread preserves the spawner\'s ThreadOK on its remaining partition.',
  },
  SpawnNew: {
    layer: 4,
    category: 'Configuration & Spawn',
    summaryEn: 'Spawnee-side soundness: the newly spawned thread starts with ThreadOK on the partition of moved argument trees.',
  },
  SpawnPres: {
    layer: 4,
    category: 'Configuration & Spawn',
    summaryEn: 'Preservation of CInv across thread spawn (TStep.spawn and TStep.spawnFail).',
  },
  Assemble: {
    layer: 4,
    category: 'Configuration & Spawn',
    summaryEn: 'Assembling global MemorySafe, RaceFree, and NoLeak from CInv and the frame/spawn lemmas (claim_from).',
  },
  Claim: {
    layer: 5,
    category: 'Data-Race Freedom Theorems',
    summaryEn: 'Crown theorem A3.claim: every well-typed concurrent program is memory-safe, data-race-free, and leak-free across all thread interleavings.',
  },
  Make: {
    layer: 5,
    category: 'Data-Race Freedom Theorems',
    summaryEn: 'Module-global initialization phase (Made, made_safe, made_ok) and crown theorem A3.claim_made.',
  },
};

function cleanComment(raw) {
  return raw
    .replace(/^\/-[-!]?\s*/, '')
    .replace(/\s*-\/$/, '')
    .split('\n')
    .map((line) => line.replace(/^\s{0,4}/, ''))
    .join('\n')
    .trim();
}

function parseLeanFile(phase, modName, filePath) {
  const content = readFileSync(filePath, 'utf8');
  const lines = content.split('\n');

  const imports = [];
  for (const line of lines) {
    const m = line.match(/^import\s+([A-Za-z0-9_.]+)/);
    if (m) imports.push(m[1]);
  }

  let moduleDoc = '';
  const nsMatch = content.match(/\bnamespace\s+A[123]\b/);
  const headerSlice = nsMatch ? content.slice(0, nsMatch.index) : content.slice(0, 1200);
  const docMatches = [...headerSlice.matchAll(/\/-[-!]?([\s\S]*?)-\//g)];
  if (docMatches.length > 0) {
    moduleDoc = docMatches.map((m) => cleanComment(m[0])).join('\n\n');
  }

  const decls = [];
  let pendingDoc = [];
  let inDoc = false;
  let currentDecl = null;

  const declRegex =
    /^(?:noncomputable\s+|private\s+|protected\s+)*(theorem|lemma|def|abbrev|inductive|structure)\s+([A-Za-z0-9_'.]+)/;

  function flushDecl(endLineIdx) {
    if (!currentDecl) return;
    while (endLineIdx > currentDecl.startLine - 1 && lines[endLineIdx - 1].trim() === '') {
      endLineIdx--;
    }
    const rawLines = lines.slice(currentDecl.startLine - 1, endLineIdx);
    const fullCode = rawLines.join('\n');

    let signature = '';
    if (currentDecl.kind === 'inductive' || currentDecl.kind === 'structure') {
      signature = rawLines.slice(0, Math.min(rawLines.length, 25)).join('\n');
    } else {
      const sigLines = [];
      for (const l of rawLines) {
        const byIdx = l.indexOf(':= by');
        if (byIdx !== -1) {
          sigLines.push(l.slice(0, byIdx).trimEnd());
          break;
        }
        const whereIdx = l.match(/\swhere\s*$/);
        if (whereIdx) {
          sigLines.push(l.slice(0, whereIdx.index).trimEnd());
          break;
        }
        const assignIdx = l.indexOf(' := ');
        if (assignIdx !== -1 && (currentDecl.kind === 'theorem' || currentDecl.kind === 'lemma')) {
          sigLines.push(l.slice(0, assignIdx).trimEnd());
          break;
        }
        sigLines.push(l);
        if (sigLines.length >= 10) break;
      }
      signature = sigLines.join('\n');
    }

    const keepFullModules = new Set([
      'Syntax',
      'Semantics',
      'Typing',
      'Invariant',
      'Panic',
      'Soundness',
      'Preservation',
      'Progress',
      'Defs',
      'Claim',
      'Make',
    ]);
    const maxLines = keepFullModules.has(modName) ? 110 : 40;
    let displayCode = fullCode;
    let truncated = false;
    if (rawLines.length > maxLines) {
      const head = rawLines.slice(0, maxLines - 5).join('\n');
      const tail = rawLines.slice(-3).join('\n');
      displayCode = `${head}\n  -- … [${rawLines.length - (maxLines - 2)} proof lines omitted in preview; see GitHub lines ${currentDecl.startLine}–${endLineIdx}] …\n${tail}`;
      truncated = true;
    }

    decls.push({
      id: `${phase}.${currentDecl.name}`,
      name: currentDecl.name,
      phase,
      module: modName,
      kind: currentDecl.kind,
      startLine: currentDecl.startLine,
      endLine: endLineIdx,
      lineCount: rawLines.length,
      doc: currentDecl.doc,
      signature,
      code: displayCode,
      truncated,
      _fullCode: fullCode,
    });
    currentDecl = null;
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    if (inDoc) {
      pendingDoc.push(line);
      if (trimmed.endsWith('-/')) {
        inDoc = false;
      }
      continue;
    }

    if (trimmed.startsWith('/--')) {
      flushDecl(i);
      pendingDoc = [line];
      if (!trimmed.endsWith('-/')) {
        inDoc = true;
      }
      continue;
    }

    if (
      trimmed.startsWith('/-!') ||
      trimmed.startsWith('end A1') ||
      trimmed.startsWith('end A2') ||
      trimmed.startsWith('end A3') ||
      trimmed === 'mutual' ||
      trimmed === 'end'
    ) {
      flushDecl(i);
      pendingDoc = [];
      continue;
    }

    const m = line.match(declRegex);
    if (m) {
      flushDecl(i);
      const kind = m[1] === 'lemma' ? 'theorem' : m[1];
      const name = m[2];
      const doc = pendingDoc.length > 0 ? cleanComment(pendingDoc.join('\n')) : '';
      pendingDoc = [];
      currentDecl = {
        kind,
        name,
        startLine: i + 1,
        doc,
      };
    } else if (trimmed !== '' && !trimmed.startsWith('--') && !currentDecl) {
      pendingDoc = [];
    }
  }
  flushDecl(lines.length);

  const layerTable = phase === 'A3' ? A3_MODULE_LAYERS : MODULE_LAYERS;
  const layerInfo = layerTable[modName] ?? {
    layer: 3,
    category: 'Proof Infrastructure',
    summaryEn: '',
  };

  return {
    id: `${phase}.${modName}`,
    name: modName,
    phase,
    path: `formal/${phase}/${modName}.lean`,
    lineCount: lines.length,
    imports: imports.filter((imp) => imp.startsWith(`${phase}.`)).map((imp) => imp.slice(phase.length + 1)),
    doc: moduleDoc,
    layer: layerInfo.layer,
    category: layerInfo.category,
    summaryEn: layerInfo.summaryEn,
    counts: {
      theorem: decls.filter((d) => d.kind === 'theorem').length,
      def: decls.filter((d) => d.kind === 'def' || d.kind === 'abbrev').length,
      inductive: decls.filter((d) => d.kind === 'inductive').length,
      structure: decls.filter((d) => d.kind === 'structure').length,
      total: decls.length,
    },
    decls,
  };
}

function buildPhaseData(phase) {
  const dir = join(FORMAL_DIR, phase);
  const files = readdirSync(dir)
    .filter((f) => f.endsWith('.lean'))
    .sort();

  const modules = files.map((f) => {
    const modName = f.replace(/\.lean$/, '');
    return parseLeanFile(phase, modName, join(dir, f));
  });

  const declByName = new Map();
  for (const mod of modules) {
    for (const d of mod.decls) {
      if (!declByName.has(d.name)) {
        declByName.set(d.name, d);
      }
    }
  }

  const identRegex = /[A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_']*)*/g;
  const usedByMap = new Map();
  for (const name of declByName.keys()) {
    usedByMap.set(name, new Set());
  }

  for (const mod of modules) {
    for (const d of mod.decls) {
      const refs = new Set();
      const matches = d._fullCode.match(identRegex) ?? [];
      for (const token of matches) {
        if (token === d.name) continue;
        if (declByName.has(token)) {
          refs.add(token);
        } else if (token.includes('.')) {
          const parts = token.split('.');
          const base = parts[0];
          if (base !== d.name && declByName.has(base)) {
            refs.add(base);
          }
        }
      }
      d.deps = [...refs].slice(0, 24);
      for (const r of d.deps) {
        usedByMap.get(r)?.add(d.name);
      }
      delete d._fullCode;
    }
  }

  for (const mod of modules) {
    for (const d of mod.decls) {
      d.usedBy = [...(usedByMap.get(d.name) ?? [])].slice(0, 24);
    }
  }

  return modules;
}

function parseRulesMd() {
  const content = readFileSync(join(FORMAL_DIR, 'RULES.md'), 'utf8');
  const lines = content.split('\n');
  const rules = [];
  for (const line of lines) {
    if (!line.startsWith('| §')) continue;
    const cells = line
      .split('|')
      .slice(1, -1)
      .map((c) => c.trim());
    if (cells.length >= 5) {
      rules.push({
        section: cells[0],
        rule: cells[1],
        phase: cells[2],
        formalRule: cells[3],
        status: cells[4],
      });
    }
  }
  return rules;
}

function parseHolesCorpus() {
  // The probe table, from the probes' own `// map:` lines: it is generated,
  // not committed (Agora #307), by the same script build.sh writes
  // formal/corpus/map.tsv with.
  const content = execFileSync('sh', [join(HOLES_DIR, 'map.sh')], { encoding: 'utf8', maxBuffer: 64 << 20 }).trim();
  const lines = content.split('\n').slice(1);
  return lines.map((line) => {
    // old_id: the hNNN number from before Agora #212, `-` for a newer probe.
    const [probe, rule, phase, note, nurlc, oldId] = line.split('\t');
    const nuPath = join(HOLES_DIR, `${probe}.nu`);
    let code = '';
    if (existsSync(nuPath)) {
      code = readFileSync(nuPath, 'utf8').trim();
    }
    return {
      probe,
      id: oldId && oldId !== '-' ? oldId : probe.split('/').pop(),
      rule,
      phase,
      note,
      nurlc,
      code,
    };
  });
}

const BLUEPRINT_NODES = [
  {
    id: 'Ty',
    name: 'Ty',
    module: 'Syntax',
    kind: 'inductive',
    tier: 0,
    titleEn: 'Types (Ty)',
    explainEn:
      'Models NURL memory-relevant types: scalars (.int), owned growable buffers (.vec t, including String), borrowed views (.slice t), inline structs (.prod a b), tagged enums/Option (.sum a b), closure/trait packages (.fn ms q), and shared blocks (.arc t, .lk t, .cell t).',
    deps: [],
  },
  {
    id: 'Eff',
    name: 'Eff',
    module: 'Syntax',
    kind: 'inductive',
    tier: 0,
    titleEn: 'Effect Lattice (Eff)',
    explainEn:
      'Orders container effects by what they invalidate: none (read) < realloc (vec_push may move buffer) < drop (vec_pop drops element) < replace (move, free, assignment, or scope exit).',
    deps: [],
  },
  {
    id: 'Eff.kills',
    name: 'Eff.kills',
    module: 'Syntax',
    kind: 'def',
    tier: 0,
    titleEn: 'Invalidation Rule (Eff.kills)',
    explainEn:
      'Exact truth table deciding when effect e on root r invalidates a dependency of kind k (self, inner, view, share, or name). For instance, realloc kills .view but preserves .inner.',
    deps: ['Eff', 'Ty'],
  },
  {
    id: 'Mem',
    name: 'Mem',
    module: 'Syntax',
    kind: 'structure',
    tier: 0,
    titleEn: 'Runtime Store (Mem & Slot)',
    explainEn:
      'Models runtime memory: allocated heap addresses (alloc : Nat → Bool), variable slots (st : Var → Option Slot) carrying ownership (own : Bool) and drop flag (val : Option Val), shared blocks (blk), and module globals (gl).',
    deps: ['Ty'],
  },
  {
    id: 'DropSlot',
    name: 'DropSlot',
    module: 'Semantics',
    kind: 'inductive',
    tier: 1,
    titleEn: 'Scope-Exit Drop (DropSlot & Frees)',
    explainEn:
      'When a scope exits normally (Step.scopeSkip) or unwinds on panic (Step.scopeP), an owning slot ⟨true, some tree⟩ recursively frees its entire tree; moved ⟨true, none⟩ or borrowed ⟨false, _⟩ slots are no-ops.',
    deps: ['Mem'],
  },
  {
    id: 'Step',
    name: 'Step',
    module: 'Semantics',
    kind: 'inductive',
    tier: 1,
    titleEn: 'Operational Step (Step & Stuck)',
    explainEn:
      'Small-step operational semantics. Every memory access or free checks that the address is allocated (m.alloc c = true). Any use-after-free, double-free, or dangling view access has no step rule and becomes Stuck.',
    deps: ['Mem', 'DropSlot'],
  },
  {
    id: 'kill',
    name: 'kill',
    module: 'Typing',
    kind: 'def',
    tier: 1,
    titleEn: 'Context Invalidation (kill & exitScope)',
    explainEn:
      'Updates typing context Γ: every binding whose borrow path or held views depend on root r with a kind killed by Eff.kills is marked dead (live := false).',
    deps: ['Eff.kills'],
  },
  {
    id: 'CallT',
    name: 'CallT',
    module: 'Typing',
    kind: 'structure',
    tier: 1,
    titleEn: 'Call & Summary Check (CallT & FnOK)',
    explainEn:
      'Enforces at call sites that sink and inout arguments are disjoint and not frozen (F), and computes return/argument dependencies from the callee summary (lends, rholds, outHolds).',
    deps: ['kill', 'Eff.kills'],
  },
  {
    id: 'StmtT',
    name: 'StmtT',
    module: 'Typing',
    kind: 'inductive',
    tier: 2,
    titleEn: 'Flow-Sensitive Typing (StmtT & RhsT)',
    explainEn:
      'Typechecks statement s from input context Γ to output context Δ (StmtT P Γ F s Δ). Every read requires live = true, every move kills its source, and every mutation applies kill.',
    deps: ['kill', 'CallT'],
  },
  {
    id: 'HeapOK',
    name: 'HeapOK',
    module: 'Invariant',
    kind: 'structure',
    tier: 2,
    titleEn: 'Single-Owner Disjoint Trees (HeapOK)',
    explainEn:
      'Guarantees that every node in an owned tree is allocated (m.alloc = true), appears at most once in the tree (Nodup), and no two owners share any address.',
    deps: ['Mem'],
  },
  {
    id: 'Covers',
    name: 'Covers',
    module: 'Invariant',
    kind: 'def',
    tier: 2,
    titleEn: 'No-Orphan-Allocation Invariant (Covers)',
    explainEn:
      'Every allocated heap address (m.alloc i = true) belongs to the owned tree of some live owner binding o in the store (i ∈ T.ids) or a live shared block. No allocation is ever orphaned.',
    deps: ['Mem', 'HeapOK'],
  },
  {
    id: 'Inv',
    name: 'Inv',
    module: 'Invariant',
    kind: 'structure',
    tier: 3,
    titleEn: 'Configuration Invariant (Inv m Γ F s)',
    explainEn:
      'Bridges compile-time context Γ and runtime store m: bundles HeapOK, Covers, and guarantees every live borrow and view in Γ resolves to a valid, in-bounds node in an owner tree.',
    deps: ['HeapOK', 'Covers', 'StmtT'],
  },
  {
    id: 'panic_unwind',
    name: 'panic_unwind',
    module: 'Panic',
    kind: 'theorem',
    tier: 3,
    titleEn: 'Panic Unwinding (panic_unwind)',
    explainEn:
      'Proves that when a panic unwinds the active scope spine (s.spine), every exited scope drops its owned trees while preserving both HeapOK and Covers.',
    deps: ['DropSlot', 'HeapOK', 'Covers'],
  },
  {
    id: 'callCase',
    name: 'callCase',
    module: 'CallInv',
    kind: 'theorem',
    tier: 3,
    titleEn: 'Function Call Soundness (callCase & recCase)',
    explainEn:
      'Proves that expanding a function call (or recover frame) with alpha-renamed body variables preserves both typing StmtT and the memory invariant Inv.',
    deps: ['Inv', 'CallT'],
  },
  {
    id: 'cloCase',
    name: 'cloCase',
    module: 'Closure',
    kind: 'theorem',
    tier: 3,
    titleEn: 'Closure & Trait Call Soundness (cloCase & cloProgress)',
    explainEn:
      'Proves that invoking a closure or trait-object package (Val.pkg) unpacks the owned environment and by-name captures safely within their effect bounds.',
    deps: ['Inv', 'CallT'],
  },
  {
    id: 'preserve',
    name: 'preserve',
    module: 'Preservation',
    kind: 'theorem',
    tier: 4,
    titleEn: 'Preservation Theorem (preserve)',
    explainEn:
      'If a configuration is well-typed (StmtT) and satisfies Inv, then after any normal step (Step P m s (.ok m\' s\')), the new configuration is well-typed in some Γ\' and satisfies Inv.',
    deps: ['Inv', 'callCase', 'cloCase', 'Step'],
  },
  {
    id: 'progress',
    name: 'progress',
    module: 'Progress',
    kind: 'theorem',
    tier: 4,
    titleEn: 'Progress Theorem (progress)',
    explainEn:
      'Every well-typed configuration satisfying Inv is either finished (s = .skip), blocked on a lock/channel (Blocked), or can take a step (∃ r, Step P m s r). It is never Stuck.',
    deps: ['Inv', 'Step', 'cloCase'],
  },
  {
    id: 'reach_ok',
    name: 'reach_ok',
    module: 'Soundness',
    kind: 'theorem',
    tier: 4,
    titleEn: 'Reachable State Invariant (reach_ok & reach_panic)',
    explainEn:
      'By induction over multi-step execution (Steps): every reachable normal state preserves Inv, and every uncaught panic unwinds the entire spine leaving an empty variable store.',
    deps: ['preserve', 'panic_unwind'],
  },
  {
    id: 'memory_safe',
    name: 'memory_safe',
    module: 'Soundness',
    kind: 'theorem',
    tier: 5,
    titleEn: 'Memory Safety Theorem (A2.memory_safe & A1.memory_safe)',
    explainEn:
      'MAIN THEOREM 1: Every well-typed source program run from the empty store (emptyMem) never reaches a stuck configuration (¬ Stuck P m\' s\') — zero use-after-free, double-free, or dangling view reads.',
    deps: ['reach_ok', 'progress'],
  },
  {
    id: 'no_leak_end',
    name: 'no_leak_end',
    module: 'Soundness',
    kind: 'theorem',
    tier: 5,
    titleEn: 'Zero Leaks on Normal Exit (A2.no_leak_end)',
    explainEn:
      'MAIN THEOREM 2: When a well-typed program finishes (.ok m\' .skip), every heap allocation it ever made has been freed: ∀ i, m\'.alloc i = false.',
    deps: ['reach_ok', 'Covers'],
  },
  {
    id: 'no_leak_panic',
    name: 'no_leak_panic',
    module: 'Soundness',
    kind: 'theorem',
    tier: 5,
    titleEn: 'Zero Leaks on Uncaught Panic (A2.no_leak_panic)',
    explainEn:
      'MAIN THEOREM 3: When a well-typed program terminates via an uncaught panic (.panic m\'), unwinding has freed every heap allocation: ∀ i, m\'.alloc i = false.',
    deps: ['reach_ok', 'panic_unwind', 'Covers'],
  },
];

const a1Modules = buildPhaseData('A1');
const a2Modules = buildPhaseData('A2');
const a3Modules = buildPhaseData('A3');
const rules = parseRulesMd();
const holes = parseHolesCorpus();

function summarizePhase(mods) {
  return {
    modules: mods.length,
    lines: mods.reduce((acc, m) => acc + m.lineCount, 0),
    theorems: mods.reduce((acc, m) => acc + m.counts.theorem, 0),
    defs: mods.reduce((acc, m) => acc + m.counts.def, 0),
    inductives: mods.reduce((acc, m) => acc + m.counts.inductive + m.counts.structure, 0),
    totalDecls: mods.reduce((acc, m) => acc + m.counts.total, 0),
  };
}

const stats = {
  leanToolchain: readFileSync(join(FORMAL_DIR, 'lean-toolchain'), 'utf8').trim(),
  axioms: ['propext', 'Classical.choice', 'Quot.sound'],
  sorryCount: 0,
  a1: summarizePhase(a1Modules),
  a2: summarizePhase(a2Modules),
  a3: summarizePhase(a3Modules),
  holesCount: holes.length,
  holesByPhase: {
    A1: holes.filter((h) => h.phase === 'A1').length,
    A2: holes.filter((h) => h.phase === 'A2').length,
    A3: holes.filter((h) => h.phase === 'A3').length,
    B: holes.filter((h) => h.phase === 'B').length,
  },
};

function stripModuleDecls(modules) {
  return modules.map(({ decls, ...rest }) => ({
    ...rest,
    declNames: decls.slice(0, 12).map((d) => d.name),
  }));
}

// Extract the landmark declarations from A2 and A3 for instant SSR rendering before formal-decls.json loads
const blueprintIds = new Set(BLUEPRINT_NODES.map((n) => n.name));
const initialDecls = {};
for (const mod of a2Modules) {
  for (const d of mod.decls) {
    if (blueprintIds.has(d.name) || mod.name === 'Soundness') {
      initialDecls[d.name] = d;
    }
  }
}
for (const mod of a3Modules) {
  if (mod.name === 'Claim' || mod.name === 'Make') {
    for (const d of mod.decls) {
      initialDecls[d.name] = d;
    }
  }
}

const tsPayload = {
  stats,
  blueprintNodes: BLUEPRINT_NODES,
  initialDecls,
  rules,
  holes,
  modules: {
    A3: stripModuleDecls(a3Modules),
    A2: stripModuleDecls(a2Modules),
    A1: stripModuleDecls(a1Modules),
  },
};

const jsonPayload = {
  A3: a3Modules,
  A2: a2Modules,
  A1: a1Modules,
};

const typesHeader = `// Generated by webdocs/scripts/gen-formal-data.mjs — do not edit by hand.

export interface FormalDecl {
  id: string;
  name: string;
  phase: 'A1' | 'A2' | 'A3';
  module: string;
  kind: 'theorem' | 'def' | 'abbrev' | 'inductive' | 'structure';
  startLine: number;
  endLine: number;
  lineCount: number;
  doc: string;
  signature: string;
  code: string;
  truncated: boolean;
  deps: string[];
  usedBy: string[];
}

export interface FormalModuleSummary {
  id: string;
  name: string;
  phase: 'A1' | 'A2' | 'A3';
  path: string;
  lineCount: number;
  imports: string[];
  doc: string;
  layer: number;
  category: string;
  summaryEn: string;
  counts: {
    theorem: number;
    def: number;
    inductive: number;
    structure: number;
    total: number;
  };
  declNames: string[];
}

export interface FormalModuleFull extends Omit<FormalModuleSummary, 'declNames'> {
  decls: FormalDecl[];
}

export interface BlueprintNode {
  id: string;
  name: string;
  module: string;
  kind: string;
  tier: number;
  titleEn: string;
  explainEn: string;
  deps: string[];
}

export interface FormalRuleRow {
  section: string;
  rule: string;
  phase: string;
  formalRule: string;
  status: string;
}

export interface HoleProbe {
  probe: string;
  id: string;
  rule: string;
  phase: string;
  note: string;
  nurlc: string;
  code: string;
}

export interface FormalData {
  stats: {
    leanToolchain: string;
    axioms: string[];
    sorryCount: number;
    a1: { modules: number; lines: number; theorems: number; defs: number; inductives: number; totalDecls: number };
    a2: { modules: number; lines: number; theorems: number; defs: number; inductives: number; totalDecls: number };
    a3: { modules: number; lines: number; theorems: number; defs: number; inductives: number; totalDecls: number };
    holesCount: number;
    holesByPhase: { A1: number; A2: number; A3: number; B: number };
  };
  blueprintNodes: BlueprintNode[];
  initialDecls: Record<string, FormalDecl>;
  rules: FormalRuleRow[];
  holes: HoleProbe[];
  modules: {
    A3: FormalModuleSummary[];
    A2: FormalModuleSummary[];
    A1: FormalModuleSummary[];
  };
}
`;

// ── formal/BLUEPRINT.md ─────────────────────────────────────────────
// Its counts, A2 module DAG, A2 module index and crown theorem statements
// come from the sources, so a formal PR never edits them by hand.

const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);

function bpHeadline(text, phase, st) {
  const re = new RegExp(
    `(\\* \\*\\*Phase ${phase} \\([^\\n]*?\\):\\*\\* )\\*\\*[\\d,]+ modules\\*\\*, \\*\\*[\\d,]+ lines of Lean 4\\*\\*, ` +
      `\\*\\*[\\d,]+ theorems\\*\\*, \\*\\*[\\d,]+ total declarations\\*\\*`,
  );
  if (!re.test(text)) throw new Error(`formal/BLUEPRINT.md: no Phase ${phase} headline to update`);
  return text.replace(
    re,
    `$1**${st.modules} modules**, **${st.lines.toLocaleString('en-US')} lines of Lean 4**, ` +
      `**${st.theorems} theorems**, **${st.totalDecls} total declarations**`,
  );
}

function bpRegion(text, name, body) {
  const begin = `<!-- BEGIN generated: ${name} (webdocs/scripts/gen-formal-data.mjs) -->`;
  const end = `<!-- END generated: ${name} -->`;
  const i = text.indexOf(begin);
  const j = text.indexOf(end);
  if (i < 0 || j < i) throw new Error(`formal/BLUEPRINT.md: the "${name}" markers are missing`);
  return `${text.slice(0, i + begin.length)}\n${body}\n${text.slice(j)}`;
}

function bpDag(mods) {
  const names = new Set(mods.map((m) => m.name));
  const sorted = [...mods].sort(byName);
  const out = [`## 4. Phase A2 Module Dependency DAG (${mods.length} Modules)`, '', '```mermaid', 'flowchart BT'];
  for (const m of sorted) out.push(`  ${m.name}["${m.name}<br/>(${m.lineCount}L, ${m.counts.theorem} thms)"]`);
  for (const m of sorted) for (const imp of m.imports) if (names.has(imp)) out.push(`  ${imp} --> ${m.name}`);
  out.push('```');
  return out.join('\n');
}

function bpIndex(mods) {
  const cat = (a, b) => (a.category < b.category ? -1 : a.category > b.category ? 1 : 0);
  const rows = [...mods].sort((a, b) => a.layer - b.layer || cat(a, b) || byName(a, b));
  const out = ['| Layer | Module | Lines | Theorems | Defs / Types | Summary |', '|---|---|---:|---:|---:|---|'];
  for (const m of rows) {
    const defs = m.counts.def + m.counts.inductive + m.counts.structure;
    const link = `[\`A2/${m.name}.lean\`](A2/${m.name}.lean)`;
    out.push(`| ${m.layer}. ${m.category} | ${link} | ${m.lineCount} | ${m.counts.theorem} | ${defs} | ${m.summaryEn} |`);
  }
  return out.join('\n');
}

// A crown theorem: its doc comment and statement (up to `:=`), with the
// line range they span.
function bpCrown() {
  const file = 'A2/Soundness.lean';
  const src = readFileSync(join(FORMAL_DIR, file), 'utf8').split('\n');
  const out = ['## 6. Crown Theorem Statements in Lean 4'];
  for (const name of ['memory_safe', 'no_leak_end', 'no_leak_panic']) {
    const t = src.findIndex((l) => l.startsWith(`theorem ${name} `));
    if (t < 0) throw new Error(`formal/${file}: no theorem ${name}`);
    let a = t;
    if (a > 0 && /-\/\s*$/.test(src[a - 1])) {
      a -= 1;
      while (a > 0 && !src[a].trimStart().startsWith('/--')) a -= 1;
    }
    let b = t;
    while (b < src.length - 1 && !/:=(\s*by)?\s*$/.test(src[b])) b += 1;
    const body = src.slice(a, b + 1);
    body[body.length - 1] = body[body.length - 1].replace(/\s*:=(\s*by)?\s*$/, '');
    const range = `L${a + 1}-L${b + 1}`;
    out.push('', `### \`A2.${name}\` ([\`${file}#${range}\`](${file}#${range}))`, '```lean', ...body, '```');
  }
  return out.join('\n');
}

let blueprint = readFileSync(BLUEPRINT_MD, 'utf8');
blueprint = bpHeadline(blueprint, 'A3', stats.a3);
blueprint = bpHeadline(blueprint, 'A2', stats.a2);
blueprint = bpHeadline(blueprint, 'A1', stats.a1);
blueprint = bpRegion(blueprint, 'A2 module DAG', bpDag(a2Modules));
blueprint = bpRegion(blueprint, 'A2 module index', bpIndex(a2Modules));
blueprint = bpRegion(blueprint, 'A2 crown theorems', bpCrown());

if (CHECK) {
  if (readFileSync(BLUEPRINT_MD, 'utf8') !== blueprint) {
    console.error(
      'formal/BLUEPRINT.md is not what the sources give: run `node webdocs/scripts/gen-formal-data.mjs` and commit it.',
    );
    process.exit(1);
  }
  console.log('gen-formal-data: formal/BLUEPRINT.md matches the sources');
  process.exit(0);
}

writeFileSync(OUTPUT_TS, `${typesHeader}\nexport const formalData: FormalData = ${JSON.stringify(tsPayload)};\n`);
writeFileSync(OUTPUT_JSON, JSON.stringify(jsonPayload));
writeFileSync(BLUEPRINT_MD, blueprint);

console.log(
  `formal data → ${OUTPUT_TS}, ${OUTPUT_JSON} & ${BLUEPRINT_MD}\n` +
    `  A3: ${stats.a3.modules} modules, ${stats.a3.lines.toLocaleString('en-US')} lines, ${stats.a3.theorems} theorems, ${stats.a3.totalDecls} total declarations\n` +
    `  A2: ${stats.a2.modules} modules, ${stats.a2.lines.toLocaleString('en-US')} lines, ${stats.a2.theorems} theorems, ${stats.a2.totalDecls} total declarations\n` +
    `  A1: ${stats.a1.modules} modules, ${stats.a1.lines.toLocaleString('en-US')} lines, ${stats.a1.theorems} theorems, ${stats.a1.totalDecls} total declarations\n` +
    `  Holes: ${stats.holesCount} soundness probes (A1=${stats.holesByPhase.A1}, A2=${stats.holesByPhase.A2}, A3=${stats.holesByPhase.A3}, B=${stats.holesByPhase.B})`
);
