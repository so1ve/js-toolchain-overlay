import {
  buildCatalog,
  digestToSRI,
  getGitHubRelease,
  getJSON,
  readCatalog,
  writeCatalog,
} from "./common.mjs";

const NAME = "pnpm";
const platforms = {
  "aarch64-darwin": "pnpm-darwin-arm64.tar.gz",
  "aarch64-linux": "pnpm-linux-arm64.tar.gz",
  "x86_64-linux": "pnpm-linux-x64.tar.gz",
};

export async function updatePnpm() {
  const metadata = await getJSON("https://registry.npmjs.org/pnpm");
  const versions = Object.keys(metadata.versions).filter(
    (version) =>
      /^\d+\.\d+\.\d+$/.test(version) && Number(version.split(".")[0]) >= 12,
  );
  const { releases: records } = await readCatalog(NAME);

  for (const version of versions) {
    const artifacts = records[version]?.artifacts ?? {};
    if (Object.keys(platforms).every((system) => artifacts[system])) continue;
    const release = await getGitHubRelease("pnpm/pnpm", `v${version}`);
    if (release.draft || release.prerelease) continue;

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
  }

  // Use the highest packaged stable release, independently of npm's latest tag.
  await writeCatalog(NAME, buildCatalog(records, { keepEmpty: true }));
}
