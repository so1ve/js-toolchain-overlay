#!/usr/bin/env -S nix shell nixpkgs#nodejs -c node

import { createHash } from "node:crypto";
import {
  buildCatalog,
  digestToSRI,
  getGitHubRelease,
  getJSON,
  readCatalog,
  writeCatalog,
} from "./common.mjs";

const pnpmPlatforms = {
  "aarch64-darwin": "pnpm-darwin-arm64.tar.gz",
  "aarch64-linux": "pnpm-linux-arm64.tar.gz",
  "x86_64-linux": "pnpm-linux-x64.tar.gz",
};
const systems = Object.keys(pnpmPlatforms);

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
      /^\d+\.\d+\.\d+$/.test(version) &&
      Number(version.split(".")[0]) >= 12 &&
      systems.some((system) => !records[version]?.artifacts[system]?.hash),
  );

  for (const [index, version] of pending.entries()) {
    const release = await getGitHubRelease("pnpm/pnpm", `v${version}`);
    if (release.draft || release.prerelease) continue;
    const artifacts = records[version]?.artifacts ?? {};

    for (const [system, file] of Object.entries(pnpmPlatforms)) {
      if (artifacts[system]?.hash) continue;
      const asset = release.assets.find((candidate) => candidate.name === file);
      if (!asset) continue;

      const hash =
        digestToSRI(asset.digest) ??
        (await downloadHash(asset.browser_download_url));
      artifacts[system] = { file, hash };
    }

    records[version] = {
      artifacts,
      date: release.published_at.slice(0, 10),
    };
    console.log(`pnpm ${version}: processed ${index + 1}/${pending.length}`);
  }

  await writeCatalog("pnpm", buildCatalog(records, { latest }));
}

async function backfillYarn() {
  const metadata = await getJSON(
    "https://registry.npmjs.org/@yarnpkg%2fcli-dist",
  );
  const { latest, releases: records } = await readCatalog("yarn");
  const pending = Object.keys(metadata.versions).filter(
    (version) =>
      /^[2345]\.\d+\.\d+$/.test(version) &&
      systems.some((system) => !records[version]?.artifacts[system]?.hash),
  );

  for (const [index, version] of pending.entries()) {
    const { tarball: url, integrity } = metadata.versions[version].dist;
    const hash = integrity?.startsWith("sha512-")
      ? integrity
      : await downloadHash(url);
    const artifacts = records[version]?.artifacts ?? {};

    for (const system of systems) {
      if (!artifacts[system]?.hash) artifacts[system] = { url, hash };
    }

    records[version] = {
      artifacts,
      date: metadata.time[version].slice(0, 10),
    };
    console.log(`yarn ${version}: processed ${index + 1}/${pending.length}`);
  }

  await writeCatalog("yarn", buildCatalog(records, { latest }));
}

await backfillPnpm();
await backfillYarn();
