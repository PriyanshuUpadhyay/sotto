const views = {
  history: document.getElementById('view-history'),
  models: document.getElementById('view-models'),
  stub: document.getElementById('view-stub'),
  settings: document.getElementById('view-settings'),
};

document.querySelectorAll('.nav-item').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach(b => {
      b.classList.remove('sel');
      b.removeAttribute('aria-current');
    });
    btn.classList.add('sel');
    btn.setAttribute('aria-current', 'page');
    Object.values(views).forEach(v => v.hidden = true);
    const v = btn.dataset.view;
    views[v].hidden = false;
    if (v === 'stub') document.getElementById('stubTitle').textContent = btn.dataset.title;
  });
});

document.querySelectorAll('.model').forEach(card => {
  card.addEventListener('click', () => {
    document.querySelectorAll('.model').forEach(m => {
      m.setAttribute('aria-pressed', 'false');
      m.querySelector('.chip-active').hidden = true;
    });
    card.setAttribute('aria-pressed', 'true');
    card.querySelector('.chip-active').hidden = false;
    document.getElementById('micName').textContent = card.dataset.name;
  });
});

const segRadios = [...document.querySelectorAll('.seg [role="radio"]')];
function pickSeg(btn) {
  segRadios.forEach(b => {
    const on = b === btn;
    b.classList.toggle('sel', on);
    b.setAttribute('aria-checked', String(on));
    b.tabIndex = on ? 0 : -1;
  });
  document.getElementById('promptRow').classList.toggle('dim', btn.textContent.trim() === 'Off');
}
segRadios.forEach(btn => {
  btn.addEventListener('click', () => pickSeg(btn));
  btn.addEventListener('keydown', e => {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) return;
    e.preventDefault();
    const other = segRadios[(segRadios.indexOf(btn) + 1) % segRadios.length];
    pickSeg(other);
    other.focus();
  });
});

const swatches = [...document.querySelectorAll('.swatch')];
function pickSwatch(btn) {
  swatches.forEach(b => {
    const on = b === btn;
    b.setAttribute('aria-checked', String(on));
    b.tabIndex = on ? 0 : -1;
  });
  document.documentElement.style.setProperty('--phosphor', btn.dataset.hex);
  document.documentElement.style.setProperty('--accent-rgb', btn.dataset.rgb);
}
swatches.forEach(btn => {
  btn.addEventListener('click', () => pickSwatch(btn));
  btn.addEventListener('keydown', e => {
    const dir = {ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1}[e.key];
    if (!dir) return;
    e.preventDefault();
    const next = swatches[(swatches.indexOf(btn) + dir + swatches.length) % swatches.length];
    pickSwatch(next);
    next.focus();
  });
});
