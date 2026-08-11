# What this repository is made of. flake.nix reads this file and nothing else
# does, so editing it by hand is fine — re-enter the dev shell afterwards to
# pick up the change.
#
# The project's name and one-line description live in flake.nix's `description`
# and in README.md, which is where people and tooling already look for them.
{
  # Platforms the flake evaluates for. Adding one costs nothing until someone
  # actually builds on it.
  systems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];

  # Toolchains composed into the dev shell and the formatter. Each name maps to
  # nix/toolchains/<name>.nix, and they combine freely: ["python" "rust"],
  # ["rust" "web"], or [] for a repository that is only Nix and docs.
  #
  # A toolchain's flake inputs and ignore rules are grouped under matching
  # `# >>> toolchain:<name>` markers elsewhere in the tree, so adding or
  # dropping one stays a local edit. See CONTRIBUTING.md.
  toolchains = [
    "python"
    "rust"
    "web"
  ];
}
