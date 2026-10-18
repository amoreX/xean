const catalog = [
  ['claude', 'Claude Code', 'CLI and app caches', [['claude-cache', 'Cache', '~/.claude/cache', 2100]]],
  ['codex', 'Codex', 'Desktop caches; sessions stay', [['codex-cache', 'Cache', '~/Library/Application Support/Codex/Cache', 840]]],
  ['superconductor', 'Superconductor', 'Desktop and web caches', [['super-cache', 'Cache', '~/Library/Caches/Superconductor', 420]]],
  ['editors', 'Coding editors', 'Cursor, VS Code, Windsurf and Zed', [['editor-cache', 'Code Cache', '~/Library/Application Support/Cursor/Code Cache', 1400]]],
  ['packages', 'Package caches', 'npm, Yarn, pip, uv, Bun and Homebrew', [['npm-cache', '_cacache', '~/.npm/_cacache', 3200]]],
  ['browsers', 'Browser caches', 'Safari, Chrome and Firefox', [['browser-cache', 'Cache', '~/Library/Caches/Google/Chrome/Default/Cache', 920]]],
  ['builds', 'Build files', 'Xcode, Swift, Rust and web build output', [['next-build', '.next', '~/Code/studio/.next', 4800]]],
  ['dependencies', 'Project dependencies', 'Inactive node_modules with a lockfile', [['node-modules', 'node_modules', '~/Code/studio/node_modules', 1600]]],
  ['docker', 'Docker build cache', 'Unused build cache; containers and volumes stay', [['docker-cache', 'Unused build cache', 'Local Docker builder', 2400]]],
  ['worktrees', 'Old worktrees', 'Clean, merged, inactive Git worktrees', [
    ['auth-worktree', 'studio-auth', '~/.codex/worktrees/studio-auth', 3100, 'agent/auth-cleanup'],
    ['settings-worktree', 'studio-settings', '~/.codex/worktrees/studio-settings', 2400, 'agent/settings'],
    ['active-worktree', 'studio-in-progress', '~/.codex/worktrees/studio-in-progress', 680, 'agent/current-work', 'This worktree has uncommitted changes. It stays on your Mac.']
  ]]
];
const defaults = ['claude', 'codex', 'superconductor', 'editors', 'packages', 'builds'];
const initialFreeSpace = 4.7;
const $ = selector => document.querySelector(selector);
const icon = name => '<svg class="icon" aria-hidden="true"><use href="#' + name + '"/></svg>';
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const sizeLabel = mb => mb >= 1000 ? (mb / 1000).toFixed(1).replace(/\.0$/, '') + ' GB' : mb + ' MB';
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const motion = { row: 240, value: 400, view: 220, scroll: 650, pointer: 440, sweep: 240, depart: 140, collapse: 160, zoom: 800 };
const easeInOut = progress => progress < 0.5 ? 4 * progress ** 3 : 1 - (-2 * progress + 2) ** 3 / 2;

