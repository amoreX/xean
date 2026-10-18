const cues = ['tap', 'select', 'toggle', 'ready', 'success', 'warning', 'error'];
const files = new Map(cues.map(name => [name, fetch(new URL('./assets/sounds/' + name + '.wav', import.meta.url)).then(r => {
  if (!r.ok) throw new Error('Unable to load ' + name + ' cue');
  return r.arrayBuffer();
}).catch(() => null)]));
const buffers = new Map();
let context;
let player;
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
  if (hover && now - lastPlay < 120) return false;
  if (['tap', 'select', 'toggle'].includes(name) && now - lastPlay < 80) return false;
  try {
    context ??= new (window.AudioContext || window.webkitAudioContext)();
    // Hover cannot unlock audio. Skip it instead of queueing sounds for a later click.
    if (hover && context.state !== 'running') return false;
    if (!automatic) lastPlay = now;
    const request = ++latest;
    if (automatic) {
      // Never leave an intro cue waiting for a later, unrelated user gesture.
      if (!await unlockAudio()) return false;
    } else if (!hover) {
      await context.resume();
    }
    if (!buffers.has(name)) {
      const bytes = await files.get(name);
      if (!bytes) return false;
      buffers.set(name, await context.decodeAudioData(bytes.slice(0)));
    }
    if (request !== latest || document.hidden || signal?.aborted || ((automatic || hover) && performance.now() - now > 250)) return false;
    player?.stop();
    const source = context.createBufferSource();
    player = source;
    player.buffer = buffers.get(name);
    player.playbackRate.value = playbackRate;
    const gain = context.createGain();
    gain.gain.value = volume;
    player.connect(gain).connect(context.destination);
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
  if (document.hidden) { latest++; player?.stop(); }
});
