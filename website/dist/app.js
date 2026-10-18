import { cue } from './sounds.js?v=20261019-no-demo-controls';
import { initDemo } from './demo.js?v=20261019-page-arrival';
import { initFooter } from './footer.js?v=20261019-footer-preview';

const installPrompt = [
  'Help me install and launch xean, the native macOS menu bar cleaner, from https://github.com/amoreX/xean.',
  'Check that I am on macOS 14 or newer and have full Xcode 26 or newer selected with xcode-select. If a prerequisite is missing, tell me what to install before continuing.',
  'Clone the repository into an appropriate development folder, or reuse an existing checkout without overwriting local changes. Read its AGENTS.md and README.md, then run ./start.sh from the repository root to build and launch the app. If an existing build needs updating, have me quit xean before running ./start.sh --build.',
  'Verify that the menu bar app opens. Do not enable auto-clean or delete any of my files as part of setup.'
].join('\n\n');
const shell = document.querySelector('#install-shell');
const trigger = document.querySelector('#get-xean');
const options = document.querySelector('#install-options');
const copyButton = document.querySelector('#agent-install');
let copyReset;

function expandInstall(expanded) {
  shell.classList.toggle('expanded', expanded);
  trigger.setAttribute('aria-expanded', String(expanded));
  options.inert = !expanded;
}
trigger.addEventListener('click', () => {
  cue('tap');
  expandInstall(trigger.getAttribute('aria-expanded') !== 'true');
});
shell.addEventListener('keydown', event => {
  if (event.key === 'Escape') { expandInstall(false); trigger.focus(); cue('tap'); }
});
document.addEventListener('pointerdown', event => {
  if (!shell.contains(event.target) && !document.querySelector('#copy-fallback').contains(event.target)) expandInstall(false);
});
copyButton.addEventListener('click', async () => {
  cue('select');
  clearTimeout(copyReset);
  try {
    await navigator.clipboard.writeText(installPrompt);
    document.querySelector('#agent-label').textContent = 'Prompt copied';
    copyButton.querySelector('use').setAttribute('href', '#check');
    document.querySelector('#install-status').textContent = 'Prompt copied. Paste it into your coding agent.';
    document.querySelector('#copy-fallback').hidden = true;
    cue('success');
    copyReset = setTimeout(() => {
      document.querySelector('#agent-label').textContent = 'Let your agent do it';
      copyButton.querySelector('use').setAttribute('href', '#copy');
    }, 5000);
  } catch {
    cue('error');
    document.querySelector('#copy-fallback').hidden = false;
    const fallback = document.querySelector('#manual-prompt');
    fallback.value = installPrompt;
    fallback.focus();
    fallback.select();
    document.querySelector('#install-status').textContent = 'Clipboard unavailable. Copy the prompt from the text field.';
  }
});
document.querySelectorAll('[data-sound]').forEach(link => link.addEventListener('click', () => cue(link.dataset.sound)));
initDemo(cue);
initFooter();
