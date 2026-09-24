#!/usr/bin/env bash
# =============================================================================
# Shared navigation for the generated pages.
#
# ONE DEFINITION. The generated pages are self-contained HTML files with their
# own CSS, so a nav bar written into each would be copies drifting apart. Each
# generator cats these functions into its output instead.
#
# WHAT IT HAS TO SOLVE. The site is three levels deep across an open-ended
# number of branches: / -> /<slug>/ -> /<slug>/tests/. From the board a reader
# needs to go up, and jump to the same view on another branch -- the whole
# point of publishing per branch -- all on one line.
#
# emit_nav_css   stylesheet rules, inside the page's <style>
# emit_nav_js    renderNav(cfg) and initTheme(btn) into the page's <script>
# =============================================================================

emit_nav_css() {
cat <<'CSSEOF'
/* --- shared site navigation: one line ---------------------------------- */
.nav { display:flex; align-items:center; gap:10px; flex-wrap:nowrap;
       padding-bottom:12px; margin-bottom:14px; border-bottom:1px solid var(--border); }
.crumbs { display:flex; align-items:center; gap:9px; flex-wrap:nowrap; min-width:0; flex:1;
          white-space:nowrap; overflow:hidden;
          font-size:0.72rem; text-transform:uppercase; letter-spacing:0.07em; font-weight:700; }
.crumbs .home { display:inline-flex; align-items:center; color:var(--fg); text-decoration:none;
                border:none; font-size:0.95rem; letter-spacing:0.12em; flex:none; }
.crumbs .home:hover { text-decoration:underline; text-underline-offset:3px; }
.crumbs .home .eye { height:1.15em; margin-right:0.5em; }
.crumbs .here { color:var(--fg); }
.crumbs .car { color:var(--border); font-weight:400; }
/* The branch picker reads as a crumb until it is used. A native <select>, so
   keyboard, screen reader and phone behaviour come for free. */
.crumbs .bsel { position:relative; display:inline-flex; align-items:center; }
.crumbs .bsel select { appearance:none; -webkit-appearance:none; background:transparent;
    border:none; border-bottom:1px dashed var(--fg3); border-radius:0; color:var(--fg);
    font:inherit; letter-spacing:inherit; text-transform:inherit; padding:0 14px 1px 0;
    cursor:pointer; max-width:24ch; text-overflow:ellipsis; }
.crumbs .bsel::after { content:'\25BE'; position:absolute; right:0; color:var(--fg3);
    pointer-events:none; font-size:0.8em; }
.crumbs .bsel select:hover, .crumbs .bsel select:focus-visible { border-bottom-style:solid;
    border-color:var(--fg); outline:none; }
.crumbs .bsel option { color:initial; text-transform:none; }
.theme-btn { margin-left:auto; flex:none; display:inline-flex; align-items:center; justify-content:center;
    width:28px; height:28px; padding:0; background:transparent; color:var(--fg3);
    border:1px solid var(--border); cursor:pointer; }
.theme-btn:hover, .theme-btn:focus-visible { color:var(--fg); border-color:var(--fg); outline:none; }
.theme-btn svg { width:15px; height:15px; display:block; }
/* A phone keeps it to one line by dropping the page name: there is one page
   per branch, so it is the least informative part. */
@media (max-width:560px) {
  .crumbs .pg { display:none; }
  .crumbs .home { font-size:0.82rem; letter-spacing:0.08em; }
  .crumbs .bsel select { max-width:14ch; }
}
CSSEOF
}

