---
name: nomimono
description: >
  How to work in a repo built on nomimono (formerly monomono), the monorepo contract package:
  the `just` door and its grammar, buck2 targets and the @nomimono// cell, the AGENTS.md contract,
  the Gherkin spec-first lifecycle (project, spec, lock, implement, green), and where work goes.
  Use when setting up a monorepo, running or adding `just` recipes, writing BUCK targets or
  lua_library/lua_test rules, adding a package, toolchain, area or submodule, working under
  context/projects (features, bdd, PROJECT.md, feature.md), running `just mono update` or a
  migration, or whenever the user mentions nomimono, monomono, mono.toml, mono.just or
  packages/nomimono.
---

# nomimono

🍶 nomimono (飲み物, "a drink") is a monorepo contract delivered as a versioned package. A consumer
repo attaches it at `packages/nomimono` (a git submodule pinned to a tag, or a vendored copy),
imports `packages/nomimono/mono.just` from its root `justfile`, and gets four things: a `just` door,
a buck2 build graph, an `AGENTS.md` contract, and a spec-first lifecycle. It assumes no language,
vendor or domain. Before 0.5.0 it was called monomono and lived at `packages/monomono`.

Names that stayed `mono` on purpose: the `just mono <verb>` recipe, the `MONO_*` environment
variables (`MONO_ROOT`, `MONO_HOME`, `MONO_DOC_MAX_LINES`, ...) and the files `mono.toml` and `mono.just`.

## First moves in a consumer repo

1. If root `AGENTS.md` is missing, run `just agents sync` (it links `AGENTS.md -> .agents/AGENTS.md`
   and generates `.agents/skills`).
2. Read root `AGENTS.md`, then the nested `AGENTS.md` of any tree before editing it. The repo's own
   rules win where they are stricter than the stock contract.
3. Do not edit `packages/nomimono/`. It is read-only; change behavior in your own files, or move the
   package with `just mono update`.
4. `just check` is green before you commit.

## The door

`just` is the only entrypoint. No `package.json` scripts, Makefiles, cargo aliases or command READMEs.
Grammar: `just <area> <verb> [args]`. `just` lists recipes; `just help` adds the lifecycle.

```
just setup | doctor | check                  # check = doctor + feature/front-matter check + agents check + buck2 build //... + buck2 test //...
just build | test | run | targets [args]     # buck2 (default //...)
just mono status | version | update [ref] | migrate | sync | diff
just agents sync | status | skills | check
just context put | get | volumes | volume add | project new|list | feature new|list|status|check|test
just pkg | adapters | init <eco> <adapter> | add <eco> <name...> | update <eco> [name...] | sync [eco] | ensure
just toolchain list | available | add <name>
just area list | add <name> [purpose...]
just submodule add <url> [name] | update | list | sync
just ci sync | run | status
just lua repl | run | cover | profile | meta | fmt | trace | observe | script | version
just build-script <target> | tool <name> | update <target>   # the repo's own scripts/{build,tools,update}/<name>.{sh,lua}
```

The root justfile sets `allow-duplicate-recipes`, so a recipe the repo defines below the import wins
over the package's recipe of the same name. Keep the justfile a thin router: a recipe calls a script
under `scripts/build`, `scripts/tools` or `scripts/update`, never inline logic. Add a recipe and its
script in the same change.

## The lifecycle

1. **Project**: `just context project new <slug>` makes `context/projects/<slug>/PROJECT.md`
   (front matter `name`, `title`, `description`) and `features/`.
2. **Spec**: `just context feature new <project> <slug>` makes `features/<slug>/` with `feature.md`
   (front matter: `name`, `title`, `status`, `description`, `summary`, `implements`, `do`, `dont`),
   `bdd/<slug>.feature`, `test/` and a `BUCK` calling `mono_feature_tests`. Rewrite the Gherkin; it is the
   contract, `feature.md` is only context. `just context feature check [project [slug]]` checks every
   `.feature` has `Feature:` and `Scenario:` and every PROJECT.md, feature.md and library.md has
   `name` and `description` and fits the line budget (`MONO_DOC_MAX_LINES`, default 200, 0 for none).
3. **Lock**: `just context feature test <project> <slug> <name>` writes a red `test/<name>.sh`
   (`--lua` for a red `.lua`); `just context feature test <project> <slug> --steps` binds the Gherkin
   in `test/steps.lua` (`require("mono.steps")`, placeholders `{int} {float} {word} {string} {value}`)
   and gives the BUCK a `<slug>-gherkin` target. `just test //context/...` stays red until the work is done.
4. **Implement** in `library/` or `app/` as buck2 targets, never in `context/`.
5. **Green**: `just check`, the same script CI runs.

`just context feature status <project> <slug>` reports the stage (spec, test, implement) and what comes next.

## Where work goes

