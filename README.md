# harder

A GitHub repository template for Nix-based projects: a dev shell you compose from the toolchains you actually use, git hooks that enforce commit and branch conventions, one formatter pass over the whole tree, and CI that runs exactly what you ran locally.

There is no source tree here on purpose. This is the scaffolding a project sits inside, not a starter application.

## Using it

```sh
nix run github:jiezhuzzz/harder -- my-project
cd my-project
nix develop
```

The run asks which toolchains you want, copies the template into `my-project` with the modules and flake inputs you did not pick stripped out, writes a README for your project, re-locks the flake, and leaves a git repository with one bootstrap commit. Pass `--help` after the `--` for the non-interactive flags.

Then put it on GitHub:

```sh
gh repo create my-project --source=. --private --push
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
- **Branch protection** — the branch hooks are local and only bind people who use the dev shell. Protect `main` on GitHub to make it stick: `.github/rulesets/main.json` encodes the intended rules (require the `Nix flake` check, require a PR, squash-only merges so Conventional Commit PR titles become the history, no force pushes or deletion). Apply it with `gh api "repos/{owner}/{repo}/rulesets" --input .github/rulesets/main.json`, or import the file under Settings → Rules → Rulesets. It ships with a repository-admin bypass so direct pushes stay possible for you; delete the `bypass_actors` entry to bind everyone.
- **Discussions** — `.github/ISSUE_TEMPLATE/config.yml` links to the Discussions tab. Enable it, or drop that link.

Both agents are wired up and both review every pull request, so a repository with both keys set pays two bills per PR. Delete the review workflow of whichever one you do not want as a standing reviewer; the mention workflows only cost anything when you invoke them.

Each agent runs read-only and replies in a comment. Codex enforces this in two places: `permission-profile: ':read-only'` sandboxes the model, and the workflow is split so the job holding the API key has a token that cannot write, while the job that posts the comment never runs the model. Codex also refuses to run for anyone without write access on the repository, which is what keeps a drive-by comment from spending your quota.

## Planning granularity

Work is planned as milestones broken into issues, an issue carries a spec through review before implementation, and an issue's body ends in a task list. The lifecycle labels in `.github/labels.json` track the middle part: `stage: draft` until concretized, `stage: spec` while agents review it, `stage: reviewed` while the verdict is pending. What separates the levels is not size but what attaches to each one: a milestone carries the research narrative, an issue carries a spec, a review cycle, a pull request, and dependency edges, and a task carries nothing but a checkbox. To place a piece of work, ask which of that machinery it needs.

- **Milestone** — done when you can claim something new: a capability demonstrated, a question answered, an approach validated or killed. If it would not be a bullet in a progress update, it is not a milestone. Cut milestone boundaries at decision points, wherever the next stretch of work depends on results you do not have yet. Only the current milestone is decomposed into concrete issues; later ones stay coarse, because planning in detail past your next unknown is fiction.
- **Issue** — the unit the pipeline processes: one session concretizes it into a spec, the spec is reviewed, one session implements it, and it merges as one pull request. Three tests, and failing any one means split: an agent can hold the whole spec in one session; it merges as one coherently reviewable PR; and nothing outside needs to block on a part of it, since dependency edges exist only between whole issues. For experiments, one issue is one pre-registered question with its metrics. A variation whose result could change the project's direction is its own issue; any other variation is a task inside one.
- **Sub-issue** — a full issue that inherited its "why" from a parent. It has its own spec, review cycle, PR, and place in the dependency graph. Created in one situation: concretization reveals an issue is bigger than one session, so it splits, the parent becomes the tracking node holding the motivation, and the children hold the implementations. A fragment that does not need its own review cycle and PR is a task, not a sub-issue.
- **Task** — a checkbox inside an issue, written during concretization as the implementation plan and checked off within one implementation session. The test is referenceability: if nothing outside the issue will ever point at it, it is a task. The moment one attracts discussion or another issue must wait on it, convert it to a sub-issue.

Two symptoms of miscalibration. Issues too big: the spec grows several clusters of acceptance criteria, or the PR touches everything at once. Splitting is a legitimate spec-review verdict, cheap at spec time and expensive at PR time. Issues too small: the dependency graph degenerates into a linear chain of trivial nodes, each dragging a full review cycle behind it. A spec that would just say "do X" should have been a checkbox in a larger issue.

## Layout

```
flake.nix              inputs, and the module list assembled from project.nix
project.nix            which systems to evaluate, which toolchains to compose
nix/
  dev-shell.nix        the dev shell and the options toolchains extend it through
  formatter.nix        nix fmt — formatters that apply to any repository
  hooks.nix            git hooks
  app.nix              the scaffold app behind `nix run`
  scaffold.sh          the scaffold script; both are stripped from the projects it creates
  toolchains/          one module per language
.github/
  workflows/           flake checks, and Claude Code and Codex on mentions and PR review
  ISSUE_TEMPLATE/      issue forms
template/
  README.md            becomes the new project's README
```

## License

MIT. See [LICENSE](LICENSE).
