# The scaffold entry point: `nix run github:jiezhuzzz/harder -- <directory>`
# creates a new project from this template. The flake's own source tree is
# baked into the script as the template source, so the scaffolder and the
# files it copies always come from the same revision.
#
# This module and nix/scaffold.sh exist only in the template itself — the
# scaffold run strips both, along with their import in flake.nix, from the
# projects it creates.
{self, ...}: {
  perSystem = {pkgs, ...}: {
    apps.default = {
      program = pkgs.writeShellApplication {
        name = "harder-scaffold";
        runtimeInputs = with pkgs; [argc coreutils findutils gnugrep gawk git];
        text =
          builtins.replaceStrings ["@templateSource@"] ["${self}"]
          (builtins.readFile ./scaffold.sh);
      };
      meta.description = "Scaffold a new project from this template";
    };
  };
}
