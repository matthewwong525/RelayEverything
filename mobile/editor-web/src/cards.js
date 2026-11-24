// A note's files as the page draws them: a picture, a file's row, and a recording's card with its player and words.
// The app sends what each one shows; a tap on one goes back to the app as a `tap`.

const icon = {
  play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.4-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z" fill="currentColor"/></svg>',
  pause: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="5" width="4.2" height="14" rx="1.2" fill="currentColor"/><rect x="13.8" y="5" width="4.2" height="14" rx="1.2" fill="currentColor"/></svg>',
  mic: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
  doc: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 3h7l5 5v12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z M14 3v5h5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
  download: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 18h10a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.2 9.6 4.2 4.2 0 0 0 7 18zM12 10v6m-2.5-2.5L12 16l2.5-2.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  chevron: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  photo: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="9" cy="10" r="1.8" fill="currentColor"/><path d="M4 17l5-4.5 3.5 3 3-2.5L20 17" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
};

const escape = text => String(text ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

/// A length in milliseconds as minutes and seconds, such as 0:42.
export function clockOf(ms) {
  const seconds = Math.max(0, Math.floor((ms ?? 0) / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

function wavesOf(levels, done) {
  if (!levels?.length) {
    return `<svg viewBox="0 0 100 36" preserveAspectRatio="none" aria-hidden="true">
      <rect x="0" y="16.5" width="100" height="3" class="rest"/>${done > 0 ? `<rect x="0" y="16.5" width="${(done * 100).toFixed(2)}" height="3" class="played"/>` : ''}</svg>`;
  }
  const step = 100 / levels.length;
  const width = step * 0.55;
  const bars = levels.map((level, i) => {
    const x = step * (i + 0.5);
    const half = 18 * (0.12 + 0.88 * Math.max(0, Math.min(1, Number(level) || 0)));
    return `<rect x="${(x - width / 2).toFixed(2)}" y="${(18 - half).toFixed(2)}" width="${width.toFixed(2)}" height="${(2 * half).toFixed(2)}" class="${x / 100 <= done ? 'played' : 'rest'}"/>`;
  }).join('');
  return `<svg viewBox="0 0 100 36" preserveAspectRatio="none" aria-hidden="true">${bars}</svg>`;
}

function recording(view) {
  const known = (view.length ?? 0) > 0;
  const at = view.position;
  const done = known && at != null ? Math.max(0, Math.min(1, at / view.length)) : 0;
  const time = at == null ? (known ? clockOf(view.length) : '') : known ? `${clockOf(at)} / ${clockOf(view.length)}` : clockOf(at);
  const top = view.ready
    ? `<div class="player">
        <button type="button" class="play" data-action="${view.playing ? 'pause' : 'play'}" aria-label="${view.playing ? 'Pause' : 'Play'}">${view.playing ? icon.pause : icon.play}</button>
        <div class="waves" data-action="seek" role="slider" aria-label="Recording" aria-valuemin="0" aria-valuemax="100"
          aria-valuenow="${Math.round(done * 100)}" aria-valuetext="${escape(time)}" tabindex="-1">${wavesOf(view.levels, done)}</div>
        <span class="time">${escape(time)}</span>
      </div>`
    : `<div class="waiting">${icon.mic}<span>Still on your phone</span>${known ? `<span class="time">${clockOf(view.length)}</span>` : ''}</div>`;
  const status = view.status ?? 'empty';
  let words = '';
  if (status === 'words') {
    words = `<div class="rule"></div><button type="button" class="transcript" data-action="transcript"><span>Transcript</span>${icon.chevron}</button>`;
  } else if (status === 'writing') {
    words = '<div class="rule"></div><div class="status"><span>Writing the words…</span><div class="busy"><i></i></div></div>';
  } else if (status === 'failed') {
    words = `<div class="rule"></div><div class="status"><span>The words did not come. Your recording is safe.</span>
      ${view.why ? `<span class="why">Why: ${escape(view.why)}</span>` : ''}
      <button type="button" class="retry" data-action="retry">Try again</button></div>`;
  } else if (status === 'none') {
    words = '<div class="rule"></div><div class="status"><span>No words heard</span></div>';
  }
  return `<div class="card recording">${top}${words}</div>`;
}

function picture(view) {
  const inside = view.src
    ? `<img src="${escape(view.src)}" alt="${escape(view.name)}" draggable="false">`
    : `<div class="loading">${icon.photo}</div>`;
  return `<div class="picture" data-action="open" role="button" aria-label="${escape(view.name || 'Picture')}">${inside}</div>`;
}

function file(view) {
  const meta = [view.size, view.ready === false ? 'Download' : ''].filter(Boolean).join(' · ');
  return `<div class="card file" data-action="open" role="button">
    ${view.ready === false ? icon.download : icon.doc}<span class="name">${escape(view.name)}</span>${meta ? `<span class="meta">${escape(meta)}</span>` : ''}</div>`;
}

/// The HTML of one file's view; empty for a file the page has no view of.
export function cardHtml(view) {
  if (!view) return '';
  if (view.kind === 'picture') return picture(view);
  if (view.kind === 'recording') return recording(view);
  if (view.kind === 'file') return file(view);
  return '';
}

/// Draws [view] in [element] and sends each tap on it through [tap] with the file's [key].
export function drawCard(element, key, view, tap) {
  const html = cardHtml(view);
  element.classList.toggle('missing', !html);
  if (element.__drawn === html) return;
  element.__drawn = html;
  element.innerHTML = html;
  element.dataset.key = key;
  if (!element.__wired) {
    element.__wired = true;
    wire(element, tap);
  }
}

function wire(element, tap) {
  let seeking = null;
  const fraction = (waves, event) => {
    const box = waves.getBoundingClientRect();
    return box.width > 0 ? Math.max(0, Math.min(1, (event.clientX - box.left) / box.width)) : 0;
  };
  element.addEventListener('pointerdown', event => {
    const waves = event.target.closest?.('[data-action="seek"]');
    if (waves) {
      event.preventDefault();
      seeking = waves;
      waves.setPointerCapture?.(event.pointerId);
      tap(element.dataset.key, 'seek', fraction(waves, event));
    }
  });
  element.addEventListener('pointermove', event => {
    if (seeking) tap(element.dataset.key, 'seek', fraction(seeking, event));
  });
  const stop = () => { seeking = null; };
  element.addEventListener('pointerup', stop);
  element.addEventListener('pointercancel', stop);
  element.addEventListener('click', event => {
    const target = event.target.closest?.('[data-action]');
    event.preventDefault();
    event.stopPropagation();
    if (!target || target.dataset.action === 'seek') return;
    tap(element.dataset.key, target.dataset.action);
  });
}
