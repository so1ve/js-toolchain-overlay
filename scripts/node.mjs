import {
  buildCatalog,
  getJSON,
  getText,
  readCatalog,
  writeCatalog,
} from "./common.mjs";

const CONCURRENCY = 20;
const INDEX_URL = "https://nodejs.org/dist/index.json";
const SHASUMS_URL = "https://nodejs.org/dist/v{version}/SHASUMS256.txt";

const platforms = {
  "aarch64-darwin": ["osx-arm64-tar", "darwin-arm64"],
  "aarch64-linux": ["linux-arm64", "linux-arm64"],
  "x86_64-linux": ["linux-x64", "linux-x64"],
};

const versionOf = (release) => release.version.slice(1);

async function fetchRelease(release) {
  const version = versionOf(release);
  const files = new Set(release.files);
  const manifest = Object.values(platforms).some(([name]) => files.has(name))
    ? await getText(SHASUMS_URL.replace("{version}", version))
    : "";
  const checksums = Object.fromEntries(
    [...manifest.matchAll(/^([0-9a-f]{64})  (.+)$/gm)].map((match) => [
      match[2],
      match[1],
    ]),
  );
  const artifacts = {};

  for (const [system, [indexName, archiveName]] of Object.entries(platforms)) {
    if (!files.has(indexName)) continue;

    const base = `node-v${version}-${archiveName}.tar`;
    const file = checksums[`${base}.xz`] ? `${base}.xz` : `${base}.gz`;
    if (!checksums[file]) continue;
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

export async function updateNode() {
  const index = await getJSON(INDEX_URL);
  const { releases: records } = await readCatalog("node");
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
      `node: fetched ${Math.min(offset + CONCURRENCY, missing.length)}/${missing.length}`,
    );
  }

  const hasArtifacts = (version) =>
    Object.keys(records[version].artifacts).length > 0;
  const latest = index.map(versionOf).find(hasArtifacts);
  const lts = versionOf(
    index.find((release) => release.lts && hasArtifacts(versionOf(release))),
  );
  await writeCatalog(
    "node",
    buildCatalog(records, {
      latest,
      lts,
      keepEmpty: true,
    }),
  );
}
