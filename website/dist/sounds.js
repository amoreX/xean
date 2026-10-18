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

export async function unlockAudio() {
  try {
    context ??= new (window.AudioContext || window.webkitAudioContext)();
    return await Promise.race([
      context.resume().then(() => context.state === 'running'),
      new Promise(resolve => setTimeout(() => resolve(false), 150))
    ]);
  } catch { return false; }
}

export async function cue(name, { volume = 0.7, automatic = false, signal } = {}) {
  if (document.hidden || signal?.aborted) return false;
  const now = performance.now();
  if (automatic && now - lastPlay < 300) return false;
  if (['tap', 'select', 'toggle'].includes(name) && now - lastPlay < 80) return false;
  if (!automatic) lastPlay = now;
  const request = ++latest;
  try {
    if (automatic) {
      // Never leave an intro cue waiting for a later, unrelated user gesture.
      if (!await unlockAudio()) return false;
    } else {
      context ??= new (window.AudioContext || window.webkitAudioContext)();
      await context.resume();
    }
    if (!buffers.has(name)) {
      const bytes = await files.get(name);
      if (!bytes) return false;
      buffers.set(name, await context.decodeAudioData(bytes.slice(0)));
    }
    if (request !== latest || document.hidden || signal?.aborted || (automatic && performance.now() - now > 250)) return false;
    player?.stop();
    const source = context.createBufferSource();
    player = source;
    player.buffer = buffers.get(name);
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
