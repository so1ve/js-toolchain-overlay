{
  lib,
  catalog,
  project,
}:

let
  data = builtins.fromJSON (builtins.readFile ../versions/node.json);

  platforms = {
    aarch64-darwin = "darwin-arm64";
    aarch64-linux = "linux-arm64";
    x86_64-linux = "linux-x64";
  };

  supportedSystems = builtins.attrNames platforms;

  resolveVersion =
    pkgs: request:
    let
      value = lib.strings.trim request;
      alias = lib.toLower value;
      versions = catalog.availableVersionsFor data pkgs;
      ltsName = lib.removePrefix "lts/" alias;
      matchingLts = lib.filter (
        version:
        let
          lts = data.releases.${version}.lts;
        in
        lts != false && lib.toLower lts == ltsName
      ) versions;
      candidates = if lib.hasPrefix "lts/" alias then matchingLts else versions;
      normalized = if lib.hasPrefix "lts/" alias then "*" else value;
    in
    catalog.resolveVersion {
      inherit data pkgs;
      request = normalized;
      versions = candidates;
      aliases = {
        inherit (data) latest lts;
        node = data.latest;
        "lts/*" = data.lts;
      };
    };

  versionFromPackageJSON =
    file:
    project.versionFromPackageJSON {
      runtime = "node";
      inherit file;
      selectors = [ (value: value.volta.node or null) ];
    };

  findVersion =
    root:
    project.findFirstVersion [
      (project.readVersionFile "${root}/.node-version")
      (project.readVersionFile "${root}/.nvmrc")
      (project.versionFromToolVersions "nodejs" "${root}/.tool-versions")
      (versionFromPackageJSON "${root}/package.json")
    ];

  mkPackage =
    pkgs: version:
    let
      release =
        data.releases.${version} or (throw "js-toolchain-overlay: unsupported Node.js version ${version}");
      system = pkgs.stdenv.hostPlatform.system;
      platform = platforms.${system} or (throw "js-toolchain-overlay: unsupported system ${system}");
      artifact =
        release.artifacts.${system}
          or (throw "js-toolchain-overlay: Node.js ${version} has no archive for ${system}");
      bundlesNpm = release.npm != null;
      bundlesCorepack =
        (lib.versionAtLeast version "14.19.0" && lib.versionOlder version "15.0.0")
        || (lib.versionAtLeast version "16.9.0" && lib.versionOlder version "25.0.0");
      supportsStandaloneCorepack = lib.versionAtLeast version "25.0.0";
    in
    pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "node-bin";
      inherit version;

      outputs = [ "out" ] ++ lib.optional bundlesNpm "npm" ++ lib.optional bundlesCorepack "corepack";

      src = pkgs.fetchurl {
        url = "https://nodejs.org/dist/v${version}/${artifact.file}";
        inherit (artifact) hash;
      };

      nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
      buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.stdenv.cc.cc.lib ];

      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -a . "$out/"
        runHook postInstall
      '';

      postInstall = ''
        scriptRoots=("$out")

        ${lib.optionalString bundlesNpm ''
          mkdir -p "$npm/bin" "$npm/lib/node_modules"
          mv "$out/bin/npm" "$out/bin/npx" "$npm/bin/"
          mv "$out/lib/node_modules/npm" "$npm/lib/node_modules/"
          scriptRoots+=("$npm")
        ''}

        ${lib.optionalString bundlesCorepack ''
          mkdir -p "$corepack/bin" "$corepack/lib/node_modules"
          mv "$out/bin/corepack" "$corepack/bin/"
          mv "$out/lib/node_modules/corepack" "$corepack/lib/node_modules/"
          scriptRoots+=("$corepack")
        ''}

        while IFS= read -r script; do
          substituteInPlace "$script" \
            --replace-fail '#!/usr/bin/env node' "#!$out/bin/node"
        done < <(grep -rl '^#!/usr/bin/env node$' "''${scriptRoots[@]}")
      '';

      passthru = {
        inherit (release) date lts;
        inherit platform;
        npmVersion = release.npm;
      }
      // lib.optionalAttrs supportsStandaloneCorepack {
        corepack =
          let
            unwrapped = pkgs.corepack.override { nodejs-slim = finalAttrs.finalPackage; };
          in
          pkgs.runCommand "corepack-${unwrapped.version}-for-node-${version}"
            {
              inherit (unwrapped) meta version;
              passthru = { inherit unwrapped; };
            }
            ''
              mkdir -p "$out/bin"
              ln -s ${lib.getExe unwrapped} "$out/bin/corepack"
            '';
      };

      meta = {
        description = "Node.js JavaScript runtime (${version}, official binary distribution)";
        homepage = "https://nodejs.org/";
        license = lib.licenses.mit;
        mainProgram = "node";
        platforms = builtins.attrNames release.artifacts;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    });

  packagesByVersionFor =
    pkgs: lib.mapAttrs (version: _: mkPackage pkgs version) (catalog.availableReleasesFor data pkgs);

  namespaceFor =
    pkgs:
    let
      versions = packagesByVersionFor pkgs;
      availableMajors = lib.filterAttrs (_: version: builtins.hasAttr version versions) data.majors;
    in
    {
      inherit versions;
      fromVersion = request: mkPackage pkgs (resolveVersion pkgs request);
      fromVersionFile = file: fromOptionalVersion pkgs (project.readVersionFile file);
      fromPackageJSON = file: fromOptionalVersion pkgs (versionFromPackageJSON file);
      fromProject = root: fromOptionalVersion pkgs (findVersion root);
      resolveVersion = resolveVersion pkgs;
      majors = lib.mapAttrs (_: version: versions.${version}) availableMajors;
      latest = versions.${data.latest};
      lts = versions.${data.lts};
    };

  fromVersion = pkgs: request: mkPackage pkgs (resolveVersion pkgs request);
  fromOptionalVersion = pkgs: version: if version == null then null else fromVersion pkgs version;
  fromVersionFile = pkgs: file: fromOptionalVersion pkgs (project.readVersionFile file);
  fromPackageJSON = pkgs: file: fromOptionalVersion pkgs (versionFromPackageJSON file);
  fromProject = pkgs: root: fromOptionalVersion pkgs (findVersion root);

  packagesFor =
    pkgs:
    let
      versions = packagesByVersionFor pkgs;
    in
    catalog.versionedPackages "node" versions
    // catalog.majorPackages "node" data versions
    // {
      node = versions.${data.latest};
      node_latest = versions.${data.latest};
      node_lts = versions.${data.lts};
    };

  overlay = final: _: { node-bin = namespaceFor final; };
in
{
  inherit
    fromPackageJSON
    fromProject
    fromVersion
    fromVersionFile
    overlay
    packagesFor
    resolveVersion
    supportedSystems
    ;
}
