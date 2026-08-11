# `nix fmt` and the treefmt flake check. Only language-agnostic formatters live
# here — anything tied to a language belongs in that toolchain's module, so a
# repo that never enables it never pays for it.
{
  perSystem = {pkgs, ...}: {
    treefmt = {
      projectRootFile = "flake.nix";

      programs = {
        # Nix
        alejandra.enable = true;
        statix.enable = true;

        # GitHub Actions
        actionlint.enable = true;

        # zizmor audits workflows for credential leaks and script injection.
        # It has no darwin build, so it runs on Linux checkouts and in CI,
        # which is where the rule is actually enforced.
        zizmor.enable = pkgs.stdenv.hostPlatform.isLinux;

        # Shell
        shellcheck.enable = true;
        shfmt.enable = true;

        # Data and docs
        taplo.enable = true;

        yamlfmt = {
          enable = true;
          settings.formatter.retain_line_breaks = true;
        };

        mdformat = {
          enable = true;

          # Without the GFM plugin mdformat parses plain CommonMark, which does
          # not know tables or task lists — it would escape the brackets in
          # `- [ ]` and leave table pipes unaligned.
          plugins = ps: [ps.mdformat-gfm];

          # Never reflow prose: one paragraph stays one line and the editor
          # soft-wraps it. Reflowing turns a one-word edit into a whole-block
          # diff.
          settings.wrap = "keep";
        };
      };
    };
  };
}
