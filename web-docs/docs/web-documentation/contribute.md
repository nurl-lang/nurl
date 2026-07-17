---
outline: deep
title: Contributing
---

# Contribute to documentation

- The web documentation is powered by VitePress.
- All of the nurl documentation is located under `/web-documentation/docs/nurl`

You can freely contribute to the web documentation with following rules:

- Follow the main [CONTRIBUTING.md](https://github.com/nurl-lang/nurl/blob/main/CONTRIBUTING.md) ruleset
- Web documentation differs from the repository one with being primarily managed **by hand**. The repository documentation changes rapidly due to the project early-state nature, with future automation implementations in mind.
- The goal of the web documentation is to be a simple to understand and broad by content, while repository one is minimal and technical.
- AI usage for **web documentation** contributions is **allowed with limitations.** The developer takes the full responsibility of the commit if AI is used. You must transparently disclose any use of automation in the pull request, including but not limited to LLM‐based AI tools.
- If low-quality or misleading information is contributed the developers have full allowance to discard all your future contributions.

## How To

Below I'll explain a simple way to make edits and additions.

1. Fork & Clone the nurl repository
2. Set the upstream repository:
   ```bash
   git remote add upstream git@github.com:nurl-lang/nurl.git
   ```
3. Create a new branch from the main:
   ```bash
   # Have the latest upstream changes
   git fetch upstream

   # Create and switch to a new branch
   git switch --create webdocs-update-describechange upstream/main
   ```
4. Do desired changes
5. Commit with the following message structure: `web docs: changedescribedhere`
6. Push your commits to your fork:
   ```bash
   git push --set-upstream origin HEAD
   ```
7. Create a pull request.
