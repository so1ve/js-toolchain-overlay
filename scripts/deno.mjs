import {
  buildCatalog,
  digestToSRI,
  getText,
  listGitHubReleases,
  readCatalog,
  writeCatalog,
} from "./common.mjs";

const NAME = "deno";
const REPOSITORY = "denoland/deno";
const TAG = /^v\d+\.\d+\.\d+$/;
const LTS_URL = "https://dl.deno.land/release-lts-latest.txt";
const platforms = {
  "aarch64-darwin": "deno-aarch64-apple-darwin.zip",
  "aarch64-linux": "deno-aarch64-unknown-linux-gnu.zip",
  "x86_64-linux": "deno-x86_64-unknown-linux-gnu.zip",
};

const versionOf = (release) => release.tag_name.slice(1);

export async function updateDeno() {
  const releases = (await listGitHubReleases(REPOSITORY)).filter(
    (release) =>
      !release.draft && !release.prerelease && TAG.test(release.tag_name),
  );
  const { releases: records } = await readCatalog(NAME);
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

  const lts = (await getText(LTS_URL)).trim().replace(/^v/, "");
  await writeCatalog(
    NAME,
    buildCatalog(records, {
      latest: versionOf(releases[0]),
      lts,
    }),
  );
}