emit_nav_js() {
cat <<'JSEOF'
// renderNav({el, branch, slug, page, branches, up, root})
//   page    : 'tests' -- the one page per branch; omit on the site root
//   up      : relative prefix to the BRANCH root (always '../' today)
//   root    : relative prefix to the SITE root (defaults to up + '../')
//   branches: [{slug, name}] -- every branch with a published page
//
// One line: the title (which is the way back to every branch), the branch as
// a picker that keeps you on the same page, the page, and the theme. It was
// three -- breadcrumbs, a "same view on" row, and a title row with a text
// theme button.
function renderNav(cfg) {
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  var up = cfg.up || '';
  var root = cfg.root != null ? cfg.root : up + '../';
  var PAGES = { tests: { label: 'Test results', dir: 'tests/' } };
  var page = PAGES[cfg.page];

  var html = '<a class="home" href="' + (root || './') + '" title="All branches">' +
             '<img class="eye" src="' + root + 'favicon.png" alt="" aria-hidden="true">' +
             'Argus Test Suite</a>';

  if (page) {
    var list = (cfg.branches || []).slice();
    if (!list.some(function (b) { return b.slug === cfg.slug; })) {
      list.unshift({ slug: cfg.slug, name: cfg.branch });
    }
    html += '<span class="car">/</span>';
    // A picker only when there is somewhere to go; one option would look
    // clickable and do nothing.
    if (list.length > 1) {
      html += '<span class="bsel"><select aria-label="Branch" id="' + cfg.el + '-branch">' +
        list.map(function (b) {
          return '<option value="' + esc(b.slug) + '"' + (b.slug === cfg.slug ? ' selected' : '') +
                 '>' + esc(b.name || b.slug) + '</option>';
        }).join('') + '</select></span>';
    } else {
      html += '<span class="here">' + esc(cfg.branch) + '</span>';
    }
    html += '<span class="car pg">/</span><span class="here pg">' + esc(page.label) + '</span>';
  }

  var el = document.getElementById(cfg.el);
  el.innerHTML = '<div class="crumbs">' + html + '</div>' +
    '<button class="theme-btn" id="' + cfg.el + '-theme" type="button"></button>';

  var sel = document.getElementById(cfg.el + '-branch');
  if (sel) {
    sel.addEventListener('change', function () {
      window.location.href = root + encodeURIComponent(sel.value) + '/' + page.dir;
    });
  }
  initTheme(document.getElementById(cfg.el + '-theme'));
}

// Follow the OS by default, let the reader override, remember it. Storage can
// throw in a private window, so every access is guarded. The icon shows the
// CURRENT mode and the tooltip names it and the next one, so a click is
// never a guess.
function initTheme(btn) {
  var ICON = {
    auto:  '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.2" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M8 1.8a6.2 6.2 0 0 1 0 12.4z" fill="currentColor"/></svg>',
    light: '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="3" fill="none" stroke="currentColor" stroke-width="1.4"/><g stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M8 1v1.6M8 13.4V15M1 8h1.6M13.4 8H15M3.05 3.05l1.13 1.13M11.82 11.82l1.13 1.13M3.05 12.95l1.13-1.13M11.82 4.18l1.13-1.13"/></g></svg>',
    dark:  '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M13.6 10.2A6 6 0 0 1 5.8 2.4a6 6 0 1 0 7.8 7.8z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>'
  };
  var NAME = { auto: 'Auto (follows your system)', light: 'Day', dark: 'Night' };
  var ORDER = ['auto', 'light', 'dark'];
  var html = document.documentElement;
  function read() { try { return localStorage.getItem('argus-theme') || 'auto'; } catch (e) { return 'auto'; } }
  function apply(mode) {
    if (mode === 'auto') html.removeAttribute('data-theme');
    else html.setAttribute('data-theme', mode);
    try { localStorage.setItem('argus-theme', mode); } catch (e) {}
    if (!btn) return;
    var next = ORDER[(ORDER.indexOf(mode) + 1) % ORDER.length];
    btn.innerHTML = ICON[mode];
    btn.title = 'Theme: ' + NAME[mode] + ' — click for ' + NAME[next];
    btn.setAttribute('aria-label', btn.title);
  }
  apply(read());
  if (btn) btn.addEventListener('click', function () {
    apply(ORDER[(ORDER.indexOf(read()) + 1) % ORDER.length]);
  });
}
JSEOF
}

# splice_nav <html-file>
# Replaces the __NAV_CSS__ / __NAV_JS__ placeholder lines with the real
# content. Done as a post-pass so the page heredocs stay quoted and literal --
# the same reason __UP__ is resolved after the fact rather than interpolated.
splice_nav() {
  local f="$1"
  local css js
  css=$(mktemp); js=$(mktemp)
  { emit_nav_css; emit_header_css; } > "$css"
  { emit_nav_js;  emit_header_js;  } > "$js"
  python3 - "$f" "$css" "$js" <<'PY'
import sys, pathlib
page, css, js = (pathlib.Path(p) for p in sys.argv[1:4])
t = page.read_text()
t = t.replace("__NAV_CSS__", css.read_text().rstrip("\n"))
t = t.replace("__NAV_JS__",  js.read_text().rstrip("\n"))
page.write_text(t)
PY
  rm -f "$css" "$js"
}

# =============================================================================
# Shared page HEADER.
#
# The board's header: branch, the suite commit, the argus ref with its version
# and commit, the liveness note, the date -- "what produced this page".
# =============================================================================

