{ lib }:

let
  nonEmptyString = value: builtins.isString value && lib.strings.trim value != "";

  readJSON =
    file: if builtins.pathExists file then builtins.fromJSON (builtins.readFile file) else null;

  readVersionFile =
    file:
    if builtins.pathExists file then
      let
        version = lib.strings.trim (builtins.readFile file);
      in
      if version == "" then null else version
    else
      null;

  words =
    line:
    lib.filter (value: value != "") (
      lib.splitString " " (lib.replaceStrings [ "\t" ] [ " " ] (lib.strings.trim line))
    );

  versionFromToolVersionsText =
    tool: text:
    let
      lines = lib.splitString "\n" text;
      matching = lib.findFirst (
        line:
        let
          parts = words line;
        in
        builtins.length parts >= 2 && lib.head parts == tool
      ) null lines;
    in
    if matching == null then null else builtins.elemAt (words matching) 1;

  versionFromToolVersions =
    tool: file:
    if builtins.pathExists file then
      versionFromToolVersionsText tool (builtins.readFile file)
    else
      null;

  packageManagerVersion =
    manager: package:
    let
      specifier = package.packageManager or null;
      prefix = "${manager}@";
    in
    if builtins.isString specifier && lib.hasPrefix prefix specifier then
      lib.head (lib.splitString "+" (lib.removePrefix prefix specifier))
    else
      null;

  runtimeFromDevEngines =
    runtimeName: package:
    let
      runtimes = package.devEngines.runtime or [ ];
      matches = value: builtins.isAttrs value && (value.name or null) == runtimeName;
      runtime =
        if builtins.isList runtimes then
          lib.findFirst matches null runtimes
        else if matches runtimes then
          runtimes
        else
          null;
    in
    if runtime != null && runtime ? version then runtime.version else null;

  versionFromPackage =
    {
      runtime,
      package,
      selectors,
    }:
    lib.findFirst nonEmptyString null (
      map (selector: selector package) selectors
      ++ [
        (runtimeFromDevEngines runtime package)
        (package.engines.${runtime} or null)
      ]
    );

  versionFromPackageJSON =
    {
      runtime,
      file,
      selectors ? [ ],
    }:
    let
      package = readJSON file;
    in
    if package == null then null else versionFromPackage { inherit runtime package selectors; };

  findFirstVersion = values: lib.findFirst nonEmptyString null values;
in
{
  inherit
    findFirstVersion
    packageManagerVersion
    readJSON
    readVersionFile
    versionFromPackage
    versionFromPackageJSON
    versionFromToolVersions
    versionFromToolVersionsText
    ;
}
