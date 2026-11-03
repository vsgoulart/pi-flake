{
  description = "pi coding agent releases, packaged from upstream prebuilt binaries";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      # Pinned by scripts/update.sh; see README.md.
      sources = lib.importJSON ./sources.json;
      platforms = builtins.attrNames sources.assets;
      forAllSystems = lib.genAttrs platforms;

      mkPi =
        pkgs:
        pkgs.callPackage ./nix/pi.nix {
          inherit (sources) version tag;
          inherit platforms;
          source = sources.assets.${pkgs.stdenv.hostPlatform.system};
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pi = mkPi nixpkgs.legacyPackages.${system};
        in
        {
          inherit pi;
          pi-coding-agent = pi;
          default = pi;
        }
      );

      overlays.default = final: _prev: {
        pi-coding-agent = mkPi final;
      };

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${system}.pi;
          meta.description = self.packages.${system}.pi.meta.description;
        };
      });
    };
}
