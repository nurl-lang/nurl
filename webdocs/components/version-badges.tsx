import type { ReactNode } from 'react';
import { docsCommit, nurlVersion } from '@/lib/release-facts.generated';
import { gitConfig } from '@/lib/shared';

export function Pill({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer noopener"
      className="inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-medium text-fd-muted-foreground transition-colors hover:bg-fd-accent hover:text-fd-accent-foreground"
    >
      {children}
    </a>
  );
}

export function VersionBadges() {
  const repoUrl = `https://github.com/${gitConfig.user}/${gitConfig.repo}`;

  return (
    <div className="m-2 flex flex-wrap items-center gap-2 justify-between">
      <Pill href={`${repoUrl}/blob/${gitConfig.branch}/CHANGELOG.md`}>
        NURL {nurlVersion}
      </Pill>
      <Pill href={`${repoUrl}/commit/${docsCommit}`}>docs {docsCommit}</Pill>
    </div>
  );
}
