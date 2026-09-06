{
  description = "Nix overlay for official Node.js, Bun, Deno, pnpm, and Yarn distributions";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      toolchains = import ./lib { inherit lib; };
      forAllSystems = lib.genAttrs toolchains.supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      lib = toolchains.publicLib;
      overlays.default = toolchains.overlay;

      packages = forAllSystems (system: toolchains.packagesFor (pkgsFor system));

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          packages = toolchains.packagesFor pkgs;
        in
        {
          lib = import ./tests { inherit pkgs toolchains; };
          inherit (packages)
            node
            bun
            deno
            pnpm
            yarn
            ;
          package-managers = import ./tests/package-managers.nix { inherit pkgs toolchains; };
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          update = pkgs.writeShellApplication {
            name = "update-toolchains";
            runtimeInputs = [ pkgs.nodejs ];
            text = ''
              exec node ${./scripts}/update.mjs "$@"
            '';
          };
        in
        {
          update = {
            type = "app";
            program = "${update}/bin/update-toolchains";
            meta.description = "Update releases";
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              actionlint
              nixfmt-tree
              nodejs
              prettier
            ];
          };
        }
      );
    };
}
