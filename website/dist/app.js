const rows = [...document.querySelectorAll('.cache-row')];
const cleanButton = document.querySelector('#clean-button');
const selectionView = document.querySelector('#selection-view');
const successView = document.querySelector('#success-view');
const totalLabel = document.querySelector('#selection-total');
const status = document.querySelector('#demo-status');
const statsSwitch = document.querySelector('#show-stats');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let cleaning = false;
let completed = false;

const selectedRows = () => rows.filter(row => row.querySelector('input').checked);
const sizeOf = row => Number(row.dataset.size);
const gigabytes = size => (size / 1000).toFixed(1);
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

function updateSelection() {
  const selected = selectedRows();
  totalLabel.textContent = `${gigabytes(selected.reduce((sum, row) => sum + sizeOf(row), 0))} GB selected`;
  cleanButton.disabled = selected.length === 0;
  status.textContent = selected.length ? 'Your choice. One click.' : 'Choose something to clean.';
}

function updateFreeSpace(removed = 0) {
  const free = 23.8 + removed / 1000;
  document.querySelector('#free-space').textContent = `${free.toFixed(1)} GB free`;
  document.querySelector('#menu-free').textContent = `${Math.round(free)} GB`;
}

rows.forEach(row => row.querySelector('input').addEventListener('change', updateSelection));
statsSwitch.addEventListener('change', () => {
  document.querySelector('#menu-stats').hidden = !statsSwitch.checked;
});

cleanButton.addEventListener('click', async () => {
  if (cleaning || completed) return;
  const selected = selectedRows();
  if (!selected.length) return;
  cleaning = true;
  cleanButton.disabled = true;
  cleanButton.textContent = 'Cleaning…';
  rows.forEach(row => { row.querySelector('input').disabled = true; });
  let removed = 0;
  status.textContent = 'Clearing the example files…';
  for (const row of selected) {
    await wait(reducedMotion.matches ? 0 : 230);
    row.classList.add('is-cleared');
    row.inert = true;
    removed += sizeOf(row);
    updateFreeSpace(removed);
  }
  await wait(reducedMotion.matches ? 0 : 180);
  document.querySelector('#removed-total').textContent = gigabytes(removed);
  document.querySelector('#success-description').textContent = `${selected.length} example ${selected.length === 1 ? 'category' : 'categories'} cleared. A little more breathing room.`;
  selectionView.hidden = true;
  successView.hidden = false;
  cleanButton.hidden = true;
  status.textContent = 'Demo complete. Your Mac’s files haven’t changed.';
  cleaning = false;
  completed = true;
  document.querySelector('#reset-demo').focus({ preventScroll: true });
});

document.querySelector('#reset-demo').addEventListener('click', () => {
  rows.forEach((row, index) => {
    row.classList.remove('is-cleared');
    row.inert = false;
    const checkbox = row.querySelector('input');
    checkbox.disabled = false;
    checkbox.checked = index < 5;
  });
  selectionView.hidden = false;
  successView.hidden = true;
  cleanButton.hidden = false;
  cleanButton.textContent = 'Clean';
  completed = false;
  updateFreeSpace();
  updateSelection();
  cleanButton.focus({ preventScroll: true });
});

updateSelection();
