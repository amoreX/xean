// Pointer-driven variation of the existing OriginKit-inspired weight interaction:
// https://www.originkit.dev/components/weight-hover
export function initFooter(cue) {
  const wordmark = document.querySelector('.brand-wordmark');
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const rest = () => ({ weight: 800, x: 0, y: 0, tilt: 0 });
  const letters = [...wordmark.querySelectorAll('.brand-letter')].map(slot => ({
    slot, glyph: slot.querySelector('span'), current: rest(), target: rest()
  }));
  let frame = 0;
  let previousTime = 0;
  let pressed = false;
  let ready = false;
  let entranceReady = false;
  let visible = false;
  let previewPending = true;
  let previewStartedAt = null;
  let previewSoundAttempted = false;
  let previewAudio;
  let hoveredLetter = -1;
  let touch = null;
  let suppressClick = false;

  function soundForPointer(event, hover = true) {
    if (!event.isTrusted || !ready || document.hidden) return;
    let index = letters.findIndex(({ slot }) => {
      const bounds = slot.getBoundingClientRect();
      return event.clientX >= bounds.left && event.clientX <= bounds.right &&
        event.clientY >= bounds.top && event.clientY <= bounds.bottom;
    });
    if (index < 0 && hover && hoveredLetter >= 0 && (event.type === 'pointerleave' || touch?.dragging)) {
      const bounds = wordmark.getBoundingClientRect();
      if (event.clientY >= bounds.top && event.clientY <= bounds.bottom &&
          (event.clientX < bounds.left || event.clientX > bounds.right)) {
        index = event.clientX < bounds.left ? 0 : letters.length - 1;
      }
    }
    if (index < 0 || (hover && index === hoveredLetter)) return;
    const direction = hover && hoveredLetter >= 0 ? Math.sign(index - hoveredLetter) : 1;
    const first = hover && hoveredLetter >= 0 ? hoveredLetter + direction : index;
    for (let crossed = first; direction > 0 ? crossed <= index : crossed >= index; crossed += direction) {
      cue('tap', { hover, volume: .6, playbackRate: [0.9, 1, 1.12, 1.26][crossed] });
    }
    hoveredLetter = index;
  }

  function trackSwipe(event) {
    if (touch?.id !== event.pointerId) return false;
    if (!touch.dragging) {
      const dx = Math.abs(event.clientX - touch.start.clientX);
      const dy = Math.abs(event.clientY - touch.start.clientY);
      if (dx < 6 || dx <= dy) return false;
      touch.dragging = true;
      soundForPointer(touch.start);
    }
    soundForPointer(event);
    return true;
  }

  function render(time) {
    if (previewStartedAt !== null) {
      const progress = Math.min((time - previewStartedAt) / 1600, 1);
      const bounds = wordmark.getBoundingClientRect();
      const radius = bounds.width * .55;
      setTargets(bounds.left - radius + (bounds.width + radius * 2) * progress, bounds.top + bounds.height * .6);
      if (progress === 1) {
        previewPending = false;
        previewStartedAt = null;
        letters.forEach(letter => { letter.target = rest(); });
      }
    }
    const delta = previousTime ? Math.min(time - previousTime, 32) : 16;
    previousTime = time;
    const blend = 1 - Math.exp(-delta / 45);
    let moving = previewStartedAt !== null;
    for (const letter of letters) {
      for (const key of Object.keys(letter.current)) {
        const difference = letter.target[key] - letter.current[key];
        if (Math.abs(difference) > (key === 'weight' ? .2 : .01)) {
          letter.current[key] += difference * blend;
          moving = true;
        } else letter.current[key] = letter.target[key];
      }
      const { weight, x, y, tilt } = letter.current;
      letter.glyph.style.fontWeight = weight.toFixed(1);
      letter.glyph.style.transform = `translate(${x.toFixed(2)}px,${y.toFixed(2)}px) rotate(${tilt.toFixed(2)}deg)`;
    }
    frame = moving ? requestAnimationFrame(render) : 0;
    if (!moving) previousTime = 0;
  }

  function animate() {
    if (!frame) frame = requestAnimationFrame(render);
  }

  function follow(event) {
    if (!ready || reducedMotion.matches || document.hidden) return;
    previewAudio?.abort();
    previewPending = false;
    previewStartedAt = null;
    setTargets(event.clientX, event.clientY);
    animate();
  }

  function setTargets(clientX, clientY) {
    const bounds = wordmark.getBoundingClientRect();
    const radius = bounds.width * .55;
    for (const letter of letters) {
      // Measure the fixed slot, so a moving glyph never chases its own position.
      const slot = letter.slot.getBoundingClientRect();
      const dx = clientX - (slot.left + slot.width / 2);
      const dy = clientY - (slot.top + slot.height * .6);
      const proximity = Math.max(0, 1 - Math.hypot(dx, dy * .65) / radius);
      const influence = proximity * proximity * (3 - 2 * proximity);
      letter.target = {
        weight: 800 - (pressed ? 430 : 350) * influence,
        x: Math.max(-8, Math.min(8, dx * .09)) * influence,
        y: -(pressed ? 18 : 12) * influence,
        tilt: Math.max(-4, Math.min(4, dx * .06)) * influence
      };
    }
  }

  function release(immediate = false) {
    previewAudio?.abort();
    previewStartedAt = null;
    pressed = false;
    touch = null;
    hoveredLetter = -1;
    letters.forEach(letter => { letter.target = rest(); });
    if (immediate) {
      cancelAnimationFrame(frame);
      frame = 0;
      previousTime = 0;
      letters.forEach(letter => {
        letter.current = rest();
        letter.glyph.style.removeProperty('font-weight');
        letter.glyph.style.removeProperty('transform');
      });
    } else animate();
  }

  function preview() {
    if (!entranceReady || !visible || !previewPending || previewStartedAt !== null || reducedMotion.matches || document.hidden) return;
    previewStartedAt = performance.now();
    if (!previewSoundAttempted) {
      previewSoundAttempted = true;
      previewAudio = new AbortController();
      cue('ready', { automatic: true, signal: previewAudio.signal });
    }
    animate();
  }

  document.fonts.ready.then(() => { ready = true; });
  Promise.allSettled([document.fonts.ready, ...wordmark.getAnimations().map(animation => animation.finished)]).then(() => {
    entranceReady = true;
    preview();
  });
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting && entry.intersectionRatio >= .5;
    if (visible) preview();
    else release(true);
  }, { threshold: .5 }).observe(wordmark);
  wordmark.addEventListener('pointerenter', event => {
    if (event.pointerType === 'touch') return;
    soundForPointer(event);
    follow(event);
  });
  wordmark.addEventListener('pointermove', event => {
    if (event.pointerType === 'touch') {
      if (!trackSwipe(event)) return;
    } else soundForPointer(event);
    follow(event);
  });
  wordmark.addEventListener('click', event => {
    if (suppressClick) { suppressClick = false; return; }
    soundForPointer(event, false);
  });
  wordmark.addEventListener('pointerdown', event => {
    if (!event.isPrimary) return;
    suppressClick = false;
    if (event.pointerType === 'touch') {
      touch = { id: event.pointerId, start: event, dragging: false };
      hoveredLetter = -1;
      wordmark.setPointerCapture(event.pointerId);
    }
    pressed = true;
    follow(event);
  });
  wordmark.addEventListener('pointerup', event => {
    if (event.pointerType === 'touch') {
      if (touch?.id !== event.pointerId) return;
      // Very fast gestures can finish before a pointermove is delivered.
      trackSwipe(event);
      suppressClick = touch.dragging;
      release();
      return;
    }
    pressed = false;
    follow(event);
  });
  wordmark.addEventListener('pointerleave', event => {
    if (event.pointerType === 'touch') return;
    soundForPointer(event);
    release();
  });
  wordmark.addEventListener('pointercancel', event => {
    if (event.pointerType === 'touch' && touch?.id !== event.pointerId) return;
    release();
  });
  reducedMotion.addEventListener('change', () => { previewPending = false; release(true); });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) release(true);
    else preview();
  });
}
