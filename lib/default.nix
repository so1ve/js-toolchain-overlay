{ lib }:

let
  semver = import ./semver.nix { inherit lib; };
  project = import ./project.nix { inherit lib; };
  catalog = import ./catalog.nix { inherit lib semver; };

  node = import ./node.nix { inherit lib catalog project; };
  bun = import ./bun.nix { inherit lib catalog project; };
  deno = import ./deno.nix { inherit lib catalog project; };
  pnpm = import ./pnpm.nix { inherit lib catalog project; };
  yarn = import ./yarn.nix { inherit lib catalog project; };

  supportedSystems = lib.unique (
    node.supportedSystems
    ++ bun.supportedSystems
    ++ deno.supportedSystems
    ++ pnpm.supportedSystems
    ++ yarn.supportedSystems
  );

  overlay =
    final: prev:
    node.overlay final prev
    // bun.overlay final prev
    // deno.overlay final prev
    // pnpm.overlay final prev
    // yarn.overlay final prev;

  packagesFor =
    pkgs:
    node.packagesFor pkgs
    // bun.packagesFor pkgs
    // deno.packagesFor pkgs
    // pnpm.packagesFor pkgs
    // yarn.packagesFor pkgs;

  publicToolLib = tool: {
    inherit (tool)
      fromPackageJSON
      fromProject
      fromVersion
      fromVersionFile
      resolveVersion
      ;
  };

  publicLib = {
    node = publicToolLib node;
    bun = publicToolLib bun;
    deno = publicToolLib deno;
    pnpm = publicToolLib pnpm;
    yarn = publicToolLib yarn;
  };
in
{
  inherit
    overlay
    packagesFor
    publicLib
    supportedSystems
    ;
}
