# Python, managed by uv. Nix supplies the interpreter and uv; uv owns the
# lockfile, the virtualenv and any dependency resolution — nothing Python-level
# is expressed in Nix.
#
# `pkgs.python3` follows nixpkgs' default minor version. Pin it (pkgs.python313)
# when the project needs a specific one.
{
  perSystem = {pkgs, ...}: {
    devPackages = [
      pkgs.python3
      pkgs.uv
    ];

    devShellHooks = ''
      # Put uv's project virtualenv on PATH when one exists, so `pytest` and
      # friends resolve without a `uv run` prefix.
      if [ -d "$PWD/.venv/bin" ]; then
        PATH="$PWD/.venv/bin:$PATH"
        export PATH
      fi
    '';

    treefmt.programs = {
      ruff-check.enable = true;
      ruff-format.enable = true;
    };

    # mypy is deliberately left off: it needs the project's dependencies
    # resolved to say anything useful, which is uv's job, not treefmt's. Run it
    # as `uv run mypy` from the dev shell, or add a CI step.
  };
}
