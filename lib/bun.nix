{
  lib,
  catalog,
  project,
}:

let
  data = builtins.fromJSON (builtins.readFile ../versions/bun.json);

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
        bun = data.latest;
      };
    };

  versionFromPackageJSON =
    file:
    project.versionFromPackageJSON {
      runtime = "bun";
      inherit file;
      selectors = [ (project.packageManagerVersion "bun") ];
    };

  findVersion =
    root:
    project.findFirstVersion [
      (project.readVersionFile "${root}/.bun-version")
      (project.versionFromToolVersions "bun" "${root}/.tool-versions")
      (versionFromPackageJSON "${root}/package.json")
    ];

  mkBun =
    pkgs: version:
    let
      release =
        data.releases.${version} or (throw "js-toolchain-overlay: unsupported Bun version ${version}");
      system = pkgs.stdenv.hostPlatform.system;
      artifact =
        release.artifacts.${system}
          or (throw "js-toolchain-overlay: Bun ${version} has no archive for ${system}");
      isTarball = lib.hasSuffix ".tgz" artifact.file;
      binary = if isTarball then "bin/bun" else "bun";
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "bun-bin";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/${artifact.file}";
        inherit (artifact) hash;
      };

      sourceRoot = if isTarball then "package" else lib.removeSuffix ".zip" artifact.file;
      strictDeps = true;
      nativeBuildInputs = [
        pkgs.unzip
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
        pkgs.cctools
        pkgs.rcodesign
      ];
      buildInputs = [
        pkgs.openssl
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.darwin.ICU ];

      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        install -Dm755 ${binary} "$out/bin/bun"
        ln -s bun "$out/bin/bunx"
        runHook postInstall
      '';

      postFixup = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
        '${lib.getExe' pkgs.cctools "${pkgs.cctools.targetPrefix}install_name_tool"}' "$out/bin/bun" \
          -change /usr/lib/libicucore.A.dylib '${lib.getLib pkgs.darwin.ICU}/lib/libicucore.A.dylib'
        '${lib.getExe pkgs.rcodesign}' sign --code-signature-flags linker-signed "$out/bin/bun"
      '';

      passthru = {
        inherit (release) date;
        platform = lib.removeSuffix ".zip" artifact.file;
      };

      meta = {
        description = "Bun JavaScript runtime and toolkit (${version}, official binary distribution)";
        homepage = "https://bun.sh/";
        license = [
          lib.licenses.mit
          lib.licenses.lgpl21Only
        ];
        mainProgram = "bun";
        platforms = builtins.attrNames release.artifacts;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    };

  packagesByVersionFor =
    pkgs: lib.mapAttrs (version: _: mkBun pkgs version) (catalog.availableReleasesFor data pkgs);

  fromVersion = pkgs: request: mkBun pkgs (resolveVersion pkgs request);
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
    catalog.versionedPackages "bun" versions
    // catalog.majorPackages "bun" data versions
    // {
      bun = versions.${data.latest};
      bun_latest = versions.${data.latest};
    };

  overlay = final: _: { bun-bin = namespaceFor final; };
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
