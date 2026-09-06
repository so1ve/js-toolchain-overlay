{
  lib,
  catalog,
  project,
}:

let
  data = builtins.fromJSON (builtins.readFile ../versions/pnpm.json);

  supportedSystems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  resolveVersion =
    pkgs: request:
    catalog.resolveVersion {
      inherit data pkgs request;
      aliases = {
        inherit (data) latest;
        pnpm = data.latest;
      };
    };

  versionFromPackageJSON = project.packageManagerFromPackageJSON "pnpm";

  findVersion =
    root:
    project.findFirstVersion [
      (project.versionFromToolVersions "pnpm" "${root}/.tool-versions")
      (versionFromPackageJSON "${root}/package.json")
    ];

  mkPackage =
    pkgs: version:
    let
      release = data.releases.${version};
      system = pkgs.stdenv.hostPlatform.system;
      artifact = release.artifacts.${system};
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "pnpm-bin";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/pnpm/pnpm/releases/download/v${version}/${artifact.file}";
        inherit (artifact) hash;
      };

      sourceRoot = ".";
      strictDeps = true;
      nativeBuildInputs = [
        pkgs.makeWrapper
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
      buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.stdenv.cc.cc.lib ];

      dontConfigure = true;
      dontBuild = true;
      # The optional JS helpers use the project's Node from PATH.
      dontPatchShebangs = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/lib/pnpm" "$out/bin"
        cp -a pnpm dist "$out/lib/pnpm/"
        makeWrapper "$out/lib/pnpm/pnpm" "$out/bin/pnpm" \
          --set pnpm_config_pm_on_fail ignore \
          --set pnpm_config_runtime_on_fail ignore
        makeWrapper "$out/lib/pnpm/pnpm" "$out/bin/pnpx" \
          --set pnpm_config_pm_on_fail ignore \
          --set pnpm_config_runtime_on_fail ignore \
          --add-flags dlx
        runHook postInstall
      '';

      passthru = { inherit (release) date; };

      meta = {
        description = "pnpm package manager (${version}, official native distribution)";
        homepage = "https://pnpm.io/";
        license = lib.licenses.mit;
        mainProgram = "pnpm";
        platforms = builtins.attrNames release.artifacts;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    };

  packagesByVersionFor =
    pkgs: lib.mapAttrs (version: _: mkPackage pkgs version) (catalog.availableReleasesFor data pkgs);

  fromVersion = pkgs: request: mkPackage pkgs (resolveVersion pkgs request);
  fromOptionalVersion = pkgs: version: if version == null then null else fromVersion pkgs version;
  fromVersionFile = pkgs: file: fromOptionalVersion pkgs (project.readVersionFile file);
  fromPackageJSON = pkgs: file: fromOptionalVersion pkgs (versionFromPackageJSON file);
  fromProject = pkgs: root: fromOptionalVersion pkgs (findVersion root);

  namespaceFor =
    pkgs:
    let
      versions = packagesByVersionFor pkgs;
      availableMajors = lib.filterAttrs (_: version: builtins.hasAttr version versions) data.majors;
    in
    {
      inherit versions;
      fromVersion = fromVersion pkgs;
      fromVersionFile = fromVersionFile pkgs;
      fromPackageJSON = fromPackageJSON pkgs;
      fromProject = fromProject pkgs;
      resolveVersion = resolveVersion pkgs;
      majors = lib.mapAttrs (_: version: versions.${version}) availableMajors;
      latest = versions.${data.latest};
    };

  packagesFor =
    pkgs:
    let
      versions = packagesByVersionFor pkgs;
    in
    catalog.versionedPackages "pnpm" versions
    // catalog.majorPackages "pnpm" data versions
    // {
      pnpm = versions.${data.latest};
      pnpm_latest = versions.${data.latest};
    };

  overlay = final: _: { pnpm-bin = namespaceFor final; };
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
