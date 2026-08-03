{ lib }:

let
  semver = import ./semver.nix { inherit lib; };
  project = import ./project.nix { inherit lib; };
  catalog = import ./catalog.nix { inherit lib semver; };

  node = import ./node.nix { inherit lib catalog project; };
  bun = import ./bun.nix { inherit lib catalog project; };
  deno = import ./deno.nix { inherit lib catalog project; };

  supportedSystems = lib.unique (
    node.supportedSystems ++ bun.supportedSystems ++ deno.supportedSystems
  );

  overlay = final: prev: node.overlay final prev // bun.overlay final prev // deno.overlay final prev;

  packagesFor = pkgs: node.packagesFor pkgs // bun.packagesFor pkgs // deno.packagesFor pkgs;

  publicRuntimeLib = runtime: {
    inherit (runtime)
      fromPackageJSON
      fromProject
      fromVersion
      fromVersionFile
      resolveVersion
      ;
  };

  publicLib = {
    node = publicRuntimeLib node;
    bun = publicRuntimeLib bun;
    deno = publicRuntimeLib deno;
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
