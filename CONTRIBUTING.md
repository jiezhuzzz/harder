# Contributing

## Getting set up

You need [Nix](https://nixos.org/download/) with flakes enabled. Everything else comes from the flake.

```sh
nix develop
```

That drops you into a shell with the project's toolchains on `PATH` and installs the git hooks into `.git/hooks` on first entry. Re-enter it after changing anything under `nix/`.

If you use [direnv](https://direnv.net/), add an `.envrc` containing `use flake` and run `direnv allow` — the shell then loads whenever you `cd` in. The file is deliberately not committed, so this stays a per-checkout choice.

## Before you push

```sh
nix fmt          # format everything treefmt owns
nix flake check  # what CI runs
```

`nix fmt` runs [treefmt](https://treefmt.com/) over the whole tree. The set of formatters is assembled from `nix/formatter.nix` (language-agnostic) plus whatever the enabled toolchains contribute. The pre-commit hook runs the same thing on staged files, so a clean commit is usually enough.

`nix flake check` evaluates every output and runs the formatter and hook checks. This is exactly what `.github/workflows/check.yml` runs, so a green local check means a green CI.

## Commits

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/), enforced at commit time by `convco`:

```
<type>(<optional scope>): <description>
```

Use `feat`, `fix`, `chore`, `docs`, `refactor`, or `test`. Keep the description imperative and lowercase, with no trailing period.

## Branches

Branch names must be `<type>/<kebab-case>`, using the same types as commits:

```
feat/composable-toolchains
fix/prettier-markdown-overlap
```

A pre-push hook rejects anything else, and rejects pushing to `main` directly. Both rules live in `nix/hooks.nix`.

## Pull requests

Open a PR against `main`. The PR title becomes the squash-merge commit, so it has to be a valid Conventional Commit subject too.

CI runs `nix flake check` on every PR. Claude Code and Codex each post a review when their API key is configured, and you can invoke either one yourself by mentioning `@claude` or `@codex` in a comment. Both run read-only and reply in a comment; neither can push to your branch.

## Working on the flake

The flake is split so that each file has one job:

| File                   | What lives there                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------ |
| `project.nix`          | The knobs: which systems to evaluate, which toolchains to compose                                      |
| `flake.nix`            | Inputs, and the module list assembled from `project.nix`                                               |
| `nix/dev-shell.nix`    | The dev shell, and the `devPackages` / `devShellHooks` options it merges                               |
| `nix/formatter.nix`    | `nix fmt` — formatters that apply to any repository                                                    |
| `nix/hooks.nix`        | Git hooks                                                                                              |
| `nix/toolchains/*.nix` | One file per language, contributing packages, formatters and hooks                                     |
| `nix/app.nix`          | The `nix run` scaffold app, wrapping `nix/scaffold.sh`; both are stripped from the projects it creates |

### Adding a toolchain

Create `nix/toolchains/<name>.nix` as a flake-parts module and add `"<name>"` to `toolchains` in `project.nix`. A module contributes through the merged options rather than defining the dev shell itself:

```nix
{
  perSystem = {pkgs, ...}: {
    devPackages = [pkgs.go];

    devShellHooks = ''
      export GOPATH="$PWD/.go"
    '';

    treefmt.programs.gofmt.enable = true;
  };
}
```

`devPackages` is a list and `devShellHooks` is a block of lines; both merge across modules, so toolchains never need to know about each other.

If the toolchain needs its own flake input, declare it in `flake.nix` inside a marker block, so everything belonging to that toolchain can be found and removed together:

```nix
# >>> toolchain:go
gomod2nix.url = "github:nix-community/gomod2nix";
# <<< toolchain:go
```

The same markers work in `.gitignore` and anywhere else a toolchain needs a few lines of its own.

### Adding a formatter

Language-agnostic formatters go in `nix/formatter.nix`; anything tied to a language goes in that toolchain's module, so a repo that never enables it never pays for it. The available programs are listed in [treefmt-nix](https://github.com/numtide/treefmt-nix/tree/main/programs).

Watch for two formatters claiming the same files — treefmt will run both, and they will fight. `nix/toolchains/web.nix` narrows prettier's `includes` for exactly this reason.
