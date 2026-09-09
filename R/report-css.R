# report design system: the inline stylesheet for report_weighting().
#
# One token layer (`:root`) drives every colour, so the palette is changed in one
# place and the dark and print variants only re-point tokens. Numeric table cells
# carry a `num` class (right-aligned, tabular figures) because a weighting report
# is read down its number columns. The per-step card takes a layout modifier
# (`is-compact` / `is-split` / `is-stacked`) chosen in report.R from how much the
# step actually has to say, so a rounding step does not get the same half-empty
# two-column grid as a calibration.

.report_css <- function() "<style>
:root{
  --ink:#14172a;--ink-2:#39405a;--mut:#666e87;--faint:#8b93a8;
  --line:#e4e7ef;--line-2:#ccd2e0;--line-3:#b6bdd0;
  --bg:#fff;--surf:#f8f9fc;--surf-2:#f1f3f9;--surf-3:#e9ecf4;
  --accent:#3b3478;--accent-2:#584f9e;--accent-soft:#eeecf8;--accent-line:#d5d0ec;
  --ok:#0e6b4e;--ok-bg:#e6f4ee;--ok-line:#bde0d1;
  --warn:#8a5200;--warn-bg:#fcf3e4;--warn-line:#f0dcb8;
  --bad:#98271b;--bad-bg:#fbeeeb;--bad-line:#f0cfc8;
  --ser:#4b5570;
  --r:10px;--r-s:6px;--r-l:14px;
  --shadow:0 1px 2px rgba(20,23,42,.05);
  --shadow-2:0 2px 10px rgba(20,23,42,.07);
  color-scheme:light;
}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){
  --ink:#e8eaf2;--ink-2:#c3c8d8;--mut:#98a0b6;--faint:#7b8299;
  --line:#2b3047;--line-2:#3a4058;--line-3:#4a5170;
  --bg:#12141f;--surf:#191c2b;--surf-2:#1f2333;--surf-3:#272c3f;
  --accent:#b0a6ee;--accent-2:#c6bef4;--accent-soft:#232741;--accent-line:#3b3f63;
  --ok:#63d3a8;--ok-bg:#152a24;--ok-line:#28483c;
  --warn:#e9b163;--warn-bg:#2a2115;--warn-line:#4a3a1f;
  --bad:#f0917f;--bad-bg:#2b1a17;--bad-line:#4d2c25;
  --ser:#a6afc8;
  --shadow:0 1px 2px rgba(0,0,0,.35);--shadow-2:0 2px 12px rgba(0,0,0,.4);
  color-scheme:dark;
}}
:root[data-theme=dark]{
  --ink:#e8eaf2;--ink-2:#c3c8d8;--mut:#98a0b6;--faint:#7b8299;
  --line:#2b3047;--line-2:#3a4058;--line-3:#4a5170;
  --bg:#12141f;--surf:#191c2b;--surf-2:#1f2333;--surf-3:#272c3f;
  --accent:#b0a6ee;--accent-2:#c6bef4;--accent-soft:#232741;--accent-line:#3b3f63;
  --ok:#63d3a8;--ok-bg:#152a24;--ok-line:#28483c;
  --warn:#e9b163;--warn-bg:#2a2115;--warn-line:#4a3a1f;
  --bad:#f0917f;--bad-bg:#2b1a17;--bad-line:#4d2c25;
  --ser:#a6afc8;
  --shadow:0 1px 2px rgba(0,0,0,.35);--shadow-2:0 2px 12px rgba(0,0,0,.4);
  color-scheme:dark;
}

*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
  font-size:15px;line-height:1.55;color:var(--ink);background:var(--bg);
  max-width:1060px;margin:0 auto;padding:34px 24px 64px;
  -webkit-font-smoothing:antialiased;font-variant-numeric:tabular-nums lining-nums}
.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}

/* ---- masthead ---------------------------------------------------------- */
.masthead{border-bottom:2px solid var(--ink);padding-bottom:14px;margin-bottom:6px}
h1{font-size:27px;line-height:1.2;margin:0 0 6px;letter-spacing:-.011em;font-weight:660}
h1 .wf-mark{color:var(--accent)}
.subtitle{color:var(--mut);font-size:14px;margin:0;display:flex;flex-wrap:wrap;gap:6px 14px;align-items:baseline}
.prov{color:var(--faint);font-size:12.5px;margin:8px 0 0;letter-spacing:.005em}

