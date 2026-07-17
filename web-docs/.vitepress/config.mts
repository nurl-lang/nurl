import { defineConfig, UserConfig } from "vitepress";
import { withSidebar } from "vitepress-sidebar";

const vitePressSidebarOptions = {
  documentRootPath: "./docs",
  useTitleFromFrontmatter: true,
  useFolderTitleFromIndexFile: true,
  hyphenToSpace: true,
  capitalizeFirst: true,
};

const vitePressOptions: UserConfig = {
  markdown: {
    typographer: true, // Enables smart quotes, replacements, and other typography rules
  },
  lastUpdated: true,
  srcDir: "docs",
  head: [["link", { rel: "icon", href: "/favicon.svg" }]],
  title: "NURL Official Documentation",
  description:
    "Web documentation for Neural Unified Representation Language aka NURL.",
  themeConfig: {
    logo: "./favicon.svg",
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
