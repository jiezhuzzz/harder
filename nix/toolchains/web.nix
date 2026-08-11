# JavaScript and TypeScript. Nix supplies the runtime and the package manager;
# npm/pnpm owns node_modules.
#
# `pkgs.nodejs` follows nixpkgs' default LTS. Pin it (pkgs.nodejs_24) when the
# project needs a specific major.
{
  perSystem = {pkgs, ...}: {
    devPackages = [
      pkgs.nodejs
      pkgs.pnpm
    ];

    devShellHooks = ''
      # Project-local binaries (vite, tsc, eslint) win over anything global.
      PATH="$PWD/node_modules/.bin:$PATH"
      export PATH
    '';

    treefmt.programs.prettier = {
      enable = true;

      # Prettier's default set also claims Markdown, YAML and JSON5, which
      # mdformat and yamlfmt already own in nix/formatter.nix. Two formatters
      # over one file fight each other, so this narrows prettier to the
      # web-only extensions.
      includes = [
        "*.cjs"
        "*.css"
        "*.html"
        "*.js"
        "*.json"
        "*.jsx"
        "*.mjs"
        "*.scss"
        "*.ts"
        "*.tsx"
        "*.vue"
      ];
    };
  };
}
