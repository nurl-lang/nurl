import { homeMarkdown } from '@/lib/agents';

// The homepage as Markdown: what `/` answers to `Accept: text/markdown`
// (worker/index.ts), and linked from /llms.txt.
export const revalidate = false;

export function GET() {
  return new Response(homeMarkdown(), { headers: { 'Content-Type': 'text/markdown; charset=utf-8' } });
}
