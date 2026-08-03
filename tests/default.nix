{
  pkgs,
  toolchains,
}:

let
  inherit (toolchains.publicLib) bun deno node;
  project = import ../lib/project.nix { inherit (pkgs) lib; };
  semver = import ../lib/semver.nix { inherit (pkgs) lib; };

  assertions = [
    (project.readVersionFile ./fixtures/runtime-version == "2.9.4")
    (
      project.versionFromToolVersionsText "nodejs" ''
        bun 1.3.14
        nodejs 24.18.1
        deno 2.9.4
      '' == "24.18.1"
    )
    (project.versionFromToolVersionsText "bun" "nodejs 24\nbun\t1.3.14\n" == "1.3.14")
    (project.packageManagerVersion "bun" { packageManager = "bun@1.3.14+sha256.example"; } == "1.3.14")
    ((node.fromPackageJSON pkgs ./fixtures/node-package.json).version == "24.18.1")
    ((bun.fromPackageJSON pkgs ./fixtures/bun-package.json).version == "1.3.14")
    (pkgs.lib.hasPrefix "2." (deno.fromPackageJSON pkgs ./fixtures/deno-package.json).version)
    (
      semver.resolve [
        "1.2.3"
        "1.9.0"
        "2.0.0"
      ] "^1.2" == "1.9.0"
    )
    (pkgs.lib.hasPrefix "24." (node.resolveVersion pkgs "24"))
    ((bun.fromVersion pkgs "latest").version == bun.resolveVersion pkgs "latest")
    ((deno.fromVersion pkgs "lts").version == deno.resolveVersion pkgs "lts")
  ];
in
assert pkgs.lib.all pkgs.lib.id assertions;
pkgs.runCommand "js-toolchain-lib-tests" { } "touch $out"
