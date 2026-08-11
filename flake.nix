{
  description = "A Nix-flake-based repository template with composable toolchains";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

    flake-parts.url = "github:hercules-ci/flake-parts";

    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Inputs below belong to a single toolchain. Keep each one in its own
    # >>> / <<< marker block, so everything that toolchain needs can be found
    # and removed together with its module.

    # >>> toolchain:rust
    fenix = {
      url = "https://flakehub.com/f/nix-community/fenix/0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # <<< toolchain:rust
  };

  outputs = inputs @ {flake-parts, ...}: let
    project = import ./project.nix;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports =
        [
          inputs.git-hooks-nix.flakeModule
          inputs.treefmt-nix.flakeModule

          ./nix/dev-shell.nix
          ./nix/formatter.nix
          ./nix/hooks.nix

          # >>> scaffold
          ./nix/app.nix
          # <<< scaffold
        ]
        ++ map (name: ./nix/toolchains + "/${name}.nix") project.toolchains;

      inherit (project) systems;
    };
}
