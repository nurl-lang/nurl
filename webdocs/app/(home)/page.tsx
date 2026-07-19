import Link from 'next/link';
import { Cpu, Zap, Target } from 'lucide-react';
import { Card, Cards } from 'fumadocs-ui/components/card';
import { Pill } from '@/components/version-badges';
import { siteFacts } from '@/lib/site-facts';
import { gitConfig } from '@/lib/shared';

const features = [
  {
    icon: Cpu,
    title: 'Designed for LLMs',
    description:
      "Every operator takes a fixed number of arguments. There are no infix operators or precedence rules. Only about 50 grammar rules, NURL is simple for both humans and AI to parse.",
  },
  {
    icon: Zap,
    title: 'LLVM Native Performance',
    description:
      'Compile to optimized native binaries through LLVM with support for Linux, Windows, macOS, WebAssembly, ARM64, RISC-V, and embedded targets.',
  },
  {
    icon: Target,
    title: 'Deterministic Compiler',
    description:
      "NURL's compiler is designed to produce reproducible builds. Given the same source code, compiler version, and target, you'll get identical output every time.",
  },
];

export default function HomePage() {
  return (
    <main className="flex flex-1 flex-col">
      <section className="flex flex-col items-center gap-6 px-6 py-24 text-center">
        <img src="/graphics/nurl1c.svg" alt="NURL" className="h-20 w-20" />
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">NURL</h1>
        <Pill href={`https://github.com/${gitConfig.user}/${gitConfig.repo}/blob/${gitConfig.branch}/CHANGELOG.md`}>
          NURL {siteFacts.nurlVersion}
        </Pill>
        <p className="max-w-2xl text-fd-muted-foreground text-lg">
          A compiled language without a virtual machine, garbage collector, or
          interpreter — designed as a target for LLM code generation, with
          deterministic builds and native LLVM performance.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-4">
          <Link
            href="/docs"
            className="rounded-full bg-fd-primary px-6 py-2.5 font-medium text-fd-primary-foreground transition-opacity hover:opacity-90"
          >
            Start with NURL
          </Link>
          <a
            href="https://play.nurl-lang.org/"
            target="_blank"
            rel="noreferrer noopener"
            className="rounded-full border px-6 py-2.5 font-medium transition-colors hover:bg-fd-accent"
          >
            Open Playground
          </a>
        </div>
      </section>

      <section className="mx-auto w-full max-w-4xl px-6 pb-24">
        <Cards className="sm:grid-cols-3">
          {features.map(({ icon: Icon, title, description }) => (
            <Card key={title} icon={<Icon />} title={title} description={description} />
          ))}
        </Cards>
      </section>
    </main>
  );
}
