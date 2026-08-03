{ lib }:

let
  trim = lib.strings.trim;
  compare = builtins.compareVersions;

  takeNumbers =
    parts:
    if parts == [ ] || builtins.match "[0-9]+" (lib.head parts) == null then
      [ ]
    else
      [ (lib.head parts) ] ++ takeNumbers (lib.tail parts);

  parse =
    value:
    let
      parts = lib.splitString "." (lib.removePrefix "v" (trim value));
      numbers = takeNumbers parts;
      precision = builtins.length numbers;
      normalized = lib.take 3 (
        numbers
        ++ [
          "0"
          "0"
          "0"
        ]
      );
    in
    {
      inherit precision;
      numbers = map lib.toInt normalized;
      version = lib.concatStringsSep "." normalized;
    };

  bump =
    parsed: index:
    lib.concatStringsSep "." (
      lib.imap0 (
        current: number:
        toString (
          if current == index then
            number + 1
          else if current > index then
            0
          else
            number
        )
      ) parsed.numbers
    );

  matchesToken =
    version: value:
    let
      token = trim value;
      operator = lib.findFirst (prefix: lib.hasPrefix prefix token) "" [
        ">="
        "<="
        ">"
        "<"
        "^"
        "~"
        "="
      ];
      parsed = parse (lib.removePrefix operator token);
      upper = bump parsed (parsed.precision - 1);
      caretIndex =
        if parsed.precision == 1 || builtins.elemAt parsed.numbers 0 != 0 then
          0
        else if parsed.precision == 2 || builtins.elemAt parsed.numbers 1 != 0 then
          1
        else
          2;
      tildeIndex = if parsed.precision == 1 then 0 else 1;
    in
    if
      builtins.elem token [
        "*"
        "x"
        "X"
      ]
    then
      true
    else if parsed.precision == 0 then
      false
    else if operator == ">=" then
      compare version parsed.version >= 0
    else if operator == ">" then
      if parsed.precision < 3 then compare version upper >= 0 else compare version parsed.version > 0
    else if operator == "<=" then
      if parsed.precision < 3 then compare version upper < 0 else compare version parsed.version <= 0
    else if operator == "<" then
      compare version parsed.version < 0
    else if operator == "^" then
      compare version parsed.version >= 0 && compare version (bump parsed caretIndex) < 0
    else if operator == "~" then
      compare version parsed.version >= 0 && compare version (bump parsed tildeIndex) < 0
    else if parsed.precision < 3 then
      compare version parsed.version >= 0 && compare version upper < 0
    else
      compare version parsed.version == 0;

  matchesAlternative =
    version: value:
    let
      range = trim value;
      hyphen = builtins.match "([^ ]+) +- +([^ ]+)" range;
      tokens = lib.filter (token: token != "") (lib.splitString " " range);
    in
    if hyphen != null then
      matchesToken version ">=${builtins.elemAt hyphen 0}"
      && matchesToken version "<=${builtins.elemAt hyphen 1}"
    else
      lib.all (matchesToken version) tokens;

  resolve =
    versions: request:
    let
      normalized = trim request;
      matches = lib.filter (
        version: lib.any (matchesAlternative version) (lib.splitString "||" normalized)
      ) versions;
    in
    if matches == [ ] then
      throw "js-toolchain-overlay: no release matches ${request}"
    else
      lib.last (lib.sort (a: b: compare a b < 0) matches);
in
{
  inherit resolve;
}
