import { llmsIndex } from '@/lib/agents';

export const revalidate = false;

export function GET() {
  return new Response(llmsIndex(), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
}
