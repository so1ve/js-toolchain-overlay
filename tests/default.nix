{
  pkgs,
  toolchains,
}:

let
  inherit (toolchains.publicLib) bun deno node;
  project = import ../lib/project.nix { inherit (pkgs) lib; };
  semver = import ../lib/semver.nix { inherit (pkgs) lib; };
  nodeWithoutCorepack = node.fromVersion pkgs "16.8.0";
  nodeWithBundledCorepack = node.fromVersion pkgs "24.19.0";
  nodeWithStandaloneCorepack = node.fromVersion pkgs "26.6.0";

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
    (
      nodeWithoutCorepack.outputs == [
        "out"
        "npm"
      ]
    )
    (nodeWithoutCorepack ? npm)
    (!(nodeWithoutCorepack ? corepack))
    (
      nodeWithBundledCorepack.outputs == [
        "out"
        "npm"
        "corepack"
      ]
    )
    (nodeWithBundledCorepack.npmVersion == "11.17.0")
    (nodeWithBundledCorepack ? npm)
    (nodeWithBundledCorepack ? corepack)
    (
      nodeWithStandaloneCorepack.outputs == [
        "out"
        "npm"
      ]
    )
    (nodeWithStandaloneCorepack.npmVersion == "11.18.0")
    (nodeWithStandaloneCorepack ? npm)
    (nodeWithStandaloneCorepack ? corepack)
    ((bun.fromVersion pkgs "latest").version == bun.resolveVersion pkgs "latest")
    ((deno.fromVersion pkgs "lts").version == deno.resolveVersion pkgs "lts")
  ];
in
assert pkgs.lib.all pkgs.lib.id assertions;
pkgs.runCommand "js-toolchain-lib-tests" { } ''
  test "$(${nodeWithBundledCorepack}/bin/node --version)" = "v24.19.0"
  test "$(${nodeWithBundledCorepack.npm}/bin/npm --version)" = "11.17.0"
  ${nodeWithBundledCorepack.corepack}/bin/corepack --version >/dev/null

  test ! -e ${nodeWithBundledCorepack}/bin/npm
  test ! -e ${nodeWithBundledCorepack}/bin/npx
  test ! -e ${nodeWithBundledCorepack}/bin/corepack
  test ! -e ${nodeWithBundledCorepack.corepack}/bin/yarn
  test ! -e ${nodeWithBundledCorepack.corepack}/bin/pnpm

  mkdir corepack-shims-24
  ${nodeWithBundledCorepack.corepack}/bin/corepack enable --install-directory "$PWD/corepack-shims-24"
  test -L corepack-shims-24/yarn
  test -L corepack-shims-24/pnpm

  test "$(${nodeWithStandaloneCorepack}/bin/node --version)" = "v26.6.0"
  test "$(${nodeWithStandaloneCorepack.npm}/bin/npm --version)" = "11.18.0"
  ${nodeWithStandaloneCorepack.corepack}/bin/corepack --version >/dev/null

  test ! -e ${nodeWithStandaloneCorepack}/bin/npm
  test ! -e ${nodeWithStandaloneCorepack}/bin/npx
  test ! -e ${nodeWithStandaloneCorepack}/bin/corepack
  test ! -e ${nodeWithStandaloneCorepack.corepack}/bin/yarn
  test ! -e ${nodeWithStandaloneCorepack.corepack}/bin/pnpm

  mkdir corepack-shims-26
  ${nodeWithStandaloneCorepack.corepack}/bin/corepack enable --install-directory "$PWD/corepack-shims-26"
  test -L corepack-shims-26/yarn
  test -L corepack-shims-26/pnpm

  touch $out
''