export function initDemo(cue) {
  let categories;
  let selected;
  let free = initialFreeSpace;
  let busy = false;
  let version = 0;
  let screen = 'settings';
  let previousScreen = 'settings';
  let tourEnabled = !reducedMotion.matches;
  let tourVersion = 0;
  let tourRunning = false;
  let visible = true;
  let sample = 0;
  let memoryMode = 'available';
  let feedbackTimer;
  let scrollGeneration = 0;
  let desktopWidth = 0;
  const panel = $('#cleaner');
  const stage = $('#demo-stage');
  const cursor = $('#desktop-cursor');
  const notifications = [...document.querySelectorAll('.storage-notification')];
  const scroller = $('#app-scroll');
  const numberAnimations = new Map();

  function fitDesktop() {
    const width = stage.clientWidth;
    if (width === desktopWidth) return;
    desktopWidth = width;
    const focusedWidth = Math.min(440, width);
    stage.style.setProperty('--desktop-height', width * 563 / 900 + 'px');
    stage.style.setProperty('--desktop-scale', width / 900);
    stage.style.setProperty('--focus-width', focusedWidth + 'px');
    stage.style.setProperty('--panel-width', focusedWidth - 20 + 'px');
    stage.style.setProperty('--camera-x', focusedWidth / 2 - 650 + 'px');
  }

  function focusDesktop(focused) {
    stage.classList.toggle('focused', focused);
    if (focused) notifications.forEach(notification => notification.classList.remove('visible'));
  }

  function hideCursor() {
    cursor.classList.remove('visible', 'pressed');
  }

  function animateValue(element, target, format, initial = target) {
    const prior = numberAnimations.get(element);
    if (prior) cancelAnimationFrame(prior.frame);
    const from = prior?.value ?? initial;
    const state = { value: from, frame: 0 };
    numberAnimations.set(element, state);
    const start = performance.now();
    function step(now) {
      const progress = reducedMotion.matches || document.hidden ? 1 : Math.min(1, (now - start) / motion.value);
      state.value = from + (target - from) * (1 - Math.pow(1 - progress, 3));
      element.textContent = format(state.value);
      if (progress < 1) state.frame = requestAnimationFrame(step);
    }
    step(start);
  }

  function updateWarning() {
    const low = $('#notify-low').checked && free < Number($('#warning-limit').value);
    $('#low-warning').hidden = !low;
    $('#open-preview').classList.toggle('has-warning', low);
  }

  function updateSpace() {
    animateValue($('#free-space'), free, n => n.toFixed(1) + ' GB free', initialFreeSpace);
    animateValue($('#menu-free'), free, n => Math.round(n) + ' GB', initialFreeSpace);
    updateWarning();
  }

  function renderMetrics() {
    const stats = $('#menu-stats');
    const before = stats.getBoundingClientRect().width;
    stats.getAnimations().forEach(animation => animation.cancel());
    stats.classList.toggle('stats-hidden', !$('#show-stats').checked);
    for (const name of ['cpu', 'memory', 'disk']) {
      $('#' + name + '-stat').hidden = !$('#show-' + name).checked;
    }
    const checked = [...document.querySelectorAll('.metric-toggle')].filter(input => input.checked);
    document.querySelectorAll('.metric-toggle').forEach(input => { input.disabled = checked.length === 1 && input.checked; });
    $('#memory-format').hidden = !$('#show-memory').checked;
    const after = stats.getBoundingClientRect().width;
    if (Math.abs(after - before) > 1 && !reducedMotion.matches) {
      stats.animate([{ width: before + 'px' }, { width: after + 'px' }], { duration: 200, easing: 'ease-in-out' });
    }
  }

  function setStatsEnabled(enabled) {
    $('#show-stats').checked = enabled;
    $('#stats-options').classList.toggle('expanded', enabled);
    $('#stats-options').inert = !enabled;
    renderMetrics();
  }

  function sampleMetrics() {
    if (!visible || document.hidden || !$('#show-stats').checked) return;
    const cpus = busy ? [42, 56, 39, 48] : [18, 24, 16, 31, 22, 12];
    const memory = [8.2, 7.9, 8.4, 8.1, 7.6, 8.3][sample % 6];
    animateValue($('#menu-cpu'), cpus[sample % cpus.length], n => Math.round(n) + '%', 18);
    const value = memoryMode === 'available' ? memory : memoryMode === 'used' ? 32 - memory : (32 - memory) / 32 * 100;
    const format = memoryMode === 'available' ? n => Math.round(n) + ' GB free' : memoryMode === 'used' ? n => Math.round(n) + ' GB used' : n => Math.round(n) + '%';
    animateValue($('#menu-memory'), value, format, value);
    sample++;
  }

  function setScreen(next) {
    const views = [$('#settings-view'), $('#cleanup-view'), $('#result-view')];
    const previous = views.find(view => !view.hidden);
    screen = next;
    panel.dataset.screen = next;
    $('#quit-view').hidden = next !== 'quit';
    $('#app-view').hidden = ['quit', 'closed'].includes(next);
    $('#settings-view').hidden = next !== 'settings';
    $('#cleanup-view').hidden = !['scanning', 'cleaning'].includes(next);
    $('#result-view').hidden = next !== 'result';
    const active = views.find(view => !view.hidden);
    if (active && active !== previous && !reducedMotion.matches) {
      active.getAnimations().forEach(animation => animation.cancel());
      active.animate([{ opacity: 0.35 }, { opacity: 1 }], { duration: motion.view, easing: 'ease-out' });
    }
    $('#open-preview').setAttribute('aria-label', next === 'closed' ? 'Open xean preview' : 'Close xean preview');
    if (next === 'closed') {
      hideCursor();
      focusDesktop(false);
      $('#automatic-row').hidden = false;
      $('#auto-confirm').hidden = true;
      $('#demo-announcement').textContent = '';
      feedback('');
    }
  }

  function syncSelection() {
    $('#clean-button').disabled = selected.size === 0 || busy;
    $('#worktree-age').hidden = !($('#auto-clean').checked && selected.has('worktrees'));
    document.querySelectorAll('.category-select').forEach(input => {
      input.checked = selected.has(input.dataset.category);
      input.disabled = busy;
    });
  }

  function inventoryMarkup(item) {
    return '<div class="inventory-row" id="item-' + item.id + '"><div class="inventory-clip"><div class="inventory-line"><div class="inventory-copy"><span>' +
      (item.protected ? icon('lock') : '') + item.name + '</span>' +
      (item.branch ? '<small>' + item.branch + '</small>' : '') + '<small>' + item.path + '</small>' +
      (item.protected ? '<small>' + item.protected + '</small>' : '') +
      '</div><div class="inventory-actions"><span>' + sizeLabel(item.mb) + '</span>' +
      (item.protected ? '' : '<button type="button" class="delete-item" data-item="' + item.id + '" aria-label="Delete ' + item.name + '">Delete</button>') +
      '</div></div></div></div>';
  }

  function renderInventory(category) {
    const target = $('#inventory-' + category.id);
    const hadContent = target.childElementCount > 0;
    const before = target.getBoundingClientRect().height;
    target.getAnimations().forEach(animation => animation.cancel());
    target.innerHTML = category.loading ? '<p class="inventory-message">Checking…</p>' :
      category.items.filter(item => !item.removed).map(inventoryMarkup).join('') || '<p class="inventory-message">No items 50 MB or larger.</p>';
    $('#category-' + category.id).querySelector('.category-loading').hidden = !category.loading;
    const after = target.getBoundingClientRect().height;
    if (hadContent && Math.abs(after - before) > 1 && !reducedMotion.matches) {
      target.animate([{ height: before + 'px' }, { height: after + 'px' }], {
        duration: motion.row, easing: 'cubic-bezier(.4,0,.2,1)'
      });
    }
  }

  function renderCategories() {
    $('#category-list').innerHTML = categories.map(category =>
      '<div class="category" id="category-' + category.id + '"><div class="category-row"><label class="category-select-target"><input class="category-select" type="checkbox" data-category="' + category.id +
      '" aria-label="Include ' + category.title + ' in Clean"' + (selected.has(category.id) ? ' checked' : '') +
      '></label><button class="category-trigger" type="button" data-category="' + category.id + '" aria-label="' + category.title + ' items" aria-expanded="false" aria-controls="inventory-panel-' + category.id +
      '"><span class="category-copy"><strong>' + category.title + '</strong><span>' + category.description +
      '</span></span><span class="category-indicator"><span class="spinner category-loading" hidden></span>' + icon('chevron') +
      '</span></button></div><div class="disclosure" id="inventory-panel-' + category.id + '" inert><div class="disclosure-clip"><div class="inventory" id="inventory-' + category.id + '"></div></div></div></div>'
    ).join('');
  }

  async function expandCategory(id, expanded) {
    const category = categories.find(item => item.id === id);
    const button = $('#category-' + id).querySelector('.category-trigger');
    const content = $('#inventory-panel-' + id);
    button.setAttribute('aria-expanded', String(expanded));
    content.inert = !expanded;
    content.classList.toggle('expanded', expanded);
    if (expanded && category.loaded) renderInventory(category);
    if (expanded && !category.loaded) {
      const current = version;
      category.loading = true;
      renderInventory(category);
      await wait(550);
      if (current !== version) return;
      category.loaded = true;
      category.loading = false;
      renderInventory(category);
    }
  }

  function scrollToElement(element) {
    const current = ++scrollGeneration;
    const from = scroller.scrollTop;
    const offset = element.getBoundingClientRect().top - scroller.getBoundingClientRect().top;
    const target = Math.max(0, Math.min(from + offset - 16, scroller.scrollHeight - scroller.clientHeight));
    if (Math.abs(target - from) < 1) return Promise.resolve(true);
    const start = performance.now();
    return new Promise(resolve => {
      function step(now) {
        if (current !== scrollGeneration) { resolve(false); return; }
        const progress = reducedMotion.matches ? 1 : Math.min(1, (now - start) / motion.scroll);
        scroller.scrollTop = from + (target - from) * easeInOut(progress);
        if (progress < 1) requestAnimationFrame(step);
        else resolve(true);
      }
      requestAnimationFrame(step);
    });
  }

  function feedback(text) {
    clearTimeout(feedbackTimer);
    $('#demo-status').textContent = text;
    feedbackTimer = setTimeout(() => { $('#demo-status').textContent = ''; }, 5000);
  }

  async function removeRow(row, current) {
    row.inert = true;
    row.setAttribute('aria-hidden', 'true');
    if (!reducedMotion.matches) {
      row.classList.add('removing');
      await wait(motion.sweep);
      if (current !== version) return false;
      row.classList.add('departing');
      await wait(motion.depart);
      if (current !== version) return false;
      row.classList.add('collapsed');
      await wait(motion.collapse);
      if (current !== version) return false;
    }
    row.remove();
    return true;
  }

  async function deleteItem(id) {
    if (busy) return;
    const item = categories.flatMap(category => category.items).find(candidate => candidate.id === id);
    if (!item || item.protected || item.removed) return;
    const current = version;
    busy = true;
    syncSelection();
    cue('tap');
    const row = $('#item-' + id);
    row.querySelector('button').disabled = true;
    await wait(220);
    if (current !== version) return;
    item.removed = true;
    free += item.mb / 1000;
    updateSpace();
    if (!await removeRow(row, current)) return;
    const category = categories.find(category => category.items.includes(item));
    if (category.items.every(item => item.removed)) renderInventory(category);
    busy = false;
    syncSelection();
    feedback('Removed 1 item · ' + sizeLabel(item.mb));
    cue('success');
  }

  async function clean(audible = true) {
    if (busy || selected.size === 0) return;
    const current = version;
    const active = categories.filter(category => selected.has(category.id)).flatMap(category => category.items).filter(item => !item.removed);
    const items = active.filter(item => !item.protected);
    const protectedCount = active.length - items.length;
    busy = true;
    if (audible) {
      cue('tap');
      $('#clean-button').classList.add('tour-pressed');
      await wait(reducedMotion.matches ? 0 : 180);
      $('#clean-button').classList.remove('tour-pressed');
      if (current !== version) return;
    }
    $('#cleanup-title').textContent = 'Checking selected items…';
    $('#cleanup-count').textContent = items.length + (items.length === 1 ? ' item' : ' items');
    $('#cleanup-queue').innerHTML = items.map(item => '<div class="queue-row" id="queue-' + item.id + '"><div class="queue-clip"><div class="queue-content"><div><strong>' + item.name + '</strong><small>' + item.path + '</small></div><span>' + sizeLabel(item.mb) + '</span></div></div></div>').join('');
    $('#cleanup-queue').scrollTop = 0;
    setScreen('scanning');
    await wait(reducedMotion.matches ? 0 : 500);
    if (current !== version) return;
    $('#cleanup-title').textContent = 'Cleaning…';
    $('#cleanup-count').textContent = '0 / ' + items.length;
    if (screen === 'quit') previousScreen = 'cleaning';
    else setScreen('cleaning');
    let removed = 0;
    let mb = 0;
    for (const item of items) {
      const row = $('#queue-' + item.id);
      row.classList.add('current');
      await wait(reducedMotion.matches ? 0 : 120);
      if (current !== version) return;
      item.removed = true;
      removed++;
      mb += item.mb;
      $('#cleanup-count').textContent = removed + ' / ' + items.length;
      free += item.mb / 1000;
      updateSpace();
      if (!await removeRow(row, current)) return;
    }
    await wait(reducedMotion.matches ? 0 : 180);
    if (current !== version) return;
    busy = false;
    $('#result-title').textContent = items.length ? 'All clean' : 'Nothing to clean';
    $('#result-bytes').textContent = items.length ? sizeLabel(mb) + ' removed' : 'No eligible items in the selected categories.';
    $('#result-count').textContent = items.length ? removed + (removed === 1 ? ' item removed' : ' items removed') : '';
    $('#result-kept').textContent = protectedCount ? protectedCount + ' protected ' + (protectedCount === 1 ? 'item' : 'items') + ' kept' : '';
    if (screen === 'quit') previousScreen = 'result';
    else setScreen('result');
    if (audible) {
      cue(items.length ? 'success' : 'ready');
      $('#demo-announcement').textContent = items.length ? sizeLabel(mb) + ' cleared in the preview. No real files were touched.' : 'Nothing to clean in this example.';
      if (screen === 'result') $('[data-action="done"]').focus({ preventScroll: true });
    }
  }

  function reset() {
    version++;
    scrollGeneration++;
    busy = false;
    free = initialFreeSpace;
    selected = new Set(defaults);
    categories = catalog.map(([id, title, description, items]) => ({
      id, title, description, loaded: false, loading: false,
      items: items.map(([itemID, name, path, mb, branch, protectedReason]) => ({ id: itemID, name, path, mb, branch, protected: protectedReason, removed: false }))
    }));
    $('#auto-clean').checked = false;
    $('#notify-low').checked = false;
    $('#start-login').checked = false;
    $('#auto-limit').value = 20;
    $('#warning-limit').value = 20;
    $('#automatic-row').hidden = false;
    $('#auto-confirm').hidden = true;
    $('#show-stats').checked = true;
    document.querySelectorAll('.metric-toggle').forEach(input => { input.checked = true; });
    $('#stats-options').classList.add('expanded');
    $('#stats-options').inert = false;
    memoryMode = 'available';
    document.querySelectorAll('[data-format]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.format === memoryMode)));
    feedback('');
    renderCategories();
    syncSelection();
    renderMetrics();
    updateSpace();
    hideCursor();
    cursor.style.removeProperty('--cursor-x');
    cursor.style.removeProperty('--cursor-y');
    notifications.forEach(notification => notification.classList.toggle('visible', reducedMotion.matches));
    setScreen('closed');
    scroller.scrollTop = 0;
  }

  function updateTourControl() {
    const button = $('#tour-toggle');
    button.setAttribute('aria-label', tourEnabled ? 'Pause demo' : 'Play demo');
    button.title = tourEnabled ? 'Pause demo' : 'Play demo';
    button.querySelector('use').setAttribute('href', tourEnabled ? '#pause' : '#play');
  }
  function pauseTour() {
    tourEnabled = false;
    tourVersion++;
    tourRunning = false;
    scrollGeneration++;
    hideCursor();
    document.querySelectorAll('.tour-highlight, .tour-pressed').forEach(control => control.classList.remove('tour-highlight', 'tour-pressed'));
    updateTourControl();
  }

  async function demonstrateClick(control, valid, activate) {
    if (!valid()) return false;
    if (scroller.contains(control)) {
      const bounds = control.getBoundingClientRect();
      const viewport = scroller.getBoundingClientRect();
      if (bounds.top < viewport.top + 16 || bounds.bottom > viewport.bottom - 16) {
        if (!await scrollToElement(control) || !valid()) return false;
      }
    }
    const bounds = control.getBoundingClientRect();
    const scene = $('#desktop-scene').getBoundingClientRect();
    const scale = scene.width / 900;
    // Keep the cursor tip on the real control in both desktop and zoomed coordinates.
    const x = control.classList.contains('category-trigger') ? bounds.right - 12 : bounds.left + bounds.width / 2;
    cursor.style.setProperty('--cursor-x', (x - scene.left) / scale - 3 + 'px');
    cursor.style.setProperty('--cursor-y', (bounds.top + bounds.height / 2 - scene.top) / scale - 2 + 'px');
    cursor.classList.add('visible');
    await wait(motion.pointer);
    if (!valid()) return false;
    control.classList.add('tour-highlight');
    await wait(200);
    if (!valid()) return false;
    cursor.classList.add('pressed');
    control.classList.add('tour-pressed');
    await wait(140);
    if (!valid()) return false;
    const activation = activate();
    cursor.classList.remove('pressed');
    control.classList.remove('tour-pressed');
    await activation;
    await wait(240);
    control.classList.remove('tour-highlight');
    if (valid()) hideCursor();
    return valid();
  }

  async function runTour() {
    if (!tourEnabled || tourRunning || !visible || document.hidden) return;
    tourRunning = true;
    const current = ++tourVersion;
    const valid = () => current === tourVersion && tourEnabled && visible && !document.hidden;
    await wait(300);
    if (!valid()) return;
    for (const notification of notifications) {
      notification.classList.add('visible');
      await wait(700);
      if (!valid()) return;
    }
    await wait(600);
    if (!valid()) return;
    if (!await demonstrateClick($('#open-preview'), valid, () => setScreen('settings'))) return;
    await wait(300);
    if (!valid()) return;
    focusDesktop(true);
    await wait(motion.zoom + 700);
    if (!valid()) return;

    if (!await demonstrateClick($('#auto-clean'), valid, () => {
      $('#automatic-row').hidden = true;
      $('#auto-confirm').hidden = false;
    })) return;
    await wait(500);
    if (!valid()) return;
    if (!await demonstrateClick($('[data-action="confirm-auto"]'), valid, () => {
      $('#auto-clean').checked = true;
      $('#automatic-row').hidden = false;
      $('#auto-confirm').hidden = true;
      syncSelection();
    })) return;
    if (!await demonstrateClick($('#notify-low'), valid, () => {
      $('#notify-low').checked = true;
      updateWarning();
    })) return;
    await wait(650);
    if (!valid()) return;

    for (const category of categories.filter(category => ['claude', 'worktrees'].includes(category.id))) {
      const row = $('#category-' + category.id);
      if (!await scrollToElement(row) || !valid()) return;
      if (category.id === 'worktrees') {
        if (!await demonstrateClick(row.querySelector('.category-select'), valid, () => {
          selected.add('worktrees');
          syncSelection();
        })) return;
      }
      const trigger = row.querySelector('.category-trigger');
      if (!await demonstrateClick(trigger, valid, () => expandCategory(category.id, true))) return;
      await wait(category.id === 'worktrees' ? 1800 : 1100);
      if (!valid()) return;
      const lastItem = row.querySelector('.inventory-row:last-child');
      if (lastItem.getBoundingClientRect().bottom > scroller.getBoundingClientRect().bottom - 16) {
        if (!await scrollToElement(lastItem) || !valid()) return;
        await wait(1200);
        if (!valid()) return;
      }
      if (!await demonstrateClick(trigger, valid, () => expandCategory(category.id, false))) return;
      await wait(motion.row);
      if (!valid()) return;
    }

    if (!await scrollToElement($('.app-settings')) || !valid()) return;
    await wait(500);
    if (!valid()) return;
    if (!await demonstrateClick($('#show-stats'), valid, () => setStatsEnabled(false))) return;
    await wait(500);
    if (!valid()) return;
    if (!await demonstrateClick($('#clean-button'), valid, () => {})) return;
    await clean(false);
    if (!valid()) return;
    await wait(3200);
    if (!valid()) return;
    if (!await demonstrateClick($('[data-action="done"]'), valid, () => setScreen('closed'))) return;
    await wait(motion.zoom);
    if (!valid()) return;
    reset();
    tourRunning = false;
    runTour();
  }

  panel.addEventListener('pointerdown', () => { pauseTour(); focusDesktop(true); });
  panel.addEventListener('focusin', () => { pauseTour(); focusDesktop(true); });
  panel.addEventListener('keydown', event => {
    pauseTour();
    if (event.key === 'Escape' && screen === 'quit') {
      setScreen(previousScreen);
      $('[data-action="request-quit"]').focus({ preventScroll: true });
    }
  });
  panel.addEventListener('wheel', pauseTour, { passive: true });
  panel.addEventListener('click', event => {
    const categoryButton = event.target.closest('.category-trigger');
    if (categoryButton && !busy) {
      cue('toggle');
      expandCategory(categoryButton.dataset.category, categoryButton.getAttribute('aria-expanded') !== 'true');
    }
    const deleteButton = event.target.closest('.delete-item');
    if (deleteButton) deleteItem(deleteButton.dataset.item);
    const action = event.target.closest('[data-action]')?.dataset.action;
    if (!action) return;
    cue(action === 'confirm-auto' ? 'select' : 'tap');
    if (action === 'request-quit') {
      previousScreen = screen;
      setScreen('quit');
      $('[data-action="cancel-quit"]').focus({ preventScroll: true });
    }
    if (action === 'cancel-quit') {
      setScreen(previousScreen);
      $('[data-action="request-quit"]').focus({ preventScroll: true });
    }
    if (action === 'quit' || action === 'done') { version++; busy = false; setScreen('closed'); $('#open-preview').focus({ preventScroll: true }); }
    if (action === 'confirm-auto' || action === 'cancel-auto') {
      $('#auto-clean').checked = action === 'confirm-auto';
      $('#automatic-row').hidden = false;
      $('#auto-confirm').hidden = true;
      syncSelection();
      $('#auto-clean').focus({ preventScroll: true });
    }
  });
  $('#category-list').addEventListener('change', event => {
    const id = event.target.dataset.category;
    if (!id) return;
    event.target.checked ? selected.add(id) : selected.delete(id);
    syncSelection();
    cue('toggle');
  });
  $('#auto-clean').addEventListener('change', () => {
    if ($('#auto-clean').checked) {
      $('#auto-clean').checked = false;
      $('#automatic-row').hidden = true;
      $('#auto-confirm').hidden = false;
      $('[data-action="cancel-auto"]').focus({ preventScroll: true });
      cue('warning');
    } else { syncSelection(); cue('toggle'); }
  });
  $('#notify-low').addEventListener('change', () => { updateWarning(); cue('toggle'); });
  document.querySelectorAll('.number-field').forEach(input => input.addEventListener('change', () => {
    input.value = Math.min(Number(input.max), Math.max(Number(input.min), Number(input.value) || Number(input.min)));
    updateWarning();
    cue('select');
  }));
  $('#show-stats').addEventListener('change', () => {
    setStatsEnabled($('#show-stats').checked);
    cue('toggle');
  });
  document.querySelectorAll('.metric-toggle').forEach(input => input.addEventListener('change', () => { renderMetrics(); cue('toggle'); }));
  document.querySelectorAll('[data-format]').forEach(button => button.addEventListener('click', () => {
    memoryMode = button.dataset.format;
    document.querySelectorAll('[data-format]').forEach(choice => choice.setAttribute('aria-pressed', String(choice === button)));
    sampleMetrics();
    cue('toggle');
  }));
  $('#start-login').addEventListener('change', () => cue('toggle'));
  $('#clean-button').addEventListener('click', () => clean());
  function togglePreview() {
    pauseTour();
    if (screen === 'closed') {
      categories.forEach(category => { category.loaded = true; });
      renderCategories();
      syncSelection();
      setScreen('settings');
      focusDesktop(true);
      scroller.scrollTop = 0;
      if (matchMedia('(max-width: 900px)').matches) {
        const current = version;
        // Wait for expansion so the page is tall enough to reveal the whole panel.
        setTimeout(() => {
          if (current === version && screen !== 'closed' && matchMedia('(max-width: 900px)').matches) {
            stage.scrollIntoView({ block: 'start', behavior: reducedMotion.matches ? 'auto' : 'smooth' });
          }
        }, reducedMotion.matches ? 0 : motion.zoom);
      }
    } else { version++; busy = false; setScreen('closed'); }
  }
  $('#open-preview').addEventListener('click', togglePreview);
  $('#tour-toggle').addEventListener('click', () => {
    cue('tap');
    if (tourEnabled) pauseTour();
    else { tourEnabled = true; reset(); updateTourControl(); runTour(); }
  });
  $('#replay-demo').addEventListener('click', () => {
    cue('tap');
    pauseTour();
    reset();
    tourEnabled = !reducedMotion.matches;
    updateTourControl();
    runTour();
  });
  function updateVisibility() {
    const bounds = stage.getBoundingClientRect();
    const next = bounds.bottom > 0 && bounds.top < window.innerHeight;
    if (next === visible) return;
    visible = next;
    tourVersion++;
    tourRunning = false;
    hideCursor();
    if (visible && tourEnabled) { reset(); runTour(); }
  }
  window.addEventListener('scroll', updateVisibility, { passive: true });
  window.addEventListener('resize', updateVisibility);
  document.addEventListener('visibilitychange', () => {
    tourVersion++;
    tourRunning = false;
    hideCursor();
    if (!document.hidden && tourEnabled && visible) { reset(); runTour(); }
  });
  reducedMotion.addEventListener('change', () => { if (reducedMotion.matches) pauseTour(); });
  fitDesktop();
  new ResizeObserver(fitDesktop).observe(stage);
  requestAnimationFrame(() => requestAnimationFrame(() => stage.classList.add('ready')));
  reset();
  updateTourControl();
  updateVisibility();
  setInterval(sampleMetrics, 2000);
  runTour();
}

