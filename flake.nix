{
  description = "Binary Node.js releases as a Nix overlay";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      nodeOverlay = import ./lib { inherit lib; };
      forAllSystems = lib.genAttrs nodeOverlay.supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      lib = nodeOverlay;
      overlays.default = nodeOverlay.overlay;

      packages = forAllSystems (system: nodeOverlay.packagesFor (pkgsFor system));

      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          update = pkgs.writeShellApplication {
            name = "update-node-overlay";
            runtimeInputs = [ pkgs.nodejs ];
            text = "exec node ${./scripts/update.mjs}";
          };
        in
        {
          default = {
            type = "app";
            program = "${update}/bin/update-node-overlay";
            meta.description = "Update Node.js releases and archive hashes";
          };
          update = {
            type = "app";
            program = "${update}/bin/update-node-overlay";
            meta.description = "Update Node.js releases and archive hashes";
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
              nixfmt-tree
              nodejs
              prettier
            ];
          };
        }
      );
    };
}
