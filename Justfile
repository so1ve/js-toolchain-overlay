default:
    @just --list

build package="default":
    nix build .#{{ package }} --print-build-logs

fmt:
    nix fmt

update:
    nix run .#update
