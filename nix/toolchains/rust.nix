# Rust, via fenix. Enabling this toolchain requires the `fenix` input, which
# flake.nix declares inside its `toolchain:rust` marker block.
#
# Swap `stable` for `beta`, `latest` (nightly), or
# `fromToolchainFile {file = ../../rust-toolchain.toml; sha256 = "...";}` if the
# project needs to pin a channel.
{
  perSystem = {inputs', ...}: let
    rustToolchain = inputs'.fenix.packages.stable.withComponents [
      "cargo"
      "clippy"
      "rust-analyzer"
      "rust-src"
      "rustc"
      "rustfmt"
    ];
  in {
    devPackages = [rustToolchain];

    treefmt.programs.rustfmt = {
      enable = true;
      package = rustToolchain;
    };

    # Once there is a crate to lint, a clippy gate belongs here rather than in
    # nix/hooks.nix, so it disappears with the toolchain:
    #
    #   pre-commit.settings.hooks.clippy = {
    #     enable = true;
    #     packageOverrides = {
    #       cargo = rustToolchain;
    #       clippy = rustToolchain;
    #     };
    #     settings.denyWarnings = true;
    #   };
  };
}
