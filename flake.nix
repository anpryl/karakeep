{
  description = "karakeep (anpryl fork) — package and NixOS module for the content-image-caching branch";

  inputs = {
    # Pinned rather than following a consumer, so this flake builds reproducibly on its
    # own. The rev matters beyond reproducibility for two reasons:
    #
    #  1. nix/package.nix is VENDORED from this exact nixpkgs
    #     (pkgs/by-name/ka/karakeep), so its use of fetchPnpmDeps (fetcherVersion = 3)
    #     and pnpmConfigHook is guaranteed to match the API here. When bumping, diff
    #     nixpkgs' karakeep against nix/package.nix rather than assuming.
    #
    #  2. It has pnpm_11, which this tree needs since the v0.33.2 merge. Before that
    #     merge the constraint ran the other way: the tree was pnpm 9 and newer
    #     nixpkgs had REMOVED pnpm_9 ("reached EOL on 2026-04-30", an unconditional
    #     throw in aliases.nix that no config can override), which pinned this flake
    #     below that removal. Moving the source to pnpm 11 lifted that ceiling, so
    #     this rev is now a free choice rather than a forced one.
    nixpkgs.url = "github:NixOS/nixpkgs/f4f698677b11021a8f84f452e23ae9ef2427bec3";

    # nodejs 24.18.1, used ONLY to build karakeep. 24.19.0 makes karakeep's bundled
    # better-sqlite3 abort on startup — "Assertion failed: (env) != nullptr" in
    # Statement::~Statement() — roughly two seconds in. Upstream hit the same bug and
    # fixed it the same way (karakeep-app/karakeep#2989, #2996) by pinning node; their
    # pin lives in a Dockerfile and so never reaches a Nix build, which is why it is
    # repeated here. There is no node 24.20 yet, so this is not short-lived. When node
    # ships the V8/GC fix, DROP this input rather than bumping it.
    nixpkgs-node2418.url = "github:NixOS/nixpkgs/624bdb74f414f1f8bf96a774f7db67a883c0ec1d";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-node2418,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Matches the version string this package has always carried, so adopting the
      # flake does not silently rename the store path's version component.
      version = "0-unstable-${self.shortRev or self.dirtyShortRev or "dirty"}";

      # Since the v0.33.2 merge this tree declares pnpm@11.2.1, so the build uses
      # pnpm_11 and no longer needs an insecure-package exception. The seven pnpm 9
      # advisories that forced `permittedInsecurePackages = [ "pnpm-9.15.9" ]` — here
      # and in every consumer — are simply gone.
      pkgsFor = system: import nixpkgs { inherit system; };

      karakeepFor =
        system:
        (pkgsFor system).callPackage ./nix/package.nix {
          # The source is this checkout, not a fetched upstream tag.
          src = self;
          inherit version;
          nodejs = nixpkgs-node2418.legacyPackages.${system}.nodejs_24;
        };
    in
    {
      packages = forAllSystems (system: rec {
        karakeep = karakeepFor system;
        default = karakeep;
      });

      overlays.default = _final: prev: { karakeep = karakeepFor prev.stdenv.hostPlatform.system; };

      # The option path stays `services.karakeep`, identical to nixpkgs', so adopting
      # this is an import rather than a rewrite of every setting. The cost is that a
      # consumer MUST also disable nixpkgs' module:
      #   disabledModules = [ "services/web-apps/karakeep.nix" ];
      # Two modules declaring the same option path is a definition conflict, and the
      # resulting error names the option rather than the cause.
      nixosModules.karakeep =
        { lib, pkgs, ... }:
        {
          imports = [ ./nix/module.nix ];
          # mkDefault so a consumer can still substitute their own build. Without this
          # the module's own default (`pkgs.karakeep`) would quietly resolve to the
          # consumer's nixpkgs copy — upstream's release, not this fork.
          services.karakeep.package = lib.mkDefault (karakeepFor pkgs.stdenv.hostPlatform.system);
        };
      nixosModules.default = self.nixosModules.karakeep;

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);
    };
}
