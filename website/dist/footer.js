// Independent adaptation of OriginKit's Weight Hover interaction:
// https://www.originkit.dev/components/weight-hover
export function initFooter() {
  const footer = document.querySelector('.brand-footer');
  const wordmark = footer.querySelector('.brand-wordmark');
  const letters = [...wordmark.querySelectorAll('.brand-letter > span')];
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  let animations = [];
  let ready = false;

  function stop() {
    animations.forEach(animation => animation.cancel());
    animations = [];
  }

  function play() {
    if (!ready || reducedMotion.matches || document.hidden || animations.some(animation => animation.playState === 'running')) return;
    stop();
    animations = letters.map((letter, index) => letter.animate([
      { fontWeight: 800 },
      { fontWeight: 450, offset: .42 },
      { fontWeight: 800 }
    ], {
      duration: 750,
      delay: index * 70,
      easing: 'cubic-bezier(.4,0,.2,1)'
    }));
  }

  const observer = new IntersectionObserver(entries => {
    if (entries.some(entry => entry.intersectionRatio >= .65)) {
      play();
      observer.disconnect();
    }
  }, { threshold: .65 });

  document.fonts.ready.then(() => {
    ready = true;
    observer.observe(wordmark);
  });
  wordmark.addEventListener('pointerenter', event => {
    if (event.pointerType === 'mouse') play();
  });
  wordmark.addEventListener('pointerdown', event => {
    if (event.pointerType !== 'mouse') play();
  });
  footer.addEventListener('focusin', play);
  reducedMotion.addEventListener('change', () => { if (reducedMotion.matches) stop(); });
  document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });
}