/* ---- section headings -------------------------------------------------- */
h2{font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.1em;
  color:var(--accent);margin:44px 0 14px;padding-bottom:8px;border-bottom:1px solid var(--line-2)}
h2:first-of-type{margin-top:34px}
h3.card-t,h4{margin:0 0 9px;font-size:11px;font-weight:700;text-transform:uppercase;
  letter-spacing:.075em;color:var(--mut)}
.hint{color:var(--mut);font-size:13px;margin:6px 0 10px;max-width:74ch}
.muted{color:var(--mut);font-size:13px}
.note{color:var(--ink-2);font-size:13px;line-height:1.6;margin:8px 0 0;max-width:80ch;
  padding-left:11px;border-left:2px solid var(--line-2)}
p{max-width:80ch}

/* ---- cards ------------------------------------------------------------- */
.exec,.meta,.done,.ddc{background:var(--surf);border:1px solid var(--line);
  border-radius:var(--r);padding:16px 18px;margin:14px 0}
.meta{background:var(--bg)}
.exec p{margin:0;font-size:14.5px;line-height:1.62;color:var(--ink);max-width:72ch}
.exec p+p{margin-top:9px}
.exec p.interp{margin-top:12px;padding-top:11px;border-top:1px solid var(--line);
  font-size:14px;color:var(--ink-2)}
.exec p.interp strong{color:var(--ink)}
/* the summary and the status checklist say different things about the same run,
   so they sit side by side instead of stacking into two wide, half-empty bands */
.sumgrid{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(0,1fr);gap:14px;align-items:start}
.sumgrid>.exec{margin:14px 0 0}
@media(max-width:860px){.sumgrid{grid-template-columns:1fr}}
.exec+.exec{margin-top:10px}
.feature{border:1px solid var(--accent-line);border-left:3px solid var(--accent);
  background:var(--accent-soft);box-shadow:none}
.feature h3.card-t,.feature h4{color:var(--accent)}
.feature-soft{border-color:var(--line-2);background:var(--bg);box-shadow:var(--shadow)}

/* ---- headline metrics -------------------------------------------------- */
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(132px,1fr));gap:1px;
  margin:20px 0 4px;background:var(--line);border:1px solid var(--line);border-radius:var(--r);overflow:hidden}
.metric{background:var(--surf);padding:14px 16px}
.mv{font-size:23px;font-weight:640;letter-spacing:-.015em;line-height:1.15;color:var(--ink)}
.ml{color:var(--mut);font-size:11px;margin-top:3px;text-transform:uppercase;letter-spacing:.06em}
.ddc .ddc-facts{display:flex;gap:10px;flex-wrap:wrap;margin:0 0 12px}
.ddc .ddc-facts .metric{background:var(--bg);border:1px solid var(--line);border-radius:var(--r-s);min-width:120px}
.ddc .ddc-lead{font-size:15px;font-weight:600;color:var(--ink);margin:2px 0 12px;line-height:1.5}
.ddc td.neff{color:var(--warn);font-weight:700;text-align:right}

/* ---- tables ------------------------------------------------------------ */
.tw{overflow-x:auto;margin:6px 0;-webkit-overflow-scrolling:touch}
table{border-collapse:collapse;width:100%;font-size:13px;margin:6px 0}
th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--mut);font-weight:650;font-size:10.5px;text-transform:uppercase;letter-spacing:.055em;
  border-bottom:1px solid var(--line-2);white-space:nowrap}
thead th{position:relative}
tbody tr:last-child td{border-bottom:0}
tbody tr:hover{background:var(--surf-2)}
td.numc,th.numc,td.r,th.r{text-align:right;font-variant-numeric:tabular-nums}
td.numc{white-space:nowrap}
.params td.k,.meta td.k{color:var(--mut);width:38%;font-weight:600}
.params td:not(.k),.meta td:not(.k){font-variant-numeric:tabular-nums}
.racct td.k{font-weight:650;color:var(--ink)}
/* the per-stage and per-domain tables are one label column followed by five
   number columns: align them all right, so magnitudes line up down the page */
