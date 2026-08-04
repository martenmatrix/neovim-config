# AGENTS.md

## This repo is public / open source

This is a personal Neovim configuration published as an **open-source** repository. Treat everything here as world-readable.

## Do not commit confidential data from other codebases

Never add anything that is internal to any private, proprietary, or employer codebase. In particular:

- **No internal project, module, repo, or team names** (e.g. private product/codebase names).
- **No internal symbol, macro, header, or file names** copied from private source.
- **No internal build paths, scripts, or infrastructure details** (build layouts, internal tooling paths, CI, hostnames).
- **No secrets** — tokens, API keys, credentials, private URLs.
- **No proprietary code snippets** or logs from private repos.

## If a config detail needs a private codebase to explain

Generalize it. Describe the *pattern* with a neutral placeholder instead of the real thing:

- Use `<Module>-Swift.h`, `MyModule`, `<project>/build/...` rather than real names/paths.
- Explain the reasoning (e.g. "some Xcode-toolchain projects generate headers clangd can't parse") without naming the actual project.

The Neovim setup should be useful to anyone, not tied to one employer's internal repo.

## Before committing

Skim your diff for internal names, paths, and secrets. If in doubt, leave it out or generalize it.
