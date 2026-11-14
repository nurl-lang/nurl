// The homepage's prose, shared by the HTML page (app/(home)/page.tsx) and
// its Markdown twin (lib/agents.ts → /index.md), so the lists and examples
// an agent reads are the ones a visitor sees.
import { Bot, Code2, Cpu, GitBranch, Rocket, ShieldCheck } from 'lucide-react';
import { repoUrl } from './shared';

export const tagline =
  'A compiled language without a virtual machine, garbage collector, or interpreter — designed as a target for LLM code generation, with deterministic builds and native LLVM performance.';

export const addExample = `@ add i a i b → i { ^ + a b }

( add 3 4 )     // → 7`;

export const fizzBuzzExample = `: ~ i i 1
~ <= i 100 {
    ? == 0 % i 15 { ( nurl_print \`FizzBuzz\\n\` ) }
    ? == 0 % i 3  { ( nurl_print \`Fizz\\n\` ) }
    ? == 0 % i 5  { ( nurl_print \`Buzz\\n\` ) }
    { ( nurl_println_int i ) }
    = i + i 1
}`;

export const features = [
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
    description: 'Values auto-drop at scope exit. Borrow checking, an explicit unsafe/raw boundary, and a mechanized Lean 4 proof (formal/) guarantee memory safety.',
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

export const projects = [
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

export const packages = ['nurllama', 'whisper', 'onnx', 'tensor', 'grad', 'yoloe', 'nwasm', 'image', 'nq'];

