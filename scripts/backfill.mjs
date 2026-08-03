#!/usr/bin/env -S nix shell nixpkgs#nodejs -c node

import { createHash } from "node:crypto";
import {
  buildCatalog,
  digestToSRI,
  listGitHubReleases,
  readCatalog,
  writeCatalog,
} from "./common.mjs";

const githubHeaders = {
  Accept: "application/vnd.github+json",
  "User-Agent": "js-toolchain-overlay-backfill",
  "X-GitHub-Api-Version": "2022-11-28",
};
if (process.env.GITHUB_TOKEN) {
  githubHeaders.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
}

const runtimes = {
  bun: {
    repository: "oven-sh/bun",
    tag: /^bun-v\d+\.\d+\.\d+$/,
    versionOf: (release) => release.tag_name.slice("bun-v".length),
    artifactsFor: (version) => ({
      "aarch64-darwin": [
        "bun-darwin-aarch64.zip",
        `bun-cli-darwin-aarch64-${version}.tgz`,
      ],
      "aarch64-linux": ["bun-linux-aarch64.zip"],
      "x86_64-linux": ["bun-linux-x64.zip", `bun-cli-linux-x64-${version}.tgz`],
    }),
  },
  deno: {
    repository: "denoland/deno",
    tag: /^v\d+\.\d+\.\d+$/,
    versionOf: (release) => release.tag_name.slice(1),
    artifactsFor: () => ({
      "aarch64-darwin": ["deno-aarch64-apple-darwin.zip"],
      "aarch64-linux": ["deno-aarch64-unknown-linux-gnu.zip"],
      "x86_64-linux": [
        "deno-x86_64-unknown-linux-gnu.zip",
        "deno_linux_x64.gz",
      ],
    }),
  },
};

async function downloadHash(url) {
  const response = await fetch(url, { headers: githubHeaders });
  if (!response.ok) throw new Error(`${response.status} ${url}`);

  const hash = createHash("sha256");
  for await (const chunk of response.body) hash.update(chunk);
  return `sha256-${hash.digest("base64")}`;
}

function assetFor(release, names) {
  return release.assets.find((asset) => names.includes(asset.name));
}

async function backfillRuntime(name) {
  const { artifactsFor, repository, tag, versionOf } = runtimes[name];
  const releases = (await listGitHubReleases(repository)).filter(
    (release) =>
      !release.draft && !release.prerelease && tag.test(release.tag_name),
  );
  const { latest, lts, releases: records, schema } = await readCatalog(name);
  const pending = releases.filter((release) => {
    const version = versionOf(release);
    const artifacts = records[version]?.artifacts ?? {};
    return Object.entries(artifactsFor(version)).some(
      ([system, names]) => !artifacts[system] && assetFor(release, names),
    );
  });
  for (const [index, release] of pending.entries()) {
    const version = versionOf(release);
    const artifacts = records[version]?.artifacts ?? {};

    for (const [system, names] of Object.entries(artifactsFor(version))) {
      if (artifacts[system]) continue;
      const asset = assetFor(release, names);
      if (!asset) continue;

      let hash = digestToSRI(asset.digest);
      if (!hash) {
        console.log(`${release.tag_name}: downloading ${asset.name}`);
        hash = await downloadHash(asset.browser_download_url);
      }
      artifacts[system] = { file: asset.name, hash };
    }

    records[version] = {
      artifacts,
      date: release.published_at.slice(0, 10),
    };
    console.log(`${name}: processed ${index + 1}/${pending.length}`);
  }

  await writeCatalog(
    name,
    buildCatalog(records, {
      latest,
      lts,
      schema,
    }),
  );
}

await backfillRuntime("bun");
await backfillRuntime("deno");
