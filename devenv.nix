{ pkgs, ... }:

{
  packages = with pkgs; [
    deadnix
    nixd
    nixfmt
    nodejs_26
    prettier
    statix
    vtsls
  ];
}
