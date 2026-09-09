import Link from 'next/link';
import type { ReactNode } from 'react';
import { Bot, Code2, Cpu, GitBranch, Package, Rocket, ShieldCheck, Terminal } from 'lucide-react';
import { Pill } from '@/components/version-badges';
import { benchmarkStats } from '@/lib/benchmark-stats.generated';
import { contributors } from '@/lib/contributors.generated';
import { releaseFacts } from '@/lib/release-facts.generated';
import { siteFacts } from '@/lib/site-facts';
import { gitConfig } from '@/lib/shared';

const repoUrl = `https://github.com/${gitConfig.user}/${gitConfig.repo}`;

const features = [
  {
    icon: Bot,
    title: 'Regular prefix-arity grammar',
    description: 'Every operator has a fixed arity. There is no infix syntax or precedence table.',
  },
  {
    icon: Code2,
    title: 'Local semantics',
    description: 'A token’s meaning depends on a short span of preceding tokens.',
  },
  {
    icon: ShieldCheck,
    title: 'Single-owner memory',
    description: 'Values drop at scope exit. Borrow checking rejects use-after-move, double-free aliases, and escaping captures.',
  },
  {
    icon: GitBranch,
    title: 'Deterministic compiler',
    description: 'Bootstrap compiles the compiler twice and requires identical LLVM IR from both runs.',
  },
  {
    icon: Cpu,
    title: 'LLVM-backed',
    description: 'One LLVM pipeline targets desktops, servers, WebAssembly, RISC-V, and embedded systems.',
  },
  {
    icon: Rocket,
    title: 'Self-hosting',
    description: 'The compiler is written in NURL and builds itself from source.',
  },
];

const projects = [
  {
    title: 'The compiler itself',
    description: 'A self-hosting compiler that produces identical LLVM IR in two compilation rounds.',
    href: `${repoUrl}/blob/main/compiler/nurlc.nu`,
  },
  {
    title: 'A Game Boy emulator',
    description: 'A complete DMG emulator compiled to WebAssembly for the browser.',
    href: 'https://play.nurl-lang.org/gameboydemo',
  },
  {
    title: 'The playground backend',
    description: 'NURL serves the playground, build service, MCP endpoint, and package registry.',
    href: `${repoUrl}/tree/main/nurlapi`,
  },
  {
    title: 'Examples',
    description: 'Examples include Game of Life, HTTP/2, MCP servers, agents, and embedded targets.',
    href: `${repoUrl}/tree/main/examples`,
  },
];

const packages = ['nurllama', 'whisper', 'onnx', 'tensor', 'grad', 'yoloe', 'nwasm', 'image', 'nq'];

function ExternalLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="font-medium text-fd-primary hover:underline">
      {children}
    </a>
  );
}