emit_header_css() {
cat <<'CSSEOF'
/* --- shared page header ------------------------------------------------ */
.phead { display:flex; align-items:center; gap:14px; flex-wrap:wrap; margin-bottom:8px; }
.phead h1 { margin:0; font-size:1.05rem; font-weight:700; color:var(--fg);
            text-transform:uppercase; letter-spacing:0.12em; display:flex; align-items:center; }
.pmeta { font-size:0.76rem; color:var(--fg3); display:flex; gap:10px; flex-wrap:wrap;
         align-items:center; margin-bottom:26px; }
.pmeta a { color:inherit; }
.pmeta .sep { color:var(--border); }
.chip { display:inline-block; padding:1px 7px; border:1px solid var(--border); font-size:0.66rem;
        font-weight:700; letter-spacing:0.04em; text-transform:uppercase; white-space:nowrap; cursor:help; }
.chip-warn { color:var(--warn-ink); background:var(--warn-bg); border-color:var(--warn); }
.chip-ok { color:var(--pass-ink); background:var(--pass-bg); border-color:var(--pass); }
CSSEOF
}

emit_header_js() {
cat <<'JSEOF'
// renderHeader({el, metaEl, title, up, branch, selfRepo, selfSha,
//               argusRepo, argusRef, argusSha, argusVersion, liveness,
//               date, runUrl, scope})
//
// One metadata line for every page. The label is what a human recognises and
// the href is the most specific immutable object; short SHAs are visible text,
// never tooltips, because a tooltip survives neither a screenshot nor a
// copy-paste.
function renderHeader(cfg) {
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  var up = cfg.up || '';
  var SRV = (cfg.runUrl || 'https://github.com').split('/').slice(0, 3).join('/');

  if (cfg.el) {
    document.getElementById(cfg.el).innerHTML =
      '<h1><img class="eye" src="' + up + 'favicon.png" alt="" aria-hidden="true">' +
      esc(cfg.title) + '</h1>';
  }

  function sha(repo, full) {
    if (!full || full === 'unknown') return '';
    return ' <a class="mono" href="' + SRV + '/' + repo + '/commit/' + esc(full) +
           '" title="exact commit -- this link cannot move">' +
           esc(String(full).slice(0, 7)) + '</a>';
  }

  var m = [];
  if (cfg.branch)   { m.push('branch <span class="mono">' + esc(cfg.branch) + '</span>'); }
  if (cfg.selfRepo) { m.push('suite' + (sha(cfg.selfRepo, cfg.selfSha) || ' <span class="mono">(sha unknown)</span>')); }
  if (cfg.argusRepo) {
    var onMain = (cfg.argusRef || 'main') === 'main';
    m.push((onMain && cfg.argusVersion
        ? '<a href="' + SRV + '/' + cfg.argusRepo + '/releases/tag/' + esc(cfg.argusVersion) +
          '">argus <span class="mono">v' + esc(cfg.argusVersion) + '</span></a>'
        : 'argus <span class="mono">' + esc(cfg.argusRef || 'main') + '</span>') +
      (sha(cfg.argusRepo, cfg.argusSha) || ''));
  }
  // Only when the Python that ran differs from the version already named.
  var L = cfg.liveness && cfg.liveness.summary;
  if (L) {
    var pins = (L.sdk_pins || []).join(', ');
    var shown = (cfg.argusRef || 'main') === 'main' ? (cfg.argusVersion || '') : '';
    if (L.sdk_live === false && pins && pins !== shown) {
      var tip = 'This run used the workflow files from ' + (L.ref || 'this ref') +
        ', but the argus Python package came from release ' + pins +
        ' — setup-argus is pinned inside those workflow files. Python behaviour is ' +
        'covered instead by the Runtime Environment tests (N1–N5), which check argus ' +
        'out at the ref and run the CLI directly.';
      var ver = (pins.indexOf(',') === -1)
        ? '<a class="mono" href="' + SRV + '/' + cfg.argusRepo + '/releases/tag/' + esc(pins) +
          '">v' + esc(pins) + '</a>'
        : '<span class="mono">' + esc(pins) + '</span>';
      m.push('<span class="chip chip-warn" title="' + esc(tip) +
             '">Python from ' + ver + ', not this ref</span>');
    } else if (L.sdk_live === true) {
      m.push('<span class="chip chip-ok" title="Workflow files and the Python package both come from this ref.">fully branch-live</span>');
    }
  }
  if (cfg.date)  { m.push(esc(cfg.date)); }
  if (cfg.scope) { m.push('scope <span class="mono">' + esc(cfg.scope) + '</span>'); }
  if (cfg.runUrl) { m.push('<a href="' + esc(cfg.runUrl) + '">view run &#8599;</a>'); }

  document.getElementById(cfg.metaEl).innerHTML = m.join('<span class="sep">&middot;</span>');
}
JSEOF
}
