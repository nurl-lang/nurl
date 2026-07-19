import { source } from '@/lib/source';
import { DocsLayout } from 'fumadocs-ui/layouts/docs';
import { baseOptions } from '@/lib/layout.shared';
import { VersionBadges } from '@/components/version-badges';

export default function Layout({ children }: LayoutProps<'/docs'>) {
  return (
    <DocsLayout tree={source.getPageTree()} sidebar={{ footer: <VersionBadges /> }} {...baseOptions()}>
      {children}
    </DocsLayout>
  );
}