export default function HomePage() {
  return (
    <main className="nurl-home flex flex-1 flex-col">
      <section className="border-b bg-gradient-to-b from-fd-muted to-fd-background px-6 py-20 text-center sm:py-28">
        <div className="mx-auto flex max-w-4xl flex-col items-center">
          <img src="/graphics/nurl1c.svg" alt="NURL" className="mb-6 h-24 w-24" />
          <h1 className="text-4xl font-bold tracking-tight sm:text-6xl">NURL</h1>
          <div className="mt-4">
            <Pill href={`${repoUrl}/blob/${gitConfig.branch}/CHANGELOG.md`}>{siteFacts.nurlVersion}</Pill>
          </div>
          <p className="mt-6 max-w-2xl text-lg text-fd-muted-foreground">
            A compiled language without a virtual machine, garbage collector, or interpreter — designed as a target for LLM code generation, with deterministic builds and native LLVM performance.
          </p>
          <div className="mt-8 flex flex-wrap justify-center gap-4">
            <Link
              href="/docs"
              className="w-full rounded-full bg-fd-primary px-6 py-2.5 font-medium text-fd-primary-foreground transition-opacity hover:opacity-90 sm:w-auto"
            >
              Start with NURL
            </Link>
            <a
              href="https://play.nurl-lang.org"
              target="_blank"
              rel="noreferrer"
              className="w-full rounded-full border px-6 py-2.5 font-medium transition-opacity hover:bg-fd-accent sm:w-auto"
            >
              Open Playground
            </a>
          </div>
          <div className="mt-8 w-full max-w-3xl rounded-lg border bg-fd-card p-2">
            <div className="grid grid-cols-1 divide-y text-center sm:grid-cols-5 sm:divide-x sm:divide-y-0">
              {releaseFacts.map(([value, label]) => (
                <div key={label} className="min-w-0 px-2 py-2.5 sm:px-3">
                  <strong className="block text-lg leading-tight font-semibold text-fd-foreground sm:text-xl">{value}</strong>
                  <span className="mt-1 block break-words text-xs leading-tight text-fd-foreground/70">{label}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="mt-6 flex flex-wrap items-center justify-center gap-3 text-sm text-fd-muted-foreground">
            <span>Contributors</span>
            {contributors.map(({ name, login }) => (
              <a key={login} href={`https://github.com/${login}`} target="_blank" rel="noreferrer" className="flex items-center gap-2 font-medium text-fd-foreground hover:text-fd-primary">
                <img src={`https://github.com/${login}.png?size=80`} alt="" className="size-8 rounded-full border" />
                {name}
              </a>
            ))}
          </div>
        </div>
      </section>

      <section id="why" className="mx-auto w-full max-w-6xl px-6 py-16">
        <p className="text-sm font-medium text-fd-primary">WHY NURL</p>
        <h2 className="mt-2 text-3xl font-bold tracking-tight">Built for generated code</h2>
        <p className="mt-4 max-w-3xl text-fd-muted-foreground">
          NURL keeps generated code easy to parse. Fixed arity removes precedence ambiguity, short dependency windows limit context, and the grammar fits on one page.
        </p>
        <div className="mt-8 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {features.map(({ icon: Icon, title, description }) => (
            <article key={title} className="rounded-xl border bg-fd-card p-5">
              <Icon className="mb-4 size-6 text-fd-primary" />
              <h3 className="font-semibold">{title}</h3>
              <p className="mt-2 text-sm text-fd-muted-foreground">{description}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="syntax" className="border-y bg-fd-muted px-6 py-16">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-fd-primary">SYNTAX</p>
          <h2 className="mt-2 text-3xl font-bold tracking-tight">Prefix notation, end to end</h2>
          <p className="mt-4 max-w-3xl text-fd-muted-foreground">NURL uses <code>OP ARG1 ARG2 …</code>. There is no operator precedence or infix syntax.</p>
          <div className="mt-8 grid gap-4 lg:grid-cols-2">
            <article className="overflow-hidden rounded-xl border bg-fd-card">
              <p className="border-b px-4 py-3 text-sm font-medium">Add two integers</p>
              <pre className="overflow-x-auto p-4 text-sm"><code>{`@ add i a i b → i { ^ + a b }

( add 3 4 )     // → 7`}</code></pre>
            </article>
            <article className="overflow-hidden rounded-xl border bg-fd-card">
              <p className="border-b px-4 py-3 text-sm font-medium">FizzBuzz</p>
              <pre className="overflow-x-auto p-4 text-sm"><code>{`: ~ i i 1
~ <= i 100 {
    ? == 0 % i 15 { ( nurl_print \`FizzBuzz\\n\` ) }
    ? == 0 % i 3  { ( nurl_print \`Fizz\\n\` ) }
    ? == 0 % i 5  { ( nurl_print \`Buzz\\n\` ) }
    { ( nurl_println_int i ) }
    = i + i 1
}`}</code></pre>
            </article>
          </div>
          <p className="mt-6 text-sm text-fd-muted-foreground">See the <Link href="/docs/cheat-sheet" className="font-medium text-fd-primary hover:underline">language reference</Link> for generics, traits, pattern matching, errors, channels, compile-time evaluation, and async runtime support.</p>
        </div>
      </section>

      <section id="bench" className="mx-auto w-full max-w-6xl px-6 py-16">
        <p className="text-sm font-medium text-fd-primary">BENCHMARKS</p>
        <h2 className="mt-2 text-3xl font-bold tracking-tight">Measured runtime performance</h2>
        <p className="mt-4 max-w-3xl text-fd-muted-foreground">
          {benchmarkStats.benchmarks} verified benchmarks compare NURL with C, Rust, Node, and Python. Each implementation must produce the same output before timing.
        </p>
        <div className="mt-6 flex flex-wrap items-center gap-x-5 gap-y-2 rounded-lg border bg-fd-card px-4 py-3 text-sm text-fd-foreground/70">
          <span>{benchmarkStats.languages} languages</span>
          <span>{benchmarkStats.host}</span>
          <span>Measured {benchmarkStats.generated}</span>
          <ExternalLink href={`${repoUrl}/tree/main/bench`}>Benchmark sources →</ExternalLink>
          {benchmarkStats.runUrl && <ExternalLink href={benchmarkStats.runUrl}>CI run →</ExternalLink>}
        </div>
        <div className="mt-4 overflow-x-auto rounded-lg border bg-fd-card">
          <table className="w-full min-w-[640px] text-left text-sm">
            <caption className="sr-only">Benchmark runtime in milliseconds; lower is better.</caption>
            <thead className="border-b bg-fd-muted text-xs text-fd-foreground/70">
              <tr>
                <th scope="col" className="px-4 py-3 font-medium">Benchmark</th>
                {benchmarkStats.columns.map((column) => (
                  <th key={column.label} scope="col" className={`px-3 py-3 text-center font-medium ${column.nurl ? 'text-fd-primary' : ''}`}>{column.label}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y">
              {benchmarkStats.rows.map((row) => (
                <tr key={row.name}>
                  <td className="px-4 py-3"><code className="font-medium">{row.name}</code><span className="mt-1 block text-xs text-fd-muted-foreground">{row.blurb}</span></td>
                  {row.values.map((value, index) => {
                    const column = benchmarkStats.columns[index];
                    const nurlWin = column.nurl && row.nurlWins;
                    return <td key={column.label} className={`px-3 py-3 text-center tabular-nums ${nurlWin ? 'bg-fd-primary/10 font-semibold text-fd-primary' : column.nurl ? 'font-medium' : ''}`}>{value}</td>;
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-3 text-xs text-fd-muted-foreground">Median wall-clock time for the full process. Lower is better. NURL is highlighted only when its displayed time is lower than every other displayed time.</p>
      </section>

      <section id="start" className="mx-auto w-full max-w-6xl px-6 py-16">
        <p className="text-sm font-medium text-fd-primary">GET STARTED</p>
        <h2 className="mt-2 text-3xl font-bold tracking-tight">Start with NURL</h2>
        <div className="mt-8 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          <article className="rounded-xl border p-5"><Rocket className="mb-4 size-6 text-fd-primary" /><h3 className="font-semibold">Try it in the browser</h3><p className="mt-2 text-sm text-fd-muted-foreground">Write, build, and run NURL in your browser.</p><ExternalLink href="https://play.nurl-lang.org">Open the Playground →</ExternalLink></article>
          <article className="rounded-xl border p-5"><Terminal className="mb-4 size-6 text-fd-primary" /><h3 className="font-semibold">Install a release</h3><pre className="mt-3 overflow-x-auto rounded bg-fd-muted p-3 text-xs"><code>{`curl -fsSL https://nurl-lang.org/install.sh | sh\nirm https://nurl-lang.org/install.ps1 | iex`}</code></pre><Link href="/docs/install" className="text-sm font-medium text-fd-primary hover:underline">Install guide →</Link></article>
          <article className="rounded-xl border p-5"><Code2 className="mb-4 size-6 text-fd-primary" /><h3 className="font-semibold">Build from source</h3><pre className="mt-3 overflow-x-auto rounded bg-fd-muted p-3 text-xs"><code>{`git clone ${repoUrl}\ncd nurl && ./build.sh`}</code></pre><ExternalLink href={repoUrl}>View the repository →</ExternalLink></article>
          <article className="rounded-xl border p-5"><GitBranch className="mb-4 size-6 text-fd-primary" /><h3 className="font-semibold">Editor support</h3><p className="mt-2 text-sm text-fd-muted-foreground">The VS Code extension also works in Cursor and Windsurf, with diagnostics, completion, and formatting.</p><Link href="/docs/editor-and-tooling" className="text-sm font-medium text-fd-primary hover:underline">Editor guide →</Link></article>
        </div>
      </section>

      <section id="targets" className="border-y bg-fd-muted px-6 py-16">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-fd-primary">TARGETS</p>
          <h2 className="mt-2 text-3xl font-bold tracking-tight">One LLVM pipeline across targets</h2>
          <p className="mt-4 max-w-3xl text-fd-muted-foreground">The compiler emits target-agnostic LLVM IR for desktop, server, browser, unikernel, and embedded targets.</p>
          <div className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {['Linux, Windows, macOS, and FreeBSD', 'WebAssembly in the browser', 'ARM64 and RISC-V Linux', 'Unikernels on x64, ARM64, and RISC-V', 'Milk-V Duo on-device', 'ESP32 Xtensa and ESP32-C3/C6'].map((target) => (
              <div key={target} className="rounded-lg border bg-fd-card px-4 py-3 text-sm font-medium">{target}</div>
            ))}
          </div>
          <div className="mt-6 grid gap-4 text-sm text-fd-muted-foreground md:grid-cols-3">
            <p><strong className="text-fd-foreground">Embedded hardware.</strong> NURL runs an HTTP file server on the Milk-V Duo and drives ESP32 GPIO through memory-mapped registers.</p>
            <p><strong className="text-fd-foreground">Browser builds.</strong> The playground compiles to wasm32-wasi in your tab and can cross-compile downloadable native binaries.</p>
            <p><strong className="text-fd-foreground">Bootable programs.</strong> The unikernel path links NURL programs without a host OS for x64, ARM64, and RISC-V targets.</p>
          </div>
        </div>
      </section>

      <section id="stdlib" className="mx-auto w-full max-w-6xl px-6 py-16">
        <p className="text-sm font-medium text-fd-primary">STANDARD LIBRARY</p>
        <h2 className="mt-2 text-3xl font-bold tracking-tight">{releaseFacts[2][0]} modules, included with the toolchain</h2>
        <p className="mt-4 max-w-3xl text-fd-muted-foreground">The standard library is plain NURL source: core types, general-purpose modules, and optional higher-level integrations.</p>
        <div className="mt-8 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <article className="rounded-xl border p-5"><h3 className="font-semibold">Network</h3><p className="mt-2 text-sm text-fd-muted-foreground">TCP, UDP, TLS, HTTP/1.1, HTTP/2, WebSocket, MQTT, SMTP, and peer-to-peer networking.</p></article>
          <article className="rounded-xl border p-5"><h3 className="font-semibold">Data</h3><p className="mt-2 text-sm text-fd-muted-foreground">JSON, TOML, YAML, XML, MessagePack, CBOR, CSV, PostgreSQL, and SQLite.</p></article>
          <article className="rounded-xl border p-5"><h3 className="font-semibold">Concurrency</h3><p className="mt-2 text-sm text-fd-muted-foreground">Threads, mutexes, channels, atomics, and a stackful M:N async runtime.</p></article>
          <article className="rounded-xl border p-5"><h3 className="font-semibold">Core</h3><p className="mt-2 text-sm text-fd-muted-foreground">Collections, arbitrary-precision numbers, regex, crypto, compression, UUIDs, paths, and processes.</p></article>
          <article className="rounded-xl border p-5"><h3 className="font-semibold">AI and MCP</h3><p className="mt-2 text-sm text-fd-muted-foreground">Anthropic API support plus MCP clients, servers, sessions, and registries.</p></article>
          <article className="rounded-xl border p-5"><h3 className="font-semibold">Tooling</h3><p className="mt-2 text-sm text-fd-muted-foreground">LSP, formatter, documentation tools, test and benchmark runners, and a differential fuzzer.</p></article>
        </div>
        <Link href="/docs/standard-library" className="mt-6 inline-flex font-medium text-fd-primary hover:underline">Browse the standard library →</Link>
      </section>

      <section id="projects" className="mx-auto w-full max-w-6xl px-6 py-16">
        <p className="text-sm font-medium text-fd-primary">PROJECTS</p>
        <h2 className="mt-2 text-3xl font-bold tracking-tight">NURL projects</h2>
        <div className="mt-8 grid gap-4 md:grid-cols-2">
          {projects.map(({ title, description, href }) => (
            <article key={title} className="rounded-xl border p-5"><h3 className="font-semibold">{title}</h3><p className="mt-2 text-sm text-fd-muted-foreground">{description}</p><ExternalLink href={href}>Explore →</ExternalLink></article>
          ))}
        </div>
      </section>

      <section id="packages" className="border-y bg-fd-muted px-6 py-16">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-fd-primary">PACKAGES</p>
          <h2 className="mt-2 text-3xl font-bold tracking-tight">Packages, one command away</h2>
          <p className="mt-4 max-w-3xl text-fd-muted-foreground">The registry supports semver ranges, reproducible lockfiles, and signed tarballs verified by <code>nurlpkg</code> before unpacking.</p>
          <div className="mt-6 grid gap-4 lg:grid-cols-[1fr_2fr]">
            <article className="rounded-xl border bg-fd-card p-5"><Package className="mb-4 size-6 text-fd-primary" /><pre className="overflow-x-auto rounded bg-fd-muted p-3 text-sm"><code>{`nurlpkg search whisper
nurlpkg install nq
nurlpkg add tensor
nurlpkg publish`}</code></pre><ExternalLink href="https://reg.nurl-lang.org">Browse the registry →</ExternalLink></article>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              {packages.map((name) => <div key={name} className="rounded-lg border bg-fd-card px-4 py-3 font-mono text-sm">{name}</div>)}
            </div>
          </div>
        </div>
      </section>

      <section id="mcp" className="mx-auto w-full max-w-6xl px-6 py-16">
        <p className="text-sm font-medium text-fd-primary">MCP SERVER</p>
        <h2 className="mt-2 text-3xl font-bold tracking-tight">NURL tools for agents</h2>
        <p className="mt-4 max-w-3xl text-fd-muted-foreground">Connect an MCP client to build, run, and cross-compile NURL without a local toolchain.</p>
        <pre className="mt-6 overflow-x-auto rounded-xl border bg-fd-muted p-4 text-sm"><code>claude mcp add --transport http nurl https://play.nurl-lang.org/mcp</code></pre>
        <Link href="/docs/playground-ai" className="mt-4 inline-flex font-medium text-fd-primary hover:underline">Read the MCP setup guide →</Link>
      </section>

      <section id="resources" className="border-t bg-fd-muted px-6 py-16">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-fd-primary">REFERENCES</p>
          <h2 className="mt-2 text-3xl font-bold tracking-tight">Source, specification, and release history</h2>
          <div className="mt-8 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            <article className="rounded-xl border bg-fd-card p-5"><h3 className="font-semibold">Documentation</h3><p className="mt-2 text-sm text-fd-muted-foreground">Guides and language reference for installing, writing, and running NURL.</p><Link href="/docs" className="font-medium text-fd-primary hover:underline">Read the docs →</Link></article>
            <article className="rounded-xl border bg-fd-card p-5"><h3 className="font-semibold">README</h3><p className="mt-2 text-sm text-fd-muted-foreground">A repository overview of the language, runtime, and build pipeline.</p><ExternalLink href={`${repoUrl}#readme`}>Open README →</ExternalLink></article>
            <article className="rounded-xl border bg-fd-card p-5"><h3 className="font-semibold">Formal grammar</h3><p className="mt-2 text-sm text-fd-muted-foreground">The versioned EBNF grammar and historical snapshots.</p><ExternalLink href={`${repoUrl}/tree/main/spec`}>Open grammar →</ExternalLink></article>
            <article className="rounded-xl border bg-fd-card p-5"><h3 className="font-semibold">Changelog</h3><p className="mt-2 text-sm text-fd-muted-foreground">A release-by-release record of changes.</p><ExternalLink href={`${repoUrl}/blob/main/CHANGELOG.md`}>Read changelog →</ExternalLink></article>
            <article className="rounded-xl border bg-fd-card p-5"><h3 className="font-semibold">Roadmap</h3><p className="mt-2 text-sm text-fd-muted-foreground">Current work and plans toward 1.0.</p><ExternalLink href={`${repoUrl}/blob/main/ROADMAP.md`}>Read roadmap →</ExternalLink></article>
            <article className="rounded-xl border bg-fd-card p-5"><h3 className="font-semibold">Package registry</h3><p className="mt-2 text-sm text-fd-muted-foreground">Browse packages, source, and generated API documentation.</p><ExternalLink href="https://reg.nurl-lang.org">Open registry →</ExternalLink></article>
          </div>
        </div>
      </section>

      <footer className="border-t px-6 py-10 text-center text-sm text-fd-muted-foreground">
        <div className="flex flex-wrap justify-center gap-x-5 gap-y-2">
          <Link href="/docs" className="hover:text-fd-foreground">Documentation</Link>
          <ExternalLink href={repoUrl}>GitHub</ExternalLink>
          <ExternalLink href="https://play.nurl-lang.org">Playground</ExternalLink>
          <ExternalLink href="https://reg.nurl-lang.org">Package registry</ExternalLink>
          <ExternalLink href={`${repoUrl}/blob/main/CHANGELOG.md`}>Changelog</ExternalLink>
          <ExternalLink href={`${repoUrl}/blob/main/ROADMAP.md`}>Roadmap</ExternalLink>
        </div>
        <p className="mt-4">Dual-licensed MIT / Apache-2.0</p>
      </footer>
    </main>
  );
}
