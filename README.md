# js-toolchain-overlay

Nix overlay for official Node.js, Bun, Deno, pnpm, and Yarn distributions

Supported systems: `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.

## Flake packages

Run a tool directly:

```bash
nix shell github:so1ve/js-toolchain-overlay#node
nix shell github:so1ve/js-toolchain-overlay#bun
nix shell github:so1ve/js-toolchain-overlay#deno
nix shell github:so1ve/js-toolchain-overlay#pnpm
nix shell github:so1ve/js-toolchain-overlay#yarn
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
    # Use js-toolchain-overlay.packages.${system}.node, bun, deno, pnpm, or yarn
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
            pkgs.pnpm-bin.latest
            pkgs.yarn-bin.latest
          ];
        })
      ];
    };
  };
}
```

The overlay adds `pkgs.node-bin`, `pkgs.bun-bin`, `pkgs.deno-bin`,
`pkgs.pnpm-bin`, and `pkgs.yarn-bin` and does not override the corresponding
nixpkgs packages.

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
| `pnpm`, `pnpm_latest` | `pnpm-bin.latest`             | Latest packaged stable pnpm |
| `pnpm_12`             | `pnpm-bin.majors."12"`        | Latest pnpm 12.x release    |
| `pnpm_12_0_0`         | `pnpm-bin.versions."12.0.0"`  | pnpm 12.0.0                 |
| `yarn`, `yarn_latest` | `yarn-bin.latest`             | Latest packaged stable Yarn |
| `yarn_4`              | `yarn-bin.majors."4"`         | Latest Yarn 4.x release     |
| `yarn_4_18_0`         | `yarn-bin.versions."4.18.0"`  | Yarn 4.18.0                 |

## Version selection

Each tool namespace supports exact versions, partial versions, and semver
ranges:

```nix
pkgs.node-bin.fromVersion "^24"
pkgs.bun-bin.fromVersion "1.3"
pkgs.deno-bin.fromVersion "~2.9"
pkgs.pnpm-bin.fromVersion "^12"
pkgs.yarn-bin.fromVersion "4"
```

It can also select a tool from a plain version file, `package.json`, or a
project directory:

```nix
pkgs.node-bin.fromVersionFile ./.node-version
pkgs.bun-bin.fromPackageJSON ./package.json
pkgs.deno-bin.fromProject ./.
pkgs.pnpm-bin.fromPackageJSON ./package.json
pkgs.yarn-bin.fromProject ./.
```

`fromProject` checks these declarations in order:

| Runtime | Project declarations                                                        |
| ------- | --------------------------------------------------------------------------- |
| Node.js | `.node-version`, `.nvmrc`, `.tool-versions` (`nodejs`), then `package.json` |
| Bun     | `.bun-version`, `.tool-versions` (`bun`), then `package.json`               |
| Deno    | `.dvmrc`, `.tool-versions` (`deno`), then `package.json`                    |
| pnpm    | `.tool-versions` (`pnpm`), then `package.json`                              |
| Yarn    | `.tool-versions` (`yarn`), then `package.json`                              |

For `package.json`, the runtime-specific precedence is:

- Node.js: `volta.node`, matching `devEngines.runtime`, then `engines.node`.
- Bun: a Bun `packageManager`, matching `devEngines.runtime`, then
  `engines.bun`.
- Deno: matching `devEngines.runtime`, then `engines.deno`.
- pnpm: `devEngines.packageManager`, then `packageManager`, then `engines.pnpm`.
- Yarn: `packageManager`, then `devEngines.packageManager`, then `engines.yarn`.
  Both selectors accept a matching entry in a `devEngines.packageManager` array.
  An explicit declaration for another package manager returns `null`.

File- and project-based selectors return `null` when no declaration is found.
`fromVersion` is strict and fails for malformed or unsupported requests.

## Package managers

pnpm is packaged from the official native archives starting with version 12.
The package includes `pnpm`, `pnpx`, and the bundled helper files. pnpm itself
can start without Node.js; add Node.js separately for project scripts and
features that use it.

Yarn is packaged from the official `@yarnpkg/cli-dist` bundles for stable
versions 2 through 5 available in that registry package. Yarn Classic and Yarn 6
previews are not cataloged. The package provides `yarn` and `yarnpkg`, uses
nixpkgs' `nodejs` by default, and supports `.override { nodejs = node; }` to
select its runtime.

For a project declaring Node.js and pnpm:

```nix
let
  node = pkgs.node-bin.fromProject ./.;
  pnpm = pkgs.pnpm-bin.fromProject ./.;
in
pkgs.mkShellNoCC {
  packages = [ node pnpm ];
}
```

For a Yarn project:

```nix
let
  node = pkgs.node-bin.fromProject ./.;
  yarn = (pkgs.yarn-bin.fromProject ./.).override { nodejs = node; };
in
pkgs.mkShellNoCC {
  packages = [ node yarn ];
}
```

These examples require the corresponding version declarations. Use an explicit
selection such as `pkgs.node-bin.lts` when a project does not declare Node.js.

Nix selects the installed tool versions. The pnpm wrappers set `pmOnFail=ignore`
and `runtimeOnFail=ignore`, leaving version selection to Nix without resolving
or downloading another package manager or runtime. Yarn sets `YARN_IGNORE_PATH=1`
to use the selected CLI even when `.yarnrc.yml` contains a `yarnPath`.

Projects that need Corepack's dynamic version selection can keep using
`node.corepack` as described below. Choose either the direct package or a
Corepack shim for each command in an environment to avoid PATH conflicts.

## Node.js components

Node.js packages expose the runtime, npm, and corepack separately. The default
package contains only the `node` executable, headers, documentation, and
runtime files. In particular, `nix shell .#node` does not add npm or corepack.

- `node.npm` contains npm and npx when the official release bundles npm.
- `node.npmVersion` records the bundled npm version, or `null` when absent.
- `node.corepack` contains only the corepack executable. When the official
  archive bundles corepack (Node.js 14 starting with 14.19, Node.js 16 starting
  with 16.9, and Node.js 17 through 24), it is exposed as a separate output.
  Node.js 25 and newer use the standalone nixpkgs corepack package with the
  selected Node.js runtime.

Add the components a project needs explicitly:

```nix
let
  node = pkgs.node-bin.fromProject ./.;
in
{
  packages = [
    node
    node.npm
    node.corepack
  ];
}
```

Yarn and pnpm are not included in `node.corepack`. An environment integration
such as devenv can generate their corepack shims, or they can be installed as
separate Nix packages.

## Version data and updates

Run this to update the version data:

```bash
nix run .#update
```

The scheduled workflow performs this update every 12 hours.

## License

[MIT](LICENSE). Made with ❤️ by [Ray](https://github.com/so1ve)
