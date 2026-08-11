# The default dev shell, plus the two seams toolchain modules extend it
# through. Both options merge across modules — lists concatenate and lines are
# joined — so several toolchains can contribute without knowing about each
# other.
{lib, ...}: {
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    options = {
      devPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        description = ''
          Packages placed on PATH in the dev shell. Toolchain modules append
          their compilers and tools here; the git hook packages are added
          separately.
        '';
      };

      devShellHooks = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Shell fragments appended to the dev shell's shellHook, after the git
          hook installer has run. Use it for PATH tweaks and environment
          variables a toolchain needs.
        '';
      };
    };

    config.devShells.default = pkgs.mkShell {
      packages = config.devPackages ++ config.pre-commit.settings.enabledPackages;

      shellHook = ''
        ${config.pre-commit.shellHook}
        ${config.devShellHooks}
      '';
    };
  };
}
