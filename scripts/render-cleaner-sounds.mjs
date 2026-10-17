// Generate native assets with Cuelume's own offline renderer. See docs/CLEANER.md.
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const revision = "2a1ba4fc1b67e8371c9f37e37a51e61353166335";
if (!process.argv[2]) throw new Error("Pass a built Cuelume checkout directory.");
const source = resolve(process.argv[2]);
if (execFileSync("git", ["-C", source, "rev-parse", "HEAD"], { encoding: "utf8" }).trim() !== revision) {
  throw new Error(`Expected Cuelume ${revision}`);
}
const { stereo, wav } = await import(pathToFileURL(resolve(source, "scripts/sound.mjs")));
const output = new URL("../Sources/BlitzClean/Resources/Cuelume/", import.meta.url);
mkdirSync(output, { recursive: true });
for (const cue of ["open", "tap", "select", "toggle", "ready", "success", "warning", "error"]) {
  const emphasis = ["open", "tap", "select", "toggle"].includes(cue) ? "subtle" : "normal";
  wav(new URL(`${cue}.wav`, output), [stereo("default", cue, { emphasis })], 0);
}
console.log("Rendered eight Cuelume cues.");
