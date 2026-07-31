# node-overlay

Nix overlay for upstream Node.js binaries.

Supported systems: `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`

## Flake packages

Run a package directly:

```bash
nix shell github:so1ve/node-overlay#lts
```

Use a package from another flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    node-overlay = {
      url = "github:so1ve/node-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, node-overlay, ... }: {
    ...
  };
}
```

## Overlay

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    node-overlay = {
      url = "github:so1ve/node-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, node-overlay, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ node-overlay.overlays.default ]; }
        ({ pkgs, ... }: {
          environment.systemPackages = [ pkgs.nodejs-bin.lts ];
        })
      ];
    };
  };
}
```

The overlay adds `pkgs.nodejs-bin` instead of overriding `pkgs.nodejs`

## Package names

| Flake package | Overlay attribute | Selects |
| --- | --- | --- |
| `default`, `latest` | `nodejs-bin.latest` | Latest release |
| `lts` | `nodejs-bin.lts` | Latest LTS release |
| `nodejs_24` | `nodejs-bin.majors."24"` | Latest 24.x release |
| `nodejs_24_18_1` | `nodejs-bin.versions."24.18.1"` | Node.js 24.18.1 |

Exact versions are available only when Node.js publishes an archive for the target system.

## Project versions

The overlay can select a release from a version, a version file, or `package.json`:

```nix
pkgs.nodejs-bin.fromNodeVersion "^24"
pkgs.nodejs-bin.fromNodeVersionFile ./.node-version
pkgs.nodejs-bin.fromPackageJSON ./package.json
pkgs.nodejs-bin.fromProject ./.
```

Without the overlay, use the flake library:

```nix
node-overlay.lib.fromProject pkgs ./.
```

`fromProject` checks `.node-version`, `.nvmrc`, then `package.json`.
For `package.json`, it checks `volta.node`, `devEngines.runtime.version`, then `engines.node`. Version values may be exact versions, partial versions, or semver ranges.

`nodejs.corepack` is the Corepack package paired with the selected Node.js version. Devenv uses it when `corepack.enable` is enabled:

```nix
let
  nodejs = pkgs.nodejs-bin.fromProject ./.;
in
{
  languages.javascript = {
    enable = true;
    package = nodejs;
    corepack.enable = true;
  };
}
```

Corepack reads `packageManager` and `devEngines.packageManager` from `package.json`.

## Update

```bash
nix run .#update
```

An automated workflow refreshes the release index every 12 hours and verifies the latest and LTS builds before committing updates.

## License

[MIT](LICENSE)
