import { defineConfig, UserConfig } from "vitepress";
import { withSidebar } from "vitepress-sidebar";

const vitePressSidebarOptions = {
  documentRootPath: "./docs",
  useTitleFromFrontmatter: true,
  useFolderTitleFromIndexFile: true,
  hyphenToSpace: true,
  capitalizeFirst: true,
  sortMenusByFrontmatterOrder: true,
  excludeByGlobPattern: ["localdraft/**"],
};

const vitePressOptions: UserConfig = {
  markdown: {
    typographer: true, // Enables smart quotes, replacements, and other typography rules
  },
  lastUpdated: true,
  srcDir: "docs",
  srcExclude: ["localdraft/**"],
  head: [["link", { rel: "icon", href: "/graphics/nurl1c.svg" }]],
  cleanUrls: true,
  title: "NURL Official Documentation",
  description:
    "Web documentation for Neural Unified Representation Language aka NURL.",
  themeConfig: {
    logo: "/graphics/nurlfullc.svg",
    siteTitle: 'Documentation',
    search: {
      provider: "local",
    },
    externalLinkIcon: true,
    nav: [],
    socialLinks: [
      {
        icon: "github",
        link: "https://github.com/nurl-lang/nurl/",
      },
    ],
    footer: {
      message: "NURL is dual-licensed under MIT or Apache-2.0, at your option.",
      copyright: "Copyright © 2026 The NURL Project Developers.",
    },
  },
};

export default defineConfig(
  withSidebar(vitePressOptions, vitePressSidebarOptions),
);
