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
  nodeOutputs = [
    "out"
    "npm"
  ];
  checkNodeOutputs = nodePackage: ''
    test "$(${nodePackage}/bin/node --version)" = "v${nodePackage.version}"
    test "$(${nodePackage.npm}/bin/npm --version)" = "${nodePackage.npmVersion}"
    test "$(${nodePackage.npm}/bin/npx --version)" = "${nodePackage.npmVersion}"

    for executable in npm npx; do
      test ! -e "${nodePackage}/bin/$executable"
    done
  '';
  checkCorepack =
    nodePackage:
    let
      shims = "corepack-shims-${nodePackage.version}";
    in
    ''
      test ! -e "${nodePackage}/bin/corepack"

      for executable in yarn pnpm; do
        test ! -e "${nodePackage.corepack}/bin/$executable"
      done

      mkdir "${shims}"
      ${nodePackage.corepack}/bin/corepack enable --install-directory "$PWD/${shims}"
      test -L "${shims}/yarn"
      test -L "${shims}/pnpm"
    '';

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
    (nodeWithoutCorepack.outputs == nodeOutputs)
    (!(nodeWithoutCorepack ? corepack))
    (nodeWithBundledCorepack.outputs == nodeOutputs ++ [ "corepack" ])
    (nodeWithStandaloneCorepack.outputs == nodeOutputs)
    (nodeWithStandaloneCorepack ? corepack)
    ((bun.fromVersion pkgs "latest").version == bun.resolveVersion pkgs "latest")
    ((deno.fromVersion pkgs "lts").version == deno.resolveVersion pkgs "lts")
  ];
in
assert pkgs.lib.all pkgs.lib.id assertions;
pkgs.runCommand "js-toolchain-lib-tests" { } ''
  ${checkNodeOutputs nodeWithBundledCorepack}
  ${checkCorepack nodeWithBundledCorepack}
  ${checkCorepack nodeWithStandaloneCorepack}

  touch $out
''
