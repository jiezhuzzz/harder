# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Getting started

```sh
nix develop
```

That gives you the project's toolchains and installs the git hooks. See [CONTRIBUTING.md](CONTRIBUTING.md) for the commit and branch conventions, and for how the flake is put together.

## Development

```sh
nix fmt          # format the tree
nix flake check  # what CI runs
```

## Planning granularity

Work is planned as milestones broken into issues, an issue carries a spec through review before implementation, and an issue's body ends in a task list. The lifecycle labels in `.github/labels.json` track the middle part: `stage: draft` until concretized, `stage: spec` while agents review it, `stage: reviewed` while the verdict is pending. What separates the levels is not size but what attaches to each one: a milestone carries the research narrative, an issue carries a spec, a review cycle, a pull request, and dependency edges, and a task carries nothing but a checkbox. To place a piece of work, ask which of that machinery it needs.

- **Milestone** — done when you can claim something new: a capability demonstrated, a question answered, an approach validated or killed. If it would not be a bullet in a progress update, it is not a milestone. Cut milestone boundaries at decision points, wherever the next stretch of work depends on results you do not have yet. Only the current milestone is decomposed into concrete issues; later ones stay coarse, because planning in detail past your next unknown is fiction.
- **Issue** — the unit the pipeline processes: one session concretizes it into a spec, the spec is reviewed, one session implements it, and it merges as one pull request. Three tests, and failing any one means split: an agent can hold the whole spec in one session; it merges as one coherently reviewable PR; and nothing outside needs to block on a part of it, since dependency edges exist only between whole issues. For experiments, one issue is one pre-registered question with its metrics. A variation whose result could change the project's direction is its own issue; any other variation is a task inside one.
- **Sub-issue** — a full issue that inherited its "why" from a parent. It has its own spec, review cycle, PR, and place in the dependency graph. Created in one situation: concretization reveals an issue is bigger than one session, so it splits, the parent becomes the tracking node holding the motivation, and the children hold the implementations. A fragment that does not need its own review cycle and PR is a task, not a sub-issue.
- **Task** — a checkbox inside an issue, written during concretization as the implementation plan and checked off within one implementation session. The test is referenceability: if nothing outside the issue will ever point at it, it is a task. The moment one attracts discussion or another issue must wait on it, convert it to a sub-issue.

Two symptoms of miscalibration. Issues too big: the spec grows several clusters of acceptance criteria, or the PR touches everything at once. Splitting is a legitimate spec-review verdict, cheap at spec time and expensive at PR time. Issues too small: the dependency graph degenerates into a linear chain of trivial nodes, each dragging a full review cycle behind it. A spec that would just say "do X" should have been a checkbox in a larger issue.

## License

See [LICENSE](LICENSE).