.stagetbl th:not(:first-child),.stagetbl td:not(:first-child){text-align:right}
.stagetbl td:not(:first-child){font-variant-numeric:tabular-nums;white-space:nowrap}
.stagetbl th{white-space:normal}
.stagetbl th.lbl,.stagetbl td.lbl{text-align:left}
.stagetbl th:first-child,.stagetbl td:first-child{white-space:normal;min-width:150px}
.total-row td{font-weight:650;border-top:2px solid var(--line-2);background:var(--surf-2)}
caption{caption-side:top;text-align:left}

/* ---- inline value chips ------------------------------------------------ */
.cell-ok{background:var(--ok-bg);color:var(--ok);padding:2px 7px;border-radius:var(--r-s);
  font-weight:600;display:inline-block;font-variant-numeric:tabular-nums}
.cell-warn{background:var(--warn-bg);color:var(--warn);padding:2px 7px;border-radius:var(--r-s);
  font-weight:600;display:inline-block;font-variant-numeric:tabular-nums}
code{background:var(--surf-2);color:var(--ink-2);padding:1.5px 6px;border-radius:4px;
  font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12.5px}
.chips{margin-top:8px;display:flex;flex-wrap:wrap;gap:5px}
.chip{background:var(--accent-soft);color:var(--accent);border:1px solid var(--accent-line);
  border-radius:999px;padding:1.5px 10px;font-size:11px;
  font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}

/* ---- status / attention ------------------------------------------------ */
.chk{list-style:none;padding-left:0;margin:8px 0 0;font-size:14px}
.chk li{margin:0;padding:7px 0 7px 26px;position:relative;border-top:1px solid var(--line);line-height:1.5}
.chk li:first-child{border-top:0;padding-top:2px}
.chk .ok,.chk .no{position:absolute;left:0;top:7px;font-weight:700}
.chk li:first-child .ok,.chk li:first-child .no{top:2px}
.chk .ok{color:var(--ok)}.chk .no{color:var(--warn)}
.attention{border-left:3px solid var(--warn);background:var(--warn-bg);border-color:var(--warn-line)}
.attention h3.card-t,.attention h4{color:var(--warn);display:flex;align-items:center;gap:8px}
.att-n{background:var(--warn);color:var(--warn-bg);border-radius:999px;min-width:19px;height:19px;
  display:inline-flex;align-items:center;justify-content:center;padding:0 6px;font-size:11px;
  font-weight:700;letter-spacing:0}
.att-step a{color:inherit;text-decoration:none;border-bottom:1px solid currentColor;opacity:.9}
.att-step a:hover{opacity:1}
.att-group{margin:10px 0 0;padding-top:10px;border-top:1px solid var(--warn-line)}
.att-group:first-of-type{border-top:0;padding-top:2px;margin-top:6px}
.att-step{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.055em;
  color:var(--warn);margin:0 0 4px}
.att-group ul{margin:0;padding-left:17px;font-size:13.5px;line-height:1.6;color:var(--ink)}
.att-group li{margin:3px 0}
.alert{margin:10px 0 0;padding:10px 13px;border-left:3px solid var(--warn);
  background:var(--warn-bg);border-radius:0 var(--r-s) var(--r-s) 0;font-size:13px;color:var(--ink)}
.alert strong{color:var(--warn);display:block;margin-bottom:5px;font-size:11px;
  text-transform:uppercase;letter-spacing:.055em}
.alert ul{margin:0;padding-left:17px}.alert li{margin:3px 0;line-height:1.55}
.alert p{margin:0}

/* ---- narrative --------------------------------------------------------- */
.methodological-note{margin:2px 0 14px;padding:12px 16px;background:var(--surf);
  border-left:3px solid var(--accent-line);border-radius:0 var(--r-s) var(--r-s) 0;
  font-size:14px;line-height:1.62;color:var(--ink-2);max-width:none}

/* ---- pipeline diagram -------------------------------------------------- */
/* the cascade reads top-down, so it stays a column; the space beside it is
   filled by the variables panel instead of being left blank. */
.pipe{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:26px;
  align-items:start;margin-top:6px}
@media(max-width:760px){.pipe{grid-template-columns:1fr}}
.flow{display:flex;flex-direction:column;align-items:stretch;margin:0}
.varbox{background:var(--surf);border:1px solid var(--line);border-radius:var(--r);
  padding:15px 17px;position:sticky;top:56px}
.node{border:1px solid var(--line);border-radius:var(--r);padding:11px 14px;background:var(--bg);
  box-shadow:var(--shadow)}
