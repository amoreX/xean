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

export async function cue(name) {
  if (document.hidden) return;
  const now = performance.now();
  if (['tap', 'select', 'toggle'].includes(name) && now - lastPlay < 80) return;
  lastPlay = now;
  const request = ++latest;
  try {
    context ??= new (window.AudioContext || window.webkitAudioContext)();
    await context.resume();
    if (!buffers.has(name)) {
      const bytes = await files.get(name);
      if (!bytes) return;
      buffers.set(name, await context.decodeAudioData(bytes.slice(0)));
    }
    if (request !== latest || document.hidden) return;
    player?.stop();
    player = context.createBufferSource();
    player.buffer = buffers.get(name);
    const gain = context.createGain();
    gain.gain.value = 0.7;
    player.connect(gain).connect(context.destination);
    player.start();
  } catch {
    // Browsers may deny audio; interactions must still work.
  }
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) { latest++; player?.stop(); }
});
