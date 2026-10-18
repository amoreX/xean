const cues = ['tap', 'select', 'toggle', 'ready', 'success', 'warning', 'error'];
const files = new Map(cues.map(name => [name, fetch(new URL('./assets/sounds/' + name + '.wav', import.meta.url)).then(r => {
  if (!r.ok) throw new Error('Unable to load ' + name + ' cue');
  return r.arrayBuffer();
}).catch(() => null)]));
const buffers = new Map();
let context;
let player;
const hoverPlayers = new Set();
let nextHoverAt = 0;
let latest = 0;
let lastPlay = -Infinity;

async function unlockAudio() {
  try {
    context ??= new (window.AudioContext || window.webkitAudioContext)();
    return await Promise.race([
      context.resume().then(() => context.state === 'running'),
      new Promise(resolve => setTimeout(() => resolve(false), 150))
    ]);
  } catch { return false; }
}

async function unlockOnInteraction(event) {
  if (!event.isTrusted || document.hidden) return;
  if (!await unlockAudio()) return;
  document.removeEventListener('click', unlockOnInteraction, true);
  document.removeEventListener('keydown', unlockOnInteraction, true);
}

// Register before the entrance animation or fonts finish, including on the page background.
document.addEventListener('click', unlockOnInteraction, { capture: true, passive: true });
document.addEventListener('keydown', unlockOnInteraction, { capture: true, passive: true });

export async function cue(name, { volume = 0.7, automatic = false, hover = false, playbackRate = 1, signal } = {}) {
  if (document.hidden || signal?.aborted) return false;
  const now = performance.now();
  if (automatic && now - lastPlay < 300) return false;
  if (!hover && ['tap', 'select', 'toggle'].includes(name) && now - lastPlay < 80) return false;
  try {
    context ??= new (window.AudioContext || window.webkitAudioContext)();
    // Hover cannot unlock audio. Skip it instead of queueing sounds for a later click.
    if (hover && context.state !== 'running') return false;
    if (!automatic && !hover) lastPlay = now;
    const request = hover ? latest : ++latest;
    if (automatic) {
      // Never leave an intro cue waiting for a later, unrelated user gesture.
      if (!await unlockAudio()) return false;
    } else if (!hover) {
      await context.resume();
    }
    if (!buffers.has(name)) {
      buffers.set(name, files.get(name).then(bytes => bytes && context.decodeAudioData(bytes.slice(0))));
    }
    const buffer = await buffers.get(name);
    if (!buffer) return false;
    if (request !== latest || document.hidden || signal?.aborted || ((automatic || hover) && performance.now() - now > 250)) return false;
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.playbackRate.value = playbackRate;
    const gain = context.createGain();
    gain.gain.value = volume;
    source.connect(gain).connect(context.destination);
    if (hover) {
      // Keep every crossing audible, including letters crossed within one mouse event.
      // Short overlapping voices avoid cutoffs; cap the scheduling tail during rapid reversals.
      const startAt = Math.max(context.currentTime, Math.min(nextHoverAt, context.currentTime + .12));
      nextHoverAt = startAt + .03;
      hoverPlayers.add(source);
      source.addEventListener('ended', () => {
        hoverPlayers.delete(source);
        source.disconnect();
        gain.disconnect();
      }, { once: true });
      gain.gain.setValueAtTime(volume, startAt);
      gain.gain.setTargetAtTime(0, startAt + .06, .012);
      source.start(startAt);
      source.stop(startAt + .12);
      return true;
    }
    player?.stop();
    player = source;
    if (signal) {
      const fadeOut = () => {
        gain.gain.setTargetAtTime(0, context.currentTime, .02);
        source.stop(context.currentTime + .08);
      };
      signal.addEventListener('abort', fadeOut, { once: true });
      source.addEventListener('ended', () => signal.removeEventListener('abort', fadeOut), { once: true });
    }
    player.start();
    return true;
  } catch {
    // Browsers may deny audio; interactions must still work.
    return false;
  }
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    latest++;
    player?.stop();
    hoverPlayers.forEach(source => source.stop());
    hoverPlayers.clear();
    nextHoverAt = 0;
  }
});
