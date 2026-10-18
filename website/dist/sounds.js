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

export async function cue(name, { volume = 0.7, automatic = false, signal } = {}) {
  if (document.hidden || signal?.aborted) return;
  const now = performance.now();
  if (automatic && now - lastPlay < 300) return;
  if (['tap', 'select', 'toggle'].includes(name) && now - lastPlay < 80) return;
  if (!automatic) lastPlay = now;
  const request = ++latest;
  try {
    context ??= new (window.AudioContext || window.webkitAudioContext)();
    const resumed = context.resume();
    if (automatic) {
      // Never leave an intro cue waiting for a later, unrelated user gesture.
      const allowed = await Promise.race([
        resumed.then(() => true),
        new Promise(resolve => setTimeout(() => resolve(false), 150))
      ]);
      if (!allowed) return;
    } else await resumed;
    if (!buffers.has(name)) {
      const bytes = await files.get(name);
      if (!bytes) return;
      buffers.set(name, await context.decodeAudioData(bytes.slice(0)));
    }
    if (request !== latest || document.hidden || signal?.aborted || (automatic && performance.now() - now > 250)) return;
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
  } catch {
    // Browsers may deny audio; interactions must still work.
  }
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) { latest++; player?.stop(); }
});
