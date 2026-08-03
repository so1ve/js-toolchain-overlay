default:
    @just --list

build package:
    nix build .#{{ package }} --print-build-logs

fmt:
    nix fmt

update:
    nix run .#update
