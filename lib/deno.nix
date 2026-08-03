{
  lib,
  catalog,
  project,
}:

let
  data = builtins.fromJSON (builtins.readFile ../versions/deno.json);

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
        inherit (data) latest lts;
        deno = data.latest;
        stable = data.latest;
      };
    };

  versionFromPackageJSON =
    file:
    project.versionFromPackageJSON {
      runtime = "deno";
      inherit file;
    };

  findVersion =
    root:
    project.findFirstVersion [
      (project.readVersionFile "${root}/.dvmrc")
      (project.versionFromToolVersions "deno" "${root}/.tool-versions")
      (versionFromPackageJSON "${root}/package.json")
    ];

  mkDeno =
    pkgs: version:
    let
      release =
        data.releases.${version} or (throw "js-toolchain-overlay: unsupported Deno version ${version}");
      system = pkgs.stdenv.hostPlatform.system;
      artifact =
        release.artifacts.${system}
          or (throw "js-toolchain-overlay: Deno ${version} has no archive for ${system}");
      isGzip = lib.hasSuffix ".gz" artifact.file;
    in
    pkgs.stdenvNoCC.mkDerivation (
      {
        pname = "deno-bin";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/denoland/deno/releases/download/v${version}/${artifact.file}";
          inherit (artifact) hash;
        };

        sourceRoot = ".";
        strictDeps = true;
        nativeBuildInputs = [
          pkgs.unzip
        ]
        ++ lib.optionals isGzip [ pkgs.gzip ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
        buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.stdenv.cc.cc.lib ];

        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          install -Dm755 deno "$out/bin/deno"
          runHook postInstall
        '';

        passthru = {
          inherit (release) date;
          platform = lib.removeSuffix ".zip" artifact.file;
        };

        meta = {
          description = "Deno JavaScript and TypeScript runtime (${version}, official binary distribution)";
          homepage = "https://deno.com/";
          license = lib.licenses.mit;
          mainProgram = "deno";
          platforms = builtins.attrNames release.artifacts;
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        };
      }
      // lib.optionalAttrs isGzip {
        unpackPhase = ''
          runHook preUnpack
          gzip -dc "$src" > deno
          runHook postUnpack
        '';
      }
    );

  packagesByVersionFor =
    pkgs: lib.mapAttrs (version: _: mkDeno pkgs version) (catalog.availableReleasesFor data pkgs);

  fromVersion = pkgs: request: mkDeno pkgs (resolveVersion pkgs request);
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
      lts = versions.${data.lts};
    };

  packagesFor =
    pkgs:
    let
      versions = packagesByVersionFor pkgs;
    in
    catalog.versionedPackages "deno" versions
    // catalog.majorPackages "deno" data versions
    // {
      deno = versions.${data.latest};
      deno_latest = versions.${data.latest};
      deno_lts = versions.${data.lts};
    };

  overlay = final: _: { deno-bin = namespaceFor final; };
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