.node-end{background:var(--surf);border-style:dashed;box-shadow:none}
.nl{font-weight:620;font-size:14px;display:flex;align-items:center;gap:9px;line-height:1.35}
.nv{margin-top:4px}
.arrow{text-align:center;color:var(--line-3);font-size:17px;line-height:1;margin:5px 0;
  display:flex;align-items:center;justify-content:center;gap:8px}
.arrow .fn{font-size:11px;color:var(--mut);font-family:ui-monospace,Menlo,monospace;
  font-variant-numeric:tabular-nums}
.num{display:inline-flex;width:22px;height:22px;flex:0 0 22px;align-items:center;
  justify-content:center;background:var(--accent);color:var(--bg);border-radius:50%;
  font-size:12px;font-weight:650}
:root[data-theme=dark] .num,:root:not([data-theme=light]) .num{color:#12141f}
@media (prefers-color-scheme:light){:root:not([data-theme=dark]) .num{color:#fff}}

/* ---- step cards -------------------------------------------------------- */
.step{border:1px solid var(--line);border-radius:var(--r-l);padding:18px 20px;margin:16px 0;
  box-shadow:var(--shadow);background:var(--bg);scroll-margin-top:64px}
.step-h{font-weight:650;font-size:16px;display:flex;align-items:center;gap:11px;
  margin-bottom:12px;letter-spacing:-.005em}
.step-h .step-kind{margin-left:auto;font-size:10.5px;font-weight:650;text-transform:uppercase;
  letter-spacing:.06em;color:var(--mut);background:var(--surf-2);border:1px solid var(--line);
  border-radius:999px;padding:2px 10px;white-space:nowrap}
.cols{display:grid;grid-template-columns:minmax(210px,.72fr) minmax(0,1.6fr);gap:26px;align-items:start}
.col-h{margin:0 0 9px;font-size:11px;font-weight:700;text-transform:uppercase;
  letter-spacing:.075em;color:var(--mut)}

/* stacked: the step has a lot to say -- parameters collapse into a compact
   spec strip across the top and every diagnostic gets the full width. */
.step.is-stacked .cols,.step.is-compact .cols{grid-template-columns:1fr;gap:14px}
.step.is-stacked .spec .params,.step.is-compact .spec .params{display:block;margin:0}
.step.is-stacked .spec .params tbody,.step.is-compact .spec .params tbody{
  display:grid;grid-template-columns:repeat(auto-fill,minmax(168px,1fr));gap:0 20px}
.step.is-stacked .spec .params tr,.step.is-compact .spec .params tr{
  display:block;border-bottom:1px solid var(--line);padding:6px 0}
.step.is-stacked .spec .params tr:hover,.step.is-compact .spec .params tr:hover{background:none}
.step.is-stacked .spec .params td,.step.is-compact .spec .params td{
  display:block;border:0;padding:0;width:auto}
.step.is-stacked .spec .params td.k,.step.is-compact .spec .params td.k{
  font-size:10px;text-transform:uppercase;letter-spacing:.055em;color:var(--faint);
  font-weight:650;margin-bottom:1px}
.step.is-stacked .spec .params td:not(.k),.step.is-compact .spec .params td:not(.k){
  font-size:13px;color:var(--ink);word-break:break-word}
.step.is-compact{padding:14px 18px}
.step.is-compact .step-h{margin-bottom:8px;font-size:15px}

/* the deff delta strip that closes every step */
.delta{display:flex;flex-wrap:wrap;gap:6px 20px;margin:12px 0 0;padding:9px 12px;max-width:none;
  background:var(--surf);border:1px solid var(--line);border-radius:var(--r-s);
  font-size:12.5px;color:var(--mut)}
.delta b{color:var(--ink);font-weight:640;font-variant-numeric:tabular-nums}
.delta .dk{text-transform:uppercase;letter-spacing:.05em;font-size:10.5px;font-weight:650}
.ri{margin-top:16px;border-top:1px solid var(--line);padding-top:14px}
.ri-val{font-size:15px;margin:8px 0}
.trim-h{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;
  margin:16px 0 6px;color:var(--mut)}

/* ---- charts ------------------------------------------------------------ */
/* Every mark takes its colour from a token, so the inline SVGs follow the
   report's scheme (dark mode, print) instead of freezing a light palette. */
svg .wf-grid{stroke:var(--line)}
svg .wf-axis{stroke:var(--line-2);stroke-width:.8}
svg .wf-tick{stroke:var(--line-3)}
svg .wf-tk{fill:var(--mut);font-size:10px}
svg .wf-al{fill:var(--faint);font-size:10.5px}
svg .wf-mark{fill:var(--accent)}
svg .wf-line{stroke:var(--accent);fill:none}
svg .wf-area{fill:var(--accent);fill-opacity:.07;stroke:none}
svg .wf-bar{fill:var(--accent-2);fill-opacity:.55}
svg .wf-stem{stroke:var(--accent-2);stroke-opacity:.55}
svg .wf-pt{fill:var(--accent-2);fill-opacity:.28}
svg .wf-ref{stroke:var(--faint);stroke-opacity:.8}
svg .wf-up,.sw-up{fill:var(--warn);color:var(--warn)}
svg .wf-dn,.sw-dn{fill:var(--ok);color:var(--ok)}
svg .wf-resp{fill:#2a78d6}svg .wf-nonresp{fill:var(--warn)}
svg .wf-chosen{stroke:var(--bad);fill:var(--bad)}
svg text{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
  font-variant-numeric:tabular-nums}
/* ---- panel / longitudinal ---------------------------------------------- */
/* categorical hues for the Sankey and the wave bars, as classes rather than
   literals, so the panel visuals follow the scheme like every other chart */
:root{--heat:37,99,235;--c1:#2f6fd0;--c2:#c2792a;--c3:#3f8f5c;--c4:#8f5bb8;--c5:#b8524f;--c6:#4e7f74}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){
  --heat:129,164,255;--c1:#7ba6ea;--c2:#e0a869;--c3:#74c495;--c4:#b894dd;--c5:#e08b87;--c6:#7fb3a6}}
:root[data-theme=dark]{--heat:129,164,255;--c1:#7ba6ea;--c2:#e0a869;--c3:#74c495;
  --c4:#b894dd;--c5:#e08b87;--c6:#7fb3a6}
svg .p1,.sw-p1{fill:var(--c1)}svg .p2,.sw-p2{fill:var(--c2)}svg .p3,.sw-p3{fill:var(--c3)}
svg .p4{fill:var(--c4)}svg .p5{fill:var(--c5)}svg .p6{fill:var(--c6)}
svg .p-node{fill:var(--mut)}
svg .p-lab{fill:var(--ink-2);font-size:11px}
svg .p-val{fill:var(--mut);font-size:10.5px;font-variant-numeric:tabular-nums}
svg .p-track{fill:var(--surf-3)}
/* heat matrix: one alpha ramp over a token hue, legible in both schemes */
.heat td.h{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.heat th{white-space:nowrap}
.heat th.rh{text-align:left;color:var(--ink);font-size:11.5px;text-transform:none;letter-spacing:0;width:1%;white-space:nowrap;padding-right:18px}
.heat td.h span.se{color:var(--mut);font-size:11px}
/* a card's headline numbers, as a strip across the top instead of a column of
   full-width tiles squeezed into half the card */
.strip{display:grid;grid-template-columns:repeat(auto-fit,minmax(128px,1fr));gap:1px;
  background:var(--line);border:1px solid var(--line);border-radius:var(--r-s);
  overflow:hidden;margin:0 0 14px}
.strip .metric{background:var(--bg);padding:11px 13px}
.strip .mv{font-size:19px}
.feature .strip{background:var(--accent-line)}
.feature .strip .metric{background:var(--bg)}
.panel-body{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:24px;align-items:start}
.panel-body.wide{grid-template-columns:1fr}
@media(max-width:820px){.panel-body{grid-template-columns:1fr}}
/* a 3x3 matrix or a 2-bar chart stretched across the full page reads as empty
   space, not as data: cap them at a width the content actually fills */
.panel-body .heat{max-width:560px}
.panel-body figure.chartblk{max-width:600px}
.panel-body>div{min-width:0}
/* the CSV button is a grid/flex item here, so it would stretch to the column */
.panel-body .dlcsv,.strip+.viz-h+.dlcsv,.dlcsv{justify-self:start;align-self:start;width:-moz-fit-content;width:fit-content}

/* estimates section: one block per estimand inside a single card, separated by a
   rule rather than by another nested box (a card inside a card inside a card is
   how the panel report used to look) */
.estblk+.estblk{padding-top:18px;border-top:1px solid var(--line)}
/* card titles, metric labels and table headers are uppercased; a Greek letter
   put through text-transform comes out as its capital, so rho reads as a P and
   alpha as an A. Opt those glyphs out. */
.gk{text-transform:none}
h4.est-h{margin:0 0 9px;font-size:14px;font-weight:650;letter-spacing:-.01em;
  color:var(--ink);text-transform:none;display:flex;align-items:baseline;gap:9px;flex-wrap:wrap}
.est-kind{font-size:10.5px;font-weight:600;text-transform:uppercase;letter-spacing:.06em;
  color:var(--accent);background:var(--accent-soft);border:1px solid var(--accent-line);
  border-radius:999px;padding:1px 8px}
.est-viz{margin-top:12px}
.creblk figure.chartblk{margin-top:16px;max-width:600px}
.est-viz figure.chartblk{max-width:660px}
/* the row whose interval clears zero is the one the reader is looking for */
table.est tbody tr.sig td{font-weight:600}
table.est tbody tr.sig td:first-child{box-shadow:inset 2px 0 0 var(--accent)}
svg .wf-ci{stroke:var(--accent-2);stroke-width:1.6;stroke-opacity:.75}
svg .wf-rl{fill:var(--ink-2);font-size:11px}
svg .wf-dot{fill:var(--accent)}
svg .wf-dot.ns{fill:var(--bg);stroke:var(--accent-2);stroke-width:1.6;stroke-opacity:.8}

/* two-phase variance split bar */
.vsplit{display:flex;height:12px;border-radius:999px;overflow:hidden;
  border:1px solid var(--accent-line);margin:4px 0 3px;max-width:420px}
.vsplit .v1{background:var(--accent-2);opacity:.42}
.vsplit .v2{background:var(--accent)}
.vsplit-leg{display:flex;gap:16px;font-size:11px;color:var(--mut);margin-bottom:4px}
.vsplit-leg span{display:inline-flex;align-items:center;gap:5px}
.sw{width:9px;height:9px;border-radius:2px;display:inline-block}
.sw1{background:var(--accent-2);opacity:.42}.sw2{background:var(--accent)}
tr.barrow td{border-bottom:0;padding-top:0}
tr.barrow:hover{background:none}
.note-warn{color:var(--warn);border-left-color:var(--warn-line)}
figure.chartblk{margin:0}
figure.chartblk+figure.chartblk{margin-top:16px}
.viz{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:20px;margin-top:10px}
.viz svg,.chart1 svg,.wdhist svg{max-width:100%;height:auto;display:block}
.viz-h{margin:0 0 4px;font-size:11px;font-weight:700;text-transform:uppercase;
  letter-spacing:.07em;color:var(--mut);text-align:left}
h4.viz-h{margin-top:16px}
.wdhist{margin:12px 0 0;max-width:560px}
.chart1{margin-top:10px;max-width:460px}
.pgrid{display:grid;grid-template-columns:minmax(0,440px) minmax(0,1fr);gap:22px;
  align-items:start;margin-top:10px}
.pgrid .chart1{margin-top:0}
.pgrid-note{font-size:13px;line-height:1.6}

/* ---- nav / toolbar ----------------------------------------------------- */
.toolbar{display:flex;gap:8px;margin:14px 0 0;flex-wrap:wrap}
.wfbtn{cursor:pointer;font:inherit;font-size:12.5px;border:1px solid var(--line-2);
  background:var(--bg);color:var(--ink-2);border-radius:var(--r-s);padding:6px 13px;
  display:inline-flex;align-items:center;gap:6px;transition:background .12s,border-color .12s}
.wfbtn:hover{background:var(--surf-2);border-color:var(--line-3)}
.toc{background:color-mix(in srgb,var(--bg) 88%,transparent);
  -webkit-backdrop-filter:saturate(180%) blur(10px);backdrop-filter:saturate(180%) blur(10px);
  border-bottom:1px solid var(--line);padding:10px 0;margin:18px 0 0;font-size:13px;
  position:sticky;top:0;z-index:20;display:flex;flex-wrap:wrap;gap:4px 12px;align-items:baseline}
@supports not (backdrop-filter:blur(1px)){.toc{background:var(--bg)}}
.toc strong{color:var(--mut);font-size:10.5px;text-transform:uppercase;letter-spacing:.07em;font-weight:700}
.toc a{color:var(--ink-2);text-decoration:none;border-bottom:1px solid transparent;padding-bottom:1px}
.toc a:hover{color:var(--accent);border-bottom-color:var(--accent-line)}
.tsteps{display:inline-flex;gap:2px;flex-wrap:wrap}
.tsteps a{display:inline-flex;min-width:21px;height:21px;align-items:center;justify-content:center;
  color:var(--mut);border:1px solid var(--line);border-radius:var(--r-s);font-size:11px;
  font-variant-numeric:tabular-nums;border-bottom-color:var(--line)}
.tsteps a:hover{color:var(--accent);border-color:var(--accent-line);background:var(--accent-soft)}
details.steps>summary{cursor:pointer;font-size:12.5px;color:var(--mut);margin:8px 0 4px;
  list-style:none;display:inline-flex;align-items:center;gap:7px;
  border:1px solid var(--line);border-radius:var(--r-s);padding:4px 11px}
details.steps>summary:hover{background:var(--surf-2);color:var(--ink-2)}
details.steps>summary::-webkit-details-marker{display:none}
details.steps>summary::before{content:'\\25BE';font-size:9px;color:var(--faint)}
details.steps:not([open])>summary::before{content:'\\25B8'}
.dlcsv{cursor:pointer;font:inherit;border:1px solid var(--line);background:var(--bg);
  color:var(--mut);border-radius:var(--r-s);padding:2px 9px;font-size:10.5px;
  margin:0 0 4px;display:inline-flex;align-items:center;gap:4px;letter-spacing:.04em;
  text-transform:uppercase;font-weight:650;opacity:.75;transition:opacity .12s}
.dlcsv:hover{opacity:1;background:var(--surf-2);color:var(--accent)}

/* ---- closing ----------------------------------------------------------- */
.done{margin-top:26px;background:var(--surf);font-size:13.5px;color:var(--ink);
  display:flex;flex-wrap:wrap;gap:4px 10px;align-items:baseline}
.foot{color:var(--mut);font-size:12px;line-height:1.65;margin-top:32px;
  border-top:1px solid var(--line);padding-top:14px;max-width:none}

/* ---- responsive -------------------------------------------------------- */
@media(max-width:760px){
  body{padding:22px 16px 48px;font-size:14.5px}
  h1{font-size:23px}
  .cols,.pgrid{grid-template-columns:1fr!important;gap:16px}
  .step{padding:15px 15px;border-radius:var(--r)}
  .flow{grid-template-columns:1fr}
  .toc{font-size:12.5px}
}

/* ---- print ------------------------------------------------------------- */
@media print{
  :root{--bg:#fff;--surf:#fafafa;--surf-2:#f4f4f6;--ink:#111;--ink-2:#333;--mut:#555;
    --faint:#777;--line:#ddd;--line-2:#bbb;--accent:#2f2a63;--accent-soft:#f4f2fb;
    --shadow:none;--shadow-2:none;color-scheme:light}
  body{max-width:none;margin:0;padding:0;font-size:10.5pt;background:#fff}
  @page{margin:16mm 14mm}
  /* Only small, self-contained blocks are kept whole. Forcing break-inside:avoid
     on the big cards and tables pushed each of them onto a fresh page and left
     half of every sheet blank; those are allowed to flow and split. */
  .metric,.node,.alert,.att-group,figure,.delta,tr,.vsplit
    {break-inside:avoid;page-break-inside:avoid}
  thead{display:table-header-group}       /* repeat headers on a split table */
  tfoot{display:table-footer-group}
  .step{break-inside:auto}
  h3.card-t,.viz-h{break-after:avoid;page-break-after:avoid}
  .step-h{break-after:avoid;page-break-after:avoid}
  h1,h2{break-after:avoid;page-break-after:avoid}
  h2{margin-top:22px}
  .step{box-shadow:none;border:1px solid #ccc}
  .feature,.feature-soft{box-shadow:none}
  .toc,.noprint,.toolbar,.dlcsv{display:none!important}
  details.steps>summary{display:none}
  details.steps[open]{display:block}
  .tw{overflow:visible}
  a{color:inherit;text-decoration:none}
  .done{margin-top:16px}
}
@media(forced-colors:active){
  .metric,.step,.node,.exec,.meta{border:1px solid CanvasText}
  .cell-ok,.cell-warn,.chip{border:1px solid CanvasText}
}
</style>"
