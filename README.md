# js-toolchain-overlay

Nix overlay for official Node.js, Bun, and Deno binaries

Supported systems: `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.

## Flake packages

Run a runtime directly:

```bash
nix shell github:so1ve/js-toolchain-overlay#node
nix shell github:so1ve/js-toolchain-overlay#bun
nix shell github:so1ve/js-toolchain-overlay#deno
```

Use the packages from another flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    js-toolchain-overlay = {
      url = "github:so1ve/js-toolchain-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { js-toolchain-overlay, ... }: {
    # Use js-toolchain-overlay.packages.${system}.node, bun, or deno
  };
}
```

## Overlay

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    js-toolchain-overlay = {
      url = "github:so1ve/js-toolchain-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, js-toolchain-overlay, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ js-toolchain-overlay.overlays.default ]; }
        ({ pkgs, ... }: {
          environment.systemPackages = [
            pkgs.node-bin.lts
            pkgs.bun-bin.latest
            pkgs.deno-bin.latest
          ];
        })
      ];
    };
  };
}
```

The overlay adds `pkgs.node-bin`, `pkgs.bun-bin`, and `pkgs.deno-bin` and does
not override the corresponding nixpkgs packages.

## Package names

| Flake package         | Overlay attribute             | Selects                     |
| --------------------- | ----------------------------- | --------------------------- |
| `node`, `node_latest` | `node-bin.latest`             | Latest Node.js release      |
| `node_lts`            | `node-bin.lts`                | Latest Node.js LTS release  |
| `node_24`             | `node-bin.majors."24"`        | Latest Node.js 24.x release |
| `node_24_18_1`        | `node-bin.versions."24.18.1"` | Node.js 24.18.1             |
| `bun`, `bun_latest`   | `bun-bin.latest`              | Latest Bun release          |
| `bun_1`               | `bun-bin.majors."1"`          | Latest Bun 1.x release      |
| `bun_1_3_14`          | `bun-bin.versions."1.3.14"`   | Bun 1.3.14                  |
| `deno`, `deno_latest` | `deno-bin.latest`             | Latest Deno release         |
| `deno_lts`            | `deno-bin.lts`                | Latest Deno LTS release     |
| `deno_2`              | `deno-bin.majors."2"`         | Latest Deno 2.x release     |
| `deno_2_9_4`          | `deno-bin.versions."2.9.4"`   | Deno 2.9.4                  |

## Version selection

Each runtime namespace supports exact versions, partial versions, and semver
ranges:

```nix
pkgs.node-bin.fromVersion "^24"
pkgs.bun-bin.fromVersion "1.3"
pkgs.deno-bin.fromVersion "~2.9"
```

It can also select a runtime from a plain version file, `package.json`, or a
project directory:

```nix
pkgs.node-bin.fromVersionFile ./.node-version
pkgs.bun-bin.fromPackageJSON ./package.json
pkgs.deno-bin.fromProject ./.
```

`fromProject` checks these declarations in order:

| Runtime | Project declarations                                                        |
| ------- | --------------------------------------------------------------------------- |
| Node.js | `.node-version`, `.nvmrc`, `.tool-versions` (`nodejs`), then `package.json` |
| Bun     | `.bun-version`, `.tool-versions` (`bun`), then `package.json`               |
| Deno    | `.dvmrc`, `.tool-versions` (`deno`), then `package.json`                    |

For `package.json`, the runtime-specific precedence is:

- Node.js: `volta.node`, matching `devEngines.runtime`, then `engines.node`.
- Bun: a Bun `packageManager`, matching `devEngines.runtime`, then
  `engines.bun`.
- Deno: matching `devEngines.runtime`, then `engines.deno`.

File- and project-based selectors return `null` when no declaration is found.
`fromVersion` is strict and fails for malformed or unsupported requests.

Its matching Corepack package is exposed as `node.corepack`:

```nix
let
  node = pkgs.node-bin.fromProject ./.;
in
{
  packages = [ node node.corepack ];
}
```

## Version data and updates

Run this to update the version data:

```bash
nix run .#update
```

The scheduled workflow performs this update every 12 hours.

## License

[MIT](LICENSE). Made with ❤️ by [Ray](https://github.com/so1ve)
