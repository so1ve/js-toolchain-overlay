#!/usr/bin/env -S nix shell nixpkgs#nodejs -c node

import { readFile, writeFile } from "node:fs/promises";

const INDEX_URL = "https://nodejs.org/dist/index.json";
const SHASUMS_URL = "https://nodejs.org/dist/v{version}/SHASUMS256.txt";
const INDEX_FILE = "versions.json";
const CONCURRENCY = 20;

const platforms = {
  "aarch64-darwin": ["osx-arm64-tar", "darwin-arm64"],
  "aarch64-linux": ["linux-arm64", "linux-arm64"],
  "x86_64-linux": ["linux-x64", "linux-x64"],
};

const versionOf = (release) => release.version.slice(1);

async function get(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${response.status} ${url}`);
  return response.text();
}

async function fetchRelease(release) {
  const version = versionOf(release);
  const files = new Set(release.files);
  const manifest = Object.values(platforms).some(([name]) => files.has(name))
    ? await get(SHASUMS_URL.replace("{version}", version))
    : "";
  const checksums = Object.fromEntries(
    manifest
      .split("\n")
      .map((line) => /^([0-9a-f]{64})  (.+)$/.exec(line))
      .filter(Boolean)
      .map((match) => [match[2].replace(/^\.\//, ""), match[1]]),
  );
  const artifacts = {};

  for (const [system, [indexName, archiveName]] of Object.entries(platforms)) {
    if (!files.has(indexName)) continue;

    const base = `node-v${version}-${archiveName}.tar`;
    const file = checksums[`${base}.xz`] ? `${base}.xz` : `${base}.gz`;
    artifacts[system] = {
      file,
      hash: `sha256-${Buffer.from(checksums[file], "hex").toString("base64")}`,
    };
  }

  return [
    version,
    {
      artifacts,
      date: release.date,
      lts: release.lts,
      npm: release.npm ?? null,
    },
  ];
}

function buildCatalog(index, records) {
  const versions = index.map(versionOf);
  const releases = Object.fromEntries(
    versions
      .filter((version) => version in records)
      .map((version) => [version, records[version]]),
  );
  const packaged = new Set(
    Object.entries(releases)
      .filter(([, release]) => Object.keys(release.artifacts).length)
      .map(([version]) => version),
  );
  const latest = versions.find((version) => packaged.has(version));
  const lts = versionOf(
    index.find((release) => release.lts && packaged.has(versionOf(release))),
  );
  const majors = {};

  for (const version of versions) {
    const major = version.split(".")[0];
    if (packaged.has(version) && !(major in majors)) majors[major] = version;
  }

  return { latest, lts, majors, releases, schema: 2 };
}

const index = JSON.parse(await get(INDEX_URL));
const records = JSON.parse(await readFile(INDEX_FILE, "utf8")).releases;
const missing = index.filter((release) => !(versionOf(release) in records));

for (let offset = 0; offset < missing.length; offset += CONCURRENCY) {
  Object.assign(
    records,
    Object.fromEntries(
      await Promise.all(
        missing.slice(offset, offset + CONCURRENCY).map(fetchRelease),
      ),
    ),
  );
  console.log(
    `fetched ${Math.min(offset + CONCURRENCY, missing.length)}/${missing.length}`,
  );
}

await writeFile(
  INDEX_FILE,
  `${JSON.stringify(buildCatalog(index, records), null, 2)}\n`,
);
console.log(`updated ${INDEX_FILE}`);
