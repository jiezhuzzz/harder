# harder

A GitHub repository template for Nix-based projects: a dev shell you compose from the toolchains you actually use, git hooks that enforce commit and branch conventions, one formatter pass over the whole tree, and CI that runs exactly what you ran locally.

There is no source tree here on purpose. This is the scaffolding a project sits inside, not a starter application.

## Using it

Create a repository from the template, then bootstrap it:

```sh
gh repo create my-project --template jiezhuzzz/harder --private --clone
cd my-project
./scripts/init-from-template.sh
```

The script asks which toolchains you want, rewrites `project.nix`, strips the modules and flake inputs you did not pick out of the tree, replaces this README with one for your project, re-locks the flake, and removes itself. Pass `--help` for the non-interactive flags.

Then:

```sh
nix develop
```

## What you get

| Area       | What it does                                                                                                   |
| ---------- | -------------------------------------------------------------------------------------------------------------- |
| Dev shell  | `nix develop` puts the selected toolchains on `PATH` and installs the git hooks                                |
| Formatting | `nix fmt` runs treefmt over Nix, YAML, TOML, Markdown, shell, workflows, and each toolchain's languages        |
| Hooks      | Conventional Commit subjects at commit time; `<type>/<kebab-case>` branch names and no direct pushes to `main` |
| CI         | `nix flake check` plus a dev shell build on every PR, with an opt-in Cachix binary cache                       |
| Security   | Workflow actions pinned by commit SHA, least-privilege `permissions`, and a `zizmor` audit of the workflows    |
| Automation | Dependabot for actions and flake inputs; Claude Code and Codex, each on mentions and as a PR reviewer          |
| Community  | Issue forms and a PR template                                                                                  |

## Toolchains

Each name in `toolchains` in `project.nix` maps to a module in `nix/toolchains/`. Combine them freely — `["python" "rust"]`, `["rust" "web"]`, or `[]` for a repo that is only Nix and docs.

| Toolchain | Dev shell                           | Formatters                  | Extra flake input |
| --------- | ----------------------------------- | --------------------------- | ----------------- |
| `rust`    | fenix stable, clippy, rust-analyzer | `rustfmt`                   | `fenix`           |
| `python`  | `python3`, `uv`                     | `ruff-check`, `ruff-format` | —                 |
| `web`     | `nodejs`, `pnpm`                    | `prettier`                  | —                 |

Adding your own is a file and a list entry; see [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-toolchain).

The template ships with all three enabled so its own CI exercises every module. Your project almost certainly wants fewer.

## Repository settings

None of these are required for CI to pass — the steps that need them skip themselves when unconfigured.

- **Cachix** — set the `CACHIX_CACHE` *variable* to your cache name to pull from it, and the `CACHIX_AUTH_TOKEN` *secret* to a write token to also push to it. With only the variable set, CI pulls and does not push.
- **Claude Code** — set the `ANTHROPIC_API_KEY` secret to enable `@claude` mentions and automatic PR review. Delete `.github/workflows/claude*.yml` if you do not want either.
- **Codex** — set the `OPENAI_API_KEY` secret to enable `@codex` mentions and automatic PR review. Delete `.github/workflows/codex*.yml` if you do not want either.
- **Branch protection** — the branch hooks are local and only bind people who use the dev shell. Protect `main` on GitHub to make it stick: require the `Nix flake` check, require a PR, and enable squash-only merges so Conventional Commit PR titles become the history.
- **Discussions** — `.github/ISSUE_TEMPLATE/config.yml` links to the Discussions tab. Enable it, or drop that link.

Both agents are wired up and both review every pull request, so a repository with both keys set pays two bills per PR. Delete the review workflow of whichever one you do not want as a standing reviewer; the mention workflows only cost anything when you invoke them.

Each agent runs read-only and replies in a comment. Codex enforces this in two places: `permission-profile: ':read-only'` sandboxes the model, and the workflow is split so the job holding the API key has a token that cannot write, while the job that posts the comment never runs the model. Codex also refuses to run for anyone without write access on the repository, which is what keeps a drive-by comment from spending your quota.

## Layout

```
flake.nix              inputs, and the module list assembled from project.nix
project.nix            which systems to evaluate, which toolchains to compose
nix/
  dev-shell.nix        the dev shell and the options toolchains extend it through
  formatter.nix        nix fmt — formatters that apply to any repository
  hooks.nix            git hooks
  toolchains/          one module per language
.github/
  workflows/           flake checks, and Claude Code and Codex on mentions and PR review
  ISSUE_TEMPLATE/      issue forms
scripts/
  init-from-template.sh   bootstrap, then delete itself
```

## License

MIT. See [LICENSE](LICENSE).
