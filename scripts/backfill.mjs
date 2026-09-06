#!/usr/bin/env -S nix shell nixpkgs#nodejs -c node

import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import {
  buildCatalog,
  digestToSRI,
  getGitHubRelease,
  getJSON,
  listGitHubReleases,
  readCatalog,
  writeCatalog,
} from "./common.mjs";

const pnpmPlatforms = {
  "aarch64-darwin": "pnpm-darwin-arm64.tar.gz",
  "aarch64-linux": "pnpm-linux-arm64.tar.gz",
  "x86_64-linux": "pnpm-linux-x64.tar.gz",
};
const systems = Object.keys(pnpmPlatforms);
const stable = /^\d+\.\d+\.\d+$/;
const run = promisify(execFile);

async function npmArtifact(release) {
  const { tarball: url, integrity } = release.dist;
  const hash = integrity?.startsWith("sha512-")
    ? integrity
    : await downloadHash(url);
  return { url, hash };
}

function externalDependencies(release) {
  const bundled = release.bundleDependencies ?? release.bundledDependencies;
  if (bundled === true) return {};

  const dependencies = { ...release.dependencies };
  if (Array.isArray(bundled)) {
    for (const name of bundled) delete dependencies[name];
  }
  return dependencies;
}

async function lockDependencies(name, version, release) {
  const dependencies = externalDependencies(release);
  if (!Object.keys(dependencies).length) return {};

  const directory = await mkdtemp(join(tmpdir(), "toolchain-npm-lock-"));
  try {
    await writeFile(
      join(directory, "package.json"),
      JSON.stringify({ name, version, dependencies }),
    );
    console.log(`${name} ${version}: locking runtime dependencies`);
    await run(
      "npm",
      [
        "install",
        "--package-lock-only",
        "--ignore-scripts",
        "--legacy-peer-deps",
        "--no-audit",
        "--no-fund",
        "--registry=https://registry.npmjs.org",
      ],
      { cwd: directory, maxBuffer: 8 * 1024 * 1024 },
    );
    const npmLock = `npm/${name}-${version}.json`;
    await mkdir("versions/npm", { recursive: true });
    await writeFile(
      join("versions", npmLock),
      await readFile(join(directory, "package-lock.json")),
    );
    return { npmLock };
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function fillSystems(artifacts, artifact) {
  for (const system of systems) {
    if (!artifacts[system]?.hash) artifacts[system] = artifact;
  }
}

async function downloadHash(url) {
  console.log(`downloading ${url}`);
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${response.status} ${url}`);

  const hash = createHash("sha256");
  for await (const chunk of response.body) hash.update(chunk);
  return `sha256-${hash.digest("base64")}`;
}

async function backfillPnpm() {
  const metadata = await getJSON("https://registry.npmjs.org/pnpm");
  const { latest, releases: records } = await readCatalog("pnpm");
  const pending = Object.keys(metadata.versions).filter(
    (version) =>
      stable.test(version) &&
      systems.some((system) => !records[version]?.artifacts[system]?.hash),
  );

  for (const [index, version] of pending.entries()) {
    const artifacts = records[version]?.artifacts ?? {};
    const release = metadata.versions[version];
    let dependencies = {};

    if (Number(version.split(".")[0]) >= 12) {
      const github = await getGitHubRelease("pnpm/pnpm", `v${version}`);
      if (github.draft || github.prerelease) continue;
      for (const [system, file] of Object.entries(pnpmPlatforms)) {
        if (artifacts[system]?.hash) continue;
        const asset = github.assets.find(
          (candidate) => candidate.name === file,
        );
        if (!asset) continue;
        const hash =
          digestToSRI(asset.digest) ??
          (await downloadHash(asset.browser_download_url));
        artifacts[system] = { file, hash };
      }
    } else if (release.bin) {
      dependencies = await lockDependencies("pnpm", version, release);
      fillSystems(artifacts, await npmArtifact(release));
    } else {
      console.log(`pnpm ${version}: no CLI was published`);
    }

    records[version] = {
      artifacts,
      date: metadata.time[version].slice(0, 10),
      ...dependencies,
    };
    console.log(`pnpm ${version}: processed ${index + 1}/${pending.length}`);
  }

  await writeCatalog(
    "pnpm",
    buildCatalog(records, { latest, keepEmpty: true }),
  );
}

async function backfillYarn() {
  const { latest, releases: records } = await readCatalog("yarn");
  const classic = await getJSON("https://registry.npmjs.org/yarn");
  const bundles = await getJSON(
    "https://registry.npmjs.org/@yarnpkg%2fcli-dist",
  );
  const cli = await getJSON("https://registry.npmjs.org/@yarnpkg%2fcli");
  const { tags } = await getJSON("https://repo.yarnpkg.com/tags");
  const github = new Map(
    (await listGitHubReleases("yarnpkg/yarn"))
      .filter((release) => !release.draft)
      .map((release) => [release.tag_name.replace(/^v/, ""), release]),
  );
  const versions = new Set([
    ...github.keys(),
    // Older owners of the npm name "yarn" published unrelated libraries.
    ...Object.keys(classic.versions).filter(
      (version) => classic.versions[version].bin?.yarn,
    ),
    ...Object.keys(bundles.versions),
    ...tags,
  ]);
  const pending = [...versions].filter(
    (version) =>
      stable.test(version) &&
      systems.some((system) => !records[version]?.artifacts[system]?.hash),
  );

  for (const [index, version] of pending.entries()) {
    const artifacts = records[version]?.artifacts ?? {};
    const npm = bundles.versions[version] ?? classic.versions[version];
    const release = github.get(version);
    let artifact;
    let dependencies = {};
    if (npm && !Object.keys(externalDependencies(npm)).length) {
      artifact = await npmArtifact(npm);
    } else if (Number(version.split(".")[0]) >= 2) {
      const url = `https://repo.yarnpkg.com/${version}/packages/yarnpkg-cli/bin/yarn.js`;
      artifact = { url, hash: await downloadHash(url) };
    } else {
      const asset =
        release?.assets.find((asset) => asset.name === `yarn-${version}.js`) ??
        release?.assets.find((asset) => /\.tar\.gz$/.test(asset.name));
      if (asset) {
        artifact = {
          url: asset.browser_download_url,
          hash:
            digestToSRI(asset.digest) ??
            (await downloadHash(asset.browser_download_url)),
        };
      } else if (npm?.bin?.yarn) {
        dependencies = await lockDependencies("yarn", version, npm);
        artifact = await npmArtifact(npm);
      } else {
        console.log(`yarn ${version}: no CLI artifact was published`);
      }
    }
    if (artifact) fillSystems(artifacts, artifact);
    const date =
      bundles.time[version] ??
      cli.time[version] ??
      classic.time[version] ??
      release.published_at;
    records[version] = {
      artifacts,
      date: date.slice(0, 10),
      ...dependencies,
    };
    console.log(`yarn ${version}: processed ${index + 1}/${pending.length}`);
  }

  await writeCatalog(
    "yarn",
    buildCatalog(records, { latest, keepEmpty: true }),
  );
}

await backfillPnpm();
await backfillYarn();
