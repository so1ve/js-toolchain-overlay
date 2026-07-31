{ lib }:

let
  data = builtins.fromJSON (builtins.readFile ../versions.json);
  resolver = import ./resolve.nix { inherit lib; };

  platforms = {
    aarch64-darwin = "darwin-arm64";
    aarch64-linux = "linux-arm64";
    x86_64-linux = "linux-x64";
  };

  supportedSystems = builtins.attrNames platforms;

  availableVersionsFor =
    pkgs:
    let
      system = pkgs.stdenv.hostPlatform.system;
    in
    builtins.attrNames (
      lib.filterAttrs (_: release: builtins.hasAttr system release.artifacts) data.releases
    );

  resolveVersion =
    pkgs: request:
    let
      value = lib.strings.trim request;
      alias = lib.toLower value;
      versions = availableVersionsFor pkgs;
      ltsName = lib.removePrefix "lts/" alias;
      matchingLts = lib.filter (
        version:
        let
          lts = data.releases.${version}.lts;
        in
        lts != false && lib.toLower lts == ltsName
      ) versions;
      candidates = if lib.hasPrefix "lts/" alias then matchingLts else versions;
      normalized =
        if
          builtins.elem alias [
            "latest"
            "node"
          ]
        then
          data.latest
        else if
          builtins.elem alias [
            "lts"
            "lts/*"
          ]
        then
          data.lts
        else if lib.hasPrefix "lts/" alias then
          "*"
        else
          value;
    in
    resolver.resolve candidates normalized;

  nodeVersionFromPackage =
    package:
    let
      runtimes = package.devEngines.runtime or [ ];
      runtime =
        if builtins.isList runtimes then
          lib.findFirst (value: value.name == "node") null runtimes
        else
          runtimes;
    in
    if package ? volta.node then
      package.volta.node
    else if runtime != null && runtime.name == "node" && runtime ? version then
      runtime.version
    else
      package.engines.node or null;

  nodeVersionFromPackageJSON =
    file:
    if builtins.pathExists file then
      nodeVersionFromPackage (builtins.fromJSON (builtins.readFile file))
    else
      null;

  nodeVersionFromFile =
    file:
    if builtins.pathExists file then
      let
        version = lib.strings.trim (builtins.readFile file);
      in
      if version == "" then null else version
    else
      null;

  findNodeVersion =
    root:
    let
      file = name: "${toString root}/${name}";
      versions = [
        (nodeVersionFromFile (file ".node-version"))
        (nodeVersionFromFile (file ".nvmrc"))
        (nodeVersionFromPackageJSON (file "package.json"))
      ];
    in
    lib.findFirst (version: version != null) null versions;

  fromNodeVersion = pkgs: request: mkNodejs pkgs (resolveVersion pkgs request);
  fromOptionalNodeVersion =
    pkgs: version: if version == null then null else fromNodeVersion pkgs version;
  fromNodeVersionFile = pkgs: file: fromOptionalNodeVersion pkgs (nodeVersionFromFile file);
  fromPackageJSON = pkgs: file: fromOptionalNodeVersion pkgs (nodeVersionFromPackageJSON file);
  fromProject = pkgs: root: fromOptionalNodeVersion pkgs (findNodeVersion root);

  mkNodejs =
    pkgs: version:
    let
      release =
        data.releases.${version} or (throw "node-overlay: unsupported Node.js version ${version}");
      system = pkgs.stdenv.hostPlatform.system;
      platform = platforms.${system} or (throw "node-overlay: unsupported system ${system}");
      artifact =
        release.artifacts.${system}
          or (throw "node-overlay: Node.js ${version} has no archive for ${system}");
      bundlesCorepack = lib.versionAtLeast version "14.19.0" && lib.versionOlder version "25.0.0";
      supportsStandaloneCorepack = lib.versionAtLeast version "25.0.0";
    in
    pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "nodejs-bin";
      inherit version;

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
        while IFS= read -r script; do
          substituteInPlace "$script" \
            --replace-fail '#!/usr/bin/env node' "#!$out/bin/node"
        done < <(grep -rl '^#!/usr/bin/env node$' "$out")
      '';

      passthru = {
        inherit (release) date lts npm;
        inherit platform;
      }
      // lib.optionalAttrs bundlesCorepack {
        corepack = finalAttrs.finalPackage;
      }
      // lib.optionalAttrs supportsStandaloneCorepack {
        corepack = pkgs.corepack.override { nodejs-slim = finalAttrs.finalPackage; };
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

  packagesFor =
    pkgs:
    let
      system = pkgs.stdenv.hostPlatform.system;
      availableReleases = lib.filterAttrs (
        _: release: builtins.hasAttr system release.artifacts
      ) data.releases;
      versions = lib.mapAttrs (version: _: mkNodejs pkgs version) availableReleases;
      versionedPackages = lib.mapAttrs' (
        version: package: lib.nameValuePair "nodejs_${lib.replaceStrings [ "." ] [ "_" ] version}" package
      ) versions;
      availableMajors = lib.filterAttrs (_: version: builtins.hasAttr version versions) data.majors;
      majorPackages = lib.mapAttrs' (
        major: version: lib.nameValuePair "nodejs_${major}" versions.${version}
      ) availableMajors;
    in
    versionedPackages
    // majorPackages
    // {
      default = versions.${data.latest};
      latest = versions.${data.latest};
      lts = versions.${data.lts};
    };

  overlay =
    final: _:
    let
      system = final.stdenv.hostPlatform.system;
      availableReleases = lib.filterAttrs (
        _: release: builtins.hasAttr system release.artifacts
      ) data.releases;
      versions = lib.mapAttrs (version: _: mkNodejs final version) availableReleases;
      availableMajors = lib.filterAttrs (_: version: builtins.hasAttr version versions) data.majors;
    in
    {
      nodejs-bin = {
        inherit versions;
        fromNodeVersion = fromNodeVersion final;
        fromNodeVersionFile = fromNodeVersionFile final;
        fromPackageJSON = fromPackageJSON final;
        fromProject = fromProject final;
        resolveVersion = resolveVersion final;
        majors = lib.mapAttrs (_: version: versions.${version}) availableMajors;
        latest = versions.${data.latest};
        lts = versions.${data.lts};
      };
    };
in
{
  inherit
    data
    fromNodeVersion
    fromNodeVersionFile
    fromPackageJSON
    fromProject
    mkNodejs
    overlay
    packagesFor
    resolveVersion
    supportedSystems
    ;
}
