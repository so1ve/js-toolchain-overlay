{
  pkgs,
  nodejs,
  name,
  version,
  release,
  environment,
}:

let
  inherit (pkgs) lib;
  artifact = release.artifacts.${pkgs.stdenv.hostPlatform.system};
  bundle = lib.hasSuffix ".js" artifact.url;
  runtimePath = lib.makeBinPath (
    [ nodejs ] ++ lib.optionals (name == "pnpm" && lib.versionOlder version "0.25.0") [ pkgs.which ]
  );
  wrapperArgs = lib.concatStringsSep " " (
    lib.mapAttrsToList (
      key: value: "--set ${lib.escapeShellArg key} ${lib.escapeShellArg value}"
    ) environment
  );
  packageLock = builtins.fromJSON (builtins.readFile (../versions + "/${release.npmLock}"));
  dependencies = pkgs.importNpmLock.buildNodeModules {
    nodejs = pkgs.nodejs;
    inherit packageLock;
    package = packageLock.packages."";
    derivationArgs.npmFlags = [
      "--ignore-scripts"
      "--legacy-peer-deps"
    ];
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "${name}-bin";
  inherit version;
  src = pkgs.fetchurl { inherit (artifact) url hash; };
  dontUnpack = bundle;
  strictDeps = true;
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.nodejs
  ];
  dontConfigure = true;
  dontBuild = true;
  dontPatchShebangs = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/${name}" "$out/bin"
  ''
  + (
    if bundle then
      ''
        install -Dm644 "$src" "$out/lib/${name}/${name}.js"
        makeWrapper ${lib.getExe nodejs} "$out/bin/${name}" \
          --add-flags "$out/lib/${name}/${name}.js" \
          --prefix PATH : ${runtimePath} ${wrapperArgs}
      ''
    else
      ''
        cp -a . "$out/lib/${name}/"
        ${lib.optionalString (release ? npmLock) ''
          cp -a ${dependencies}/node_modules "$out/lib/${name}/"
        ''}
        chmod -R u+w "$out/lib/${name}"
        PATH=${lib.makeBinPath [ nodejs ]}:$PATH patchShebangs --build --update "$out/lib/${name}"
        while IFS=$'\t' read -r command entry; do
          chmod +x "$out/lib/${name}/$entry"
          makeWrapper "$out/lib/${name}/$entry" "$out/bin/$command" \
            --prefix PATH : "$out/bin:${runtimePath}" ${wrapperArgs}
        done < <(${lib.getExe pkgs.nodejs} -e '
          const p = require("./package.json");
          const bins = typeof p.bin === "string" ? { [p.name]: p.bin } : p.bin;
          for (const [name, entry] of Object.entries(bins)) console.log(name + "\t" + entry);
        ')
        ${lib.optionalString (name == "yarn") ''
          if [ ! -e "$out/bin/yarn" ]; then
            if [ -e "$out/bin/kpm" ]; then
              ln -s kpm "$out/bin/yarn"
            else
              ln -s fb-kpm "$out/bin/yarn"
            fi
          fi
        ''}
      ''
  )
  + ''
    ${lib.optionalString (name == "yarn") ''
      if [ ! -e "$out/bin/yarnpkg" ]; then
        ln -s yarn "$out/bin/yarnpkg"
      fi
    ''}
    test -x "$out/bin/${name}"
    runHook postInstall
  '';

  passthru = {
    inherit (release) date;
    inherit nodejs;
  };
  meta = {
    description = "${name} package manager (${version}, official CLI distribution)";
    homepage = if name == "pnpm" then "https://pnpm.io/" else "https://yarnpkg.com/";
    license = if name == "pnpm" then lib.licenses.mit else lib.licenses.bsd2;
    mainProgram = name;
    platforms = builtins.attrNames release.artifacts;
  };
}
