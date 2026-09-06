import { buildCatalog, getJSON, readCatalog, writeCatalog } from "./common.mjs";

const NAME = "yarn";
const systems = ["aarch64-darwin", "aarch64-linux", "x86_64-linux"];

export async function updateYarn() {
  const metadata = await getJSON(
    "https://registry.npmjs.org/@yarnpkg%2fcli-dist",
  );
  const { releases: records } = await readCatalog(NAME);

  for (const [version, release] of Object.entries(metadata.versions)) {
    if (!/^[2345]\.\d+\.\d+$/.test(version) || records[version]) continue;

    const { tarball: url, integrity: hash } = release.dist;
    if (!hash?.startsWith("sha512-")) {
      throw new Error(`yarn ${version}: missing SHA-512 integrity for ${url}`);
    }
    records[version] = {
      artifacts: Object.fromEntries(
        systems.map((system) => [system, { url, hash }]),
      ),
      date: metadata.time[version].slice(0, 10),
    };
  }

  await writeCatalog(NAME, buildCatalog(records, {}));
}
