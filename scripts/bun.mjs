import {
  buildCatalog,
  digestToSRI,
  listGitHubReleases,
  readCatalog,
  writeCatalog,
} from "./common.mjs";

const NAME = "bun";
const REPOSITORY = "oven-sh/bun";
const TAG = /^bun-v\d+\.\d+\.\d+$/;
const platforms = {
  "aarch64-darwin": "bun-darwin-aarch64.zip",
  "aarch64-linux": "bun-linux-aarch64.zip",
  "x86_64-linux": "bun-linux-x64.zip",
};

const versionOf = (release) => release.tag_name.slice("bun-v".length);

export async function updateBun() {
  const releases = (await listGitHubReleases(REPOSITORY)).filter(
    (release) =>
      !release.draft && !release.prerelease && TAG.test(release.tag_name),
  );
  const { releases: records, schema } = await readCatalog(NAME);
  const pending = releases.filter((release) => {
    const artifacts = records[versionOf(release)]?.artifacts ?? {};
    return Object.entries(platforms).some(([system, file]) => {
      if (artifacts[system]) return false;
      const asset = release.assets.find((candidate) => candidate.name === file);
      return asset && digestToSRI(asset.digest);
    });
  });

  for (const [index, release] of pending.entries()) {
    const version = versionOf(release);
    const artifacts = records[version]?.artifacts ?? {};

    for (const [system, file] of Object.entries(platforms)) {
      if (artifacts[system]) continue;
      const asset = release.assets.find((candidate) => candidate.name === file);
      if (!asset) continue;

      const hash = digestToSRI(asset.digest);
      if (hash) artifacts[system] = { file, hash };
    }

    records[version] = {
      artifacts,
      date: release.published_at.slice(0, 10),
    };
    console.log(`${NAME}: processed ${index + 1}/${pending.length}`);
  }

  await writeCatalog(
    NAME,
    buildCatalog(records, {
      latest: versionOf(releases[0]),
      schema,
    }),
  );
}
