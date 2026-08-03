#!/usr/bin/env -S nix shell nixpkgs#nodejs -c node

import { createHash } from "node:crypto";
import { parseArgs } from "node:util";
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
    platforms: {
      "aarch64-darwin": "bun-darwin-aarch64.zip",
      "aarch64-linux": "bun-linux-aarch64.zip",
      "x86_64-linux": "bun-linux-x64.zip",
    },
  },
  deno: {
    repository: "denoland/deno",
    tag: /^v\d+\.\d+\.\d+$/,
    versionOf: (release) => release.tag_name.slice(1),
    platforms: {
      "aarch64-darwin": "deno-aarch64-apple-darwin.zip",
      "aarch64-linux": "deno-aarch64-unknown-linux-gnu.zip",
      "x86_64-linux": "deno-x86_64-unknown-linux-gnu.zip",
    },
  },
};

async function downloadHash(url) {
  const response = await fetch(url, { headers: githubHeaders });
  if (!response.ok) throw new Error(`${response.status} ${url}`);

  const hash = createHash("sha256");
  for await (const chunk of response.body) hash.update(chunk);
  return `sha256-${hash.digest("base64")}`;
}

async function backfillRuntime(name, limit) {
  const { platforms, repository, tag, versionOf } = runtimes[name];
  const releases = (await listGitHubReleases(repository)).filter(
    (release) =>
      !release.draft && !release.prerelease && tag.test(release.tag_name),
  );
  const { latest, lts, releases: records, schema } = await readCatalog(name);
  const pending = releases.filter((release) => {
    const artifacts = records[versionOf(release)]?.artifacts ?? {};
    return Object.entries(platforms).some(([system, file]) => {
      if (artifacts[system]) return false;
      return release.assets.some((asset) => asset.name === file);
    });
  });
  const selected = limit === 0 ? pending : pending.slice(0, limit);

  for (const [index, release] of selected.entries()) {
    const version = versionOf(release);
    const artifacts = records[version]?.artifacts ?? {};

    for (const [system, file] of Object.entries(platforms)) {
      if (artifacts[system]) continue;
      const asset = release.assets.find((candidate) => candidate.name === file);
      if (!asset) continue;

      let hash = digestToSRI(asset.digest);
      if (!hash) {
        console.log(`${release.tag_name}: downloading ${file}`);
        hash = await downloadHash(asset.browser_download_url);
      }
      artifacts[system] = { file, hash };
    }

    records[version] = {
      artifacts,
      date: release.published_at.slice(0, 10),
    };
    console.log(`${name}: processed ${index + 1}/${selected.length}`);
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

const { runtime, limit: limitValue } = parseArgs({
  options: {
    runtime: { type: "string" },
    limit: { type: "string" },
  },
}).values;

if (!["all", ...Object.keys(runtimes)].includes(runtime)) {
  throw new Error("--runtime must be one of: all, bun, deno");
}

const limit = Number(limitValue);
if (
  limitValue === undefined ||
  limitValue === "" ||
  !Number.isInteger(limit) ||
  limit < 0
) {
  throw new Error("--limit must be provided as a non-negative integer");
}

if (runtime === "all" || runtime === "bun") await backfillRuntime("bun", limit);
if (runtime === "all" || runtime === "deno")
  await backfillRuntime("deno", limit);
