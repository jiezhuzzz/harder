# Git hooks, installed into .git/hooks the first time you enter the dev shell.
# Toolchain modules may add their own under pre-commit.settings.hooks.
{
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    pre-commit.settings = {
      package = pkgs.prek;

      hooks = {
        # Commit subjects must be Conventional Commits. Release tooling and the
        # branch-name rule below both key off the same set of types.
        convco.enable = true;

        treefmt = {
          enable = true;
          stages = ["pre-commit"];
          packageOverrides.treefmt = config.treefmt.build.wrapper;
        };

        no-commit-to-branch = {
          enable = true;
          name = "branch is main or not named <type>/<kebab-case>";
          stages = ["pre-push"];
          settings = {
            branch = ["main"];
            pattern = [
              "^(?!(feat|fix|chore|docs|refactor|test)/[a-z0-9]+(?:-[a-z0-9]+)*$).*"
            ];
          };
        };
      };
    };
  };
}