| About to... | Put it in |
| --- | --- |
| note, scrape, thought that is not code | `just context put <volume> --title "..." [body]` (sqlite at `context/dump/context.sqlite`) |
| define what a feature must do | `context/projects/<p>/features/<slug>/bdd/*.feature` |
| shared module | `library/<domain>/` with a `BUCK` and a `library.md` (front matter `name`, `description`) |
| shipped surface | `app/<surface>/` with a `BUCK` |
| third-party dependency | `just pkg add <eco> <name>`; manifests and lockfiles live only in `packages/<eco>/` |
| new language | `just toolchain add <name>`, then `just pkg init <eco> <adapter>` |
| CI change | `git/ci/github/*.yml`, then `just ci sync` (`.github/workflows` is a generated copy) |
| public or reusable repo | `just submodule add <url> [name]` (lands in `submodules/<name>`) |
| repeatable agent workflow | hand-authored `.agents/skills/<name>/SKILL.md` |
| new top-level folder | `just area add <name> "purpose"` (folder + `AGENTS.md` + `BUCK`), then add a row under Folders in `.agents/AGENTS.md` |

Only these prose files are allowed: `AGENTS.md`, Gherkin `.feature`, `feature.md`, `library.md`,
`PROJECT.md` and the root `README.md`. Everything else goes to `context/dump` via `just context put`.
Every folder holding a `BUCK` file has an `AGENTS.md`; `just doctor` warns when one is missing.

`.agents/skills/` is generated from PROJECT.md, feature.md, Gherkin and library.md by `just agents sync`;
generated folders carry a `.generated` marker and are rewritten, others are hand-authored and left alone.

## Buck2

The consumer repo is the buck2 project root. `.buckconfig` declares the bundled prelude, `toolchains//`
and the package as a cell (`nomimono = packages/nomimono`). Anything that turns sources into an artifact,
and every test, is a target in a `BUCK` file; a script under `scripts/build` is a temporary bridge.

- `@nomimono//rules:defs.bzl`: `mono_check` (a shell test from the repo root), `mono_script` (a runnable),
  `mono_feature_tests` (one target per test file plus a suite, and the Gherkin target).
- `@nomimono//rules/lua:defs.bzl`: `lua_library`, `lua_binary`, `lua_test`/`lua_tests` (`mono.spec`, TAP),
  `lua_repl`, `lua_bundle` (dialect gate 5.1/5.3/5.4/jit/portable), `lua_embed`, `lua_wasm`, `lua_meta`,
  `lua_typecheck`, `lua_lint`, `lua_format`, `lua_feature_test`; `rules/lua:toolchain.bzl` has `lua_cxx_library`.

## Toolchains

`toolchains/BUCK` starts with `genrule`, `python-bootstrap` and `test` only. `just toolchain available`
lists fragments (cxx, python, rust, go, haskell, ocaml, lua, lua-5.1, lua-5.3, luajit, lua-system,
lua-config, lua-host, luals, luacheck, stylua). `just toolchain add <name>` appends one, hoists its
`load()` lines, and writes a `# nomimono:toolchain <name>` line above it. That marker is the contract
the scripts read (never the Starlark): a hand-written or app-generated `toolchains/BUCK` writes it too.
Lua: `lua` is a hermetic 5.4 built from pinned source; `lua-system` uses PATH; `lua-config` reads
`[lua] bin` from `.buckconfig.local`; `lua-host` runs everything through `[lua] host = <program>`.

## Packages

`just pkg init <eco> <adapter>` makes `packages/<eco>/` with a `.eco` file naming a shipped adapter
(bun, npm, cargo, uv, mix, go, luarocks), or put an executable `packages/<eco>/adapter.sh` there.
Adapters implement `ensure | add | update | sync` and shell out to the ecosystem's own client.

## Updates and migrations

`mono.toml` records the package: `[nomimono]` with `version`, `mode` (`submodule`, `vendor`, or `self`
for the package's own repo), `path`, `repo`, optional `provider`; `[repo] name`; `[modules] context`.

- `just mono update [vX.Y.Z]` (submodule mode): fetches tags, checks out the ref (default: latest tag),
  runs every `migrations/<version>.sh` newer than the manifest's version and not newer than the target,
  in order, adds template files the repo does not have yet (never overwrites), resyncs agents and CI,
  and stages `mono.toml` and the package. Commit after `just check`.
- `mode = "vendor"` refuses and never fetches: replace the copy yourself, then `just mono migrate`
  and `just mono sync`. A `provider = "<app>"` line makes update refuse; the app owns upgrades.
- `just mono migrate` runs the pending migrations against the installed copy; `just mono diff` lists
  template files the repo lacks; `just mono sync` adds them and regenerates.
- Consumer-owned files (`AGENTS.md`, `justfile`, `BUCK`, folder rules) are never overwritten; a change
  that must reach them ships as a migration.
- 0.5.0 is the rename: it moves `packages/monomono` to `packages/nomimono` (git mv for a submodule or
  tracked copy) and rewrites `@monomono//`, the `.buckconfig` cell, `# monomono:toolchain`, the justfile
  import, `[monomono]` in mono.toml, `monomono.*` telemetry names and the package name in AGENTS.md,
  CLAUDE.md and `.agents/`, in the repo's own files only. Afterwards: `just mono sync`, `just check`, commit.

## Rules that bite

- `packages/nomimono/` is read-only.
- The justfile is a thin router; behavior lives in scripts.
- Every artifact and every test is a buck2 target.
- Toolchains are declared, never assumed; ecosystems live under `packages/<eco>` behind an adapter.
- Reusable code in `library/`, deliverables in `app/`; apps depend on library targets.
- Spec before code: Gherkin, then a red test target, then implementation.
- Commit only on a green `just check`.
