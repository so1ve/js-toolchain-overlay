{
  pkgs,
  toolchains,
}:

let
  overlayPkgs = pkgs.extend toolchains.overlay;
  inherit (overlayPkgs) pnpm-bin yarn-bin;
  node = overlayPkgs.node-bin.fromVersion "24.19.0";
  pnpm = pnpm-bin.fromProject ./fixtures/package-managers/pnpm;
  yarn = (yarn-bin.fromProject ./fixtures/package-managers/yarn).override { nodejs = node; };
  packages = toolchains.packagesFor pkgs;

  assertions = [
    ((pnpm-bin.fromPackageJSON ./fixtures/package-manager-hash.json).version == "12.0.0")
    ((yarn-bin.fromPackageJSON ./fixtures/package-managers/pnpm/package.json) == null)
    ((pnpm-bin.fromPackageJSON ./fixtures/package-managers/yarn/package.json) == null)
    ((pnpm-bin.fromPackageJSON ./fixtures/node-package.json) == null)
    ((yarn-bin.fromProject ./fixtures/package-managers/dependency) == null)
    ((pnpm-bin.fromPackageJSON ./fixtures/missing-package.json) == null)
    ((pnpm-bin.fromPackageJSON ./fixtures/package-manager-engines.json).version == pnpm.version)
    (
      (yarn-bin.fromPackageJSON ./fixtures/package-manager-engines.json).version
      == yarn-bin.latest.version
    )
    ((pnpm-bin.fromPackageJSON ./fixtures/package-manager-precedence/package.json).version == "12.0.0")
    ((yarn-bin.fromPackageJSON ./fixtures/package-manager-precedence/package.json).version == "4.18.0")
    ((pnpm-bin.fromPackageJSON ./fixtures/package-manager-array.json).version == "12.0.0")
    ((yarn-bin.fromPackageJSON ./fixtures/package-manager-array.json).version == "4.18.0")
    ((pnpm-bin.fromProject ./fixtures/package-manager-precedence).version == "12.0.0")
    ((yarn-bin.fromProject ./fixtures/package-manager-precedence).version == "3.8.7")
    (pnpm-bin.resolveVersion "12" == pnpm.version)
    (pnpm-bin.resolveVersion "12.x.x" == pnpm.version)
    (!(builtins.tryEval (pnpm-bin.resolveVersion "12.0.0-rc.1")).success)
    (!(builtins.tryEval (yarn-bin.resolveVersion "4.18.0-invalid")).success)
    (yarn-bin.resolveVersion "stable" == yarn-bin.latest.version)
    (packages.pnpm.version == pnpm.version)
    (packages.pnpm_12_0_0.version == "12.0.0")
    (packages.yarn_4_18_0.version == "4.18.0")
    (packages.yarn_4.version == yarn-bin.latest.version)
    ((toolchains.publicLib.pnpm.fromVersion pkgs "12").version == pnpm.version)
    ((toolchains.publicLib.yarn.fromVersion pkgs "4").version == yarn-bin.latest.version)
    (yarn.nodejs == node)
  ];
in
assert pkgs.lib.all pkgs.lib.id assertions;
pkgs.runCommand "js-toolchain-package-manager-tests" { nativeBuildInputs = [ node ]; } ''
  export XDG_CACHE_HOME="$TMPDIR/cache"
  export XDG_CONFIG_HOME="$TMPDIR/config"
  export XDG_DATA_HOME="$TMPDIR/data"
  export PNPM_HOME="$TMPDIR/pnpm-home"
  cp -R ${./fixtures/package-managers} project
  chmod -R u+w project

  # pnpm's native CLI also starts without Node on PATH.
  test "$(PATH= ${pnpm}/bin/pnpm --version)" = "${pnpm.version}"
  ${pnpm}/bin/pnpx --help > /dev/null
  cd project/pnpm
  ${pnpm}/bin/pnpm install --offline --ignore-scripts
  ${pnpm}/bin/pnpm install --offline --frozen-lockfile --ignore-scripts
  ${pnpm}/bin/pnpm run check | grep -F '${node}/bin/node'

  node -e '
    const fs = require("node:fs");
    const manifest = JSON.parse(fs.readFileSync("package.json"));
    manifest.devEngines.packageManager.version = "99.0.0";
    fs.writeFileSync("package.json", JSON.stringify(manifest));
  '
    # A changed pin must not download or switch away from the Nix-selected tool.
    ${pnpm}/bin/pnpm install --offline --frozen-lockfile --ignore-scripts
    ${pnpm}/bin/pnpm run check | grep -F '${node}/bin/node'
    test "$(${pnpm}/bin/pnpm --version)" = "${pnpm.version}"

  cd ../yarn
  test "$(${yarn}/bin/yarn --version)" = "${yarn.version}"
  test "$(${yarn}/bin/yarnpkg --version)" = "${yarn.version}"
  ${yarn}/bin/yarn install
  ${yarn}/bin/yarn install --immutable
  ${yarn}/bin/yarn run check | grep -F '${node}/bin/node'

  touch "$out"
''
