import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const GITHUB_PAGE_SIZE = 100;
const VERSIONS_DIR = resolve("versions");

const githubHeaders = {
  Accept: "application/vnd.github+json",
  "User-Agent": "js-toolchain-overlay-update",
  "X-GitHub-Api-Version": "2022-11-28",
};
if (process.env.GITHUB_TOKEN) {
  githubHeaders.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
}

async function fetchChecked(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) throw new Error(`${response.status} ${url}`);
  return response;
}

export async function getText(url, options) {
  return (await fetchChecked(url, options)).text();
}

export async function getJSON(url, options) {
  return (await fetchChecked(url, options)).json();
}

export function digestToSRI(digest) {
  if (!digest) return null;
  return `sha256-${Buffer.from(digest.slice(7), "hex").toString("base64")}`;
}

export async function readCatalog(name) {
  return JSON.parse(
    await readFile(resolve(VERSIONS_DIR, `${name}.json`), "utf8"),
  );
}

export async function writeCatalog(name, catalog) {
  await writeFile(
    resolve(VERSIONS_DIR, `${name}.json`),
    `${JSON.stringify(catalog, null, 2)}\n`,
  );
  console.log(`updated versions/${name}.json`);
}

export function buildCatalog(records, { latest, lts, keepEmpty = false }) {
  const versions = Object.keys(records).sort((left, right) =>
    right.localeCompare(left, undefined, {
      numeric: true,
      sensitivity: "base",
    }),
  );
  const releases = Object.fromEntries(
    versions
      .filter(
        (version) =>
          keepEmpty || Object.keys(records[version].artifacts).length > 0,
      )
      .map((version) => [version, records[version]]),
  );
  const packaged = Object.keys(releases).filter(
    (version) => Object.keys(releases[version].artifacts).length > 0,
  );
  const resolvedLatest = packaged.includes(latest) ? latest : packaged[0];
  const majors = {};

  for (const version of packaged) {
    const major = version.split(".")[0];
    if (!(major in majors)) majors[major] = version;
  }

  return {
    latest: resolvedLatest,
    ...(lts != null && packaged.includes(lts) ? { lts } : {}),
    majors,
    releases,
  };
}

export async function listGitHubReleases(repository) {
  const releases = [];
  for (let page = 1; ; page += 1) {
    const batch = await getJSON(
      `https://api.github.com/repos/${repository}/releases?per_page=${GITHUB_PAGE_SIZE}&page=${page}`,
      { headers: githubHeaders },
    );
    releases.push(...batch);
    if (batch.length < GITHUB_PAGE_SIZE) return releases;
  }
}
