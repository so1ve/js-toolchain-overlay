{ pkgs, ... }:

{
  packages = with pkgs; [
    actionlint
    deadnix
    nixd
    nixfmt
    nodejs_26
    prettier
    statix
    vtsls
  ];
}
