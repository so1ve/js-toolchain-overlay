{
  lib,
  semver,
}:

let
  availableReleasesFor =
    data: pkgs:
    let
      system = pkgs.stdenv.hostPlatform.system;
    in
    lib.filterAttrs (_: release: builtins.hasAttr system release.artifacts) data.releases;

  availableVersionsFor = data: pkgs: builtins.attrNames (availableReleasesFor data pkgs);

  resolveVersion =
    {
      data,
      pkgs,
      request,
      aliases,
      versions ? availableVersionsFor data pkgs,
    }:
    let
      value = lib.strings.trim request;
      alias = lib.toLower value;
      normalized = aliases.${alias} or value;
    in
    semver.resolve versions normalized;

  packageName =
    prefix: version: "${prefix}_${lib.replaceStrings [ "." "-" "+" ] [ "_" "_" "_" ] version}";

  versionedPackages =
    prefix: versions:
    lib.mapAttrs' (version: package: lib.nameValuePair (packageName prefix version) package) versions;

  majorPackages =
    prefix: data: versions:
    let
      availableMajors = lib.filterAttrs (_: version: builtins.hasAttr version versions) data.majors;
    in
    lib.mapAttrs' (
      major: version: lib.nameValuePair "${prefix}_${major}" versions.${version}
    ) availableMajors;
in
{
  inherit
    availableReleasesFor
    availableVersionsFor
    majorPackages
    packageName
    resolveVersion
    versionedPackages
    ;
}
