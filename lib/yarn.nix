{
  lib,
  catalog,
  project,
}:

let
  data = builtins.fromJSON (builtins.readFile ../versions/yarn.json);

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
        stable = data.latest;
        yarn = data.latest;
      };
    };

  versionFromPackageJSON = project.packageManagerFromPackageJSON "yarn";

  findVersion =
    root:
    project.findFirstVersion [
      (project.versionFromToolVersions "yarn" "${root}/.tool-versions")
      (versionFromPackageJSON "${root}/package.json")
    ];

  mkPackage =
    pkgs: version:
    lib.makeOverridable (
      {
        nodejs ? pkgs.nodejs,
      }:
      let
        release = data.releases.${version};
        system = pkgs.stdenv.hostPlatform.system;
        artifact = release.artifacts.${system};
      in
      pkgs.stdenvNoCC.mkDerivation {
        pname = "yarn-bin";
        inherit version;

        src = pkgs.fetchurl { inherit (artifact) url hash; };

        sourceRoot = "package";
        strictDeps = true;
        nativeBuildInputs = [ pkgs.makeWrapper ];

        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          install -Dm644 bin/yarn.js "$out/lib/yarn/yarn.js"
          makeWrapper ${lib.getExe nodejs} "$out/bin/yarn" \
            --add-flags "$out/lib/yarn/yarn.js" \
            --set YARN_IGNORE_PATH 1 \
            --prefix PATH : ${lib.makeBinPath [ nodejs ]}
          ln -s yarn "$out/bin/yarnpkg"
          runHook postInstall
        '';

        passthru = {
          inherit (release) date;
          inherit nodejs;
        };

        meta = {
          description = "Yarn package manager (${version}, official CLI distribution)";
          homepage = "https://yarnpkg.com/";
          license = lib.licenses.bsd2;
          mainProgram = "yarn";
          platforms = builtins.attrNames release.artifacts;
        };
      }
    ) { };

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
    catalog.versionedPackages "yarn" versions
    // catalog.majorPackages "yarn" data versions
    // {
      yarn = versions.${data.latest};
      yarn_latest = versions.${data.latest};
    };

  overlay = final: _: { yarn-bin = namespaceFor final; };
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
