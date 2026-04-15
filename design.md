# Dashboard Design System

A reusable design language for internal analytics dashboards. Dark-first, solid-card aesthetic with a single accent color and subtle micro-animations.

---

## 1. Color Palette

### Accent
```
--accent:       #d94f4f   (primary red — buttons, highlights, chips, chart bars)
--accent-dim:   rgba(217, 79, 79, 0.18)
--accent-focus: rgba(217, 79, 79, 0.15)  (focus ring)
```
Swap `#d94f4f` for any hue to re-skin the entire dashboard. All accent uses reference this variable.

### Dark Mode (active)
```
Page background:    #0e0e14
Card background:    #18181f
Card (elevated):    #1e1e28
Input background:   #16161e
Button background:  #1c1c26
Table header:       #13131a
```

### Text scale (dark mode)
```
Full:   rgba(255,255,255,1.00)
80%:    rgba(255,255,255,0.80)
75%:    rgba(255,255,255,0.75)
60%:    rgba(255,255,255,0.60)
50%:    rgba(255,255,255,0.50)   ← labels, secondary text
40%:    rgba(255,255,255,0.40)   ← chart axis ticks
25%:    rgba(255,255,255,0.25)   ← placeholder text
```

### Chart color palette (20 colors, cycle with `i % PALETTE.length`)
```js
const PALETTE = [
  '#d94f4f','#e89468','#f0c080','#a3d977','#4fc4d9','#4f7fd9','#9b6fd9',
  '#d96fb0','#d9a44f','#6fd9a4','#d9d94f','#6fa4d9','#d96f6f','#7fd96f',
  '#d94fb0','#4fd9d9','#d9874f','#874fd9','#4fd987','#d9cf4f',
];
```
Primary bar/line color when a single series: `#d94f4f`.

---

## 2. Typography

```
Font stack:  -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', system-ui, sans-serif
```

| Role | Class / Size |
|---|---|
| App title | `text-xl font-bold` |
| Panel section title | `text-xs font-semibold uppercase tracking-widest text-white/50` |
| Chart sub-title | `10px font-semibold uppercase tracking-widest text-white/40` |
| Table header | `text-[10px] font-semibold uppercase tracking-widest` |
| Body / row text | `text-sm` |
| Chip / badge label | `text-xs` |
| Tooltip text | `11–12px` |
| Axis ticks | `fontSize: 10, fill: rgba(255,255,255,0.4)` |

---

## 3. Cards / Panels (`.glass`)

Every content section is a `.glass` card:

```css
.glass {
  background: var(--glass-bg);          /* #18181f in dark */
  border: 1px solid var(--glass-border); /* rgba(255,255,255,0.07) in dark */
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,0.04),  /* top highlight */
    0 4px 24px rgba(0,0,0,0.50);
  border-radius: 1.25rem;               /* 20px */
}
```

Panel anatomy:
```jsx
<div className="glass flex flex-col overflow-hidden">
  <div className="px-5 py-3 border-b border-white/[0.07] flex-shrink-0 flex items-center gap-2">
    <h2 className="text-xs font-semibold text-white/50 uppercase tracking-widest">{title}</h2>
    {/* optional info tooltip */}
  </div>
  <div className="flex-1 overflow-auto p-4 min-h-0">
    {children}
  </div>
</div>
```

---

## 4. Layout

### Page structure
```
fixed .glass-bg           ← full-screen dark background layer
relative z-10 flex flex-col min-h-screen
  ├── <header>  sticky top-0 z-50
  ├── filter bar  sticky top-[49px] z-40  height: 72px (fixed, never shifts)
  └── <main>  px-4 py-6 max-w-screen-2xl mx-auto flex flex-col gap-4
```

### Grid
- KPI cards: `grid grid-cols-2 sm:grid-cols-4 gap-3`
- Chart sections: full-width panels stacked vertically with `gap-4`
- Multi-chart panels (e.g. 3 bar charts): `flex gap-6 items-start`

### Sticky filter bar
```jsx
<div
  className="sticky top-[49px] z-40 flex-shrink-0"
  style={{ height: '72px', background: 'var(--filters-bg)', borderBottom: '1px solid var(--filters-border)', willChange: 'transform' }}
>
```
`willChange: transform` prevents the bar from shifting vertically on scroll. Always set an explicit pixel height — never let it auto-size.

---

## 5. Filter Bar

### Pill shape
Each filter is an equal-width pill:
```
flex-1 min-w-0 glass rounded-2xl px-4 pt-2 pb-2.5 flex flex-col gap-0.5 h-[52px] justify-center
```

### Multi-select dropdown
- Opens below the pill with `position: absolute, z-index: 200`
- Has a search input that auto-focuses on open
- Checkbox list with themed hover: `.dropdown-opt:hover { background: var(--dropdown-hover); }`
- "Clear selection" button at the bottom
- Closes on click-outside via `useRef` + `mousedown` listener

### Active filter chips (in header)
```jsx
<span style={{
  background: 'rgba(217,79,79,0.12)',
  border: '1px solid rgba(217,79,79,0.25)',
  color: 'rgba(255,255,255,0.70)',
}} className="inline-flex items-center gap-1 text-xs px-2.5 py-1 rounded-full">
  <span style={{ color: 'rgba(255,255,255,0.38)', fontSize: '10px' }}>{label}:</span>
  {value}
  <button onClick={...}>×</button>
</span>
```
The chip row uses `overflow-x: auto` with a 3px accent-colored scrollbar:
```css
.chips-scroll::-webkit-scrollbar { height: 3px; }
.chips-scroll::-webkit-scrollbar-thumb { background: rgba(217,79,79,0.35); border-radius: 999px; }
```

---

## 6. KPI Cards

- Animated "slot machine" digit effect on number change
- Each digit is a column of 0–9 stacked vertically, translated to the correct position
- Transition: `transform 0.55s cubic-bezier(0.25, 0.46, 0.45, 0.94)` with staggered delay (rightmost digit = 0 delay, leftmost = longest)
- `format` prop: `"number"` | `"percent"` | `"decimal"`
- Change indicator: green ▲ / red ▼ with `+X%` / `-X%` vs prior period
- When loading: render a skeleton block instead of the number

---

## 7. Tables

### Header
```css
.table-head-row th {
  background: var(--table-head-bg);       /* #13131a */
  border-bottom: 1px solid var(--table-head-border);
  position: sticky; top: 0;
}
```
Sortable columns show `↑` / `↓` / `↕` indicators.

### Row animations
Rows animate in on load:
```js
style={{
  animation: 'row-in 0.3s ease-out both',
  animationDelay: `${Math.min(i * 0.025, 0.35)}s`
}}

@keyframes row-in {
  from { opacity: 0; transform: translateY(10px); }
  to   { opacity: 1; transform: translateY(0); }
}
```
Increment an `animKey` state when loading completes to re-trigger the animation on fresh data.

### Winner row highlight
```css
.table-winner-row { background: rgba(217, 79, 79, 0.08) !important; }
```

---

## 8. Charts (Recharts)

### Shared axis style
```js
const TICK = { fill: 'rgba(255,255,255,0.4)', fontSize: 10 };
const GRID = 'rgba(255,255,255,0.06)';
// XAxis / YAxis: axisLine={false} tickLine={false}
// CartesianGrid: strokeDasharray="3 3" vertical={false}
```

### Tooltip
```jsx
<div style={{
  background: 'rgba(20,15,40,0.92)',
  backdropFilter: 'blur(16px)',
  border: '1px solid rgba(255,255,255,0.12)',
  borderRadius: 10,
  padding: '10px 14px',
}}>
```

### Bar charts (horizontal)
- `layout="vertical"`, `radius={[0, 4, 4, 0]}` on `<Bar>`
- `animationDuration={700} animationEasing="ease-out"`
- Stagger multiple charts with `animationBegin`: 0, 150, 300ms
- `<LabelList position="right" style={{ fill: 'rgba(255,255,255,0.6)', fontSize: 11 }} />`

### Line charts
- `dot={false}`, `strokeWidth={1.5}`, `connectNulls`
- Y-axis formatter: `v >= 1_000_000 ? Xm : v >= 1000 ? XK : v`

### Removing focus outlines on charts
```css
.recharts-wrapper,
.recharts-wrapper svg,
.recharts-wrapper *:focus { outline: none !important; }
```

### Custom right-side legend (line charts)
Wrap `<ResponsiveContainer>` in a flex container and render the legend as a sibling div:
```jsx
<div style={{ display: 'flex', width: '100%', height: '100%' }}>
  <div style={{ flex: 1, minWidth: 0, height: '100%' }}>
    <ResponsiveContainer width="100%" height="100%">
      {/* chart */}
    </ResponsiveContainer>
  </div>
  <div style={{ width: 160, flexShrink: 0, display: 'flex', flexDirection: 'column',
                justifyContent: 'center', paddingLeft: 12, overflowY: 'auto' }}>
    {items.map((item, i) => (
      <div key={item} style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 5 }}>
        <span style={{ width: 10, height: 10, borderRadius: 2, background: PALETTE[i], flexShrink: 0 }} />
        <span style={{ color: 'rgba(255,255,255,0.5)', fontSize: 11, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item}</span>
      </div>
    ))}
  </div>
</div>
```
Do **not** pass `width="calc(...)"` to `<ResponsiveContainer>` — it only accepts numbers or `"100%"`.

---

## 9. Skeleton Loading

Every section should match its loaded height during loading to prevent layout shift.

```css
@keyframes skeleton-pulse {
  0%, 100% { opacity: 0.35; }
  50%       { opacity: 0.65; }
}
.skeleton {
  background: rgba(255,255,255,0.10);
  border-radius: 6px;
  animation: skeleton-pulse 1.6s ease-in-out infinite;
}
```

Pattern: render the same structural layout (same number of rows/bars/columns) but replace content with `.skeleton` divs of matching dimensions.

---

## 10. Scrollbars

```css
/* Global */
::-webkit-scrollbar        { width: 6px; height: 6px; }
::-webkit-scrollbar-track  { background: transparent; }
::-webkit-scrollbar-thumb  { background: var(--scrollbar-thumb); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--scrollbar-hover); }

/* Dark:  thumb = rgba(255,255,255,0.12), hover = rgba(255,255,255,0.22) */
/* Light: thumb = rgba(217,79,79,0.18),   hover = rgba(217,79,79,0.32)  */
```

For inline chip/overflow rows use a 3px variant (class `chips-scroll`).

---

## 11. Buttons

| Class | Usage |
|---|---|
| `.glass-btn` | Default: icon buttons, secondary actions |
| `.glass-btn-primary` | CTA / submit — accent gradient fill |
| `.glass-btn-danger` | Destructive actions (delete, sign out) — rose tint |

All buttons: `transition: all 0.2s`, disabled state `opacity: 0.3`, `cursor: not-allowed`.

Three-dot kebab menu pattern: `w-8 h-8` square `.glass-btn` with three `3px` dot spans, dropdown rendered as a `.glass rounded-xl` absolutely positioned below.

---

## 12. Forcing Dark Mode

In `App.jsx` (or entry component):
```js
useEffect(() => {
  document.documentElement.classList.add('dark');
}, []);
```

In `tailwind.config.js`:
```js
darkMode: 'class'
```

---

## 13. Info Tooltips

Small `ⓘ` icon next to panel titles. On hover, shows a `.glass` tooltip with `position: fixed` via `createPortal` at `z-index: 9999` to avoid being clipped by overflow containers.

---

## 14. Filter State Pattern

```js
// State shape
const DEFAULT_FILTERS = {
  date_from: dayjs().subtract(14, 'day').format('YYYY-MM-DD'),
  date_to:   dayjs().format('YYYY-MM-DD'),
  model: [], account: [], category: [], vehicle: [], content_type: [],
};

// Persist to localStorage
useEffect(() => {
  localStorage.setItem('dashboard_filters', JSON.stringify(filters));
}, [JSON.stringify(filters)]);

// Convert arrays → comma-joined strings for API calls
function buildApiParams(filters) {
  const out = {};
  for (const [k, v] of Object.entries(filters)) {
    if (Array.isArray(v)) { if (v.length > 0) out[k] = v.join(','); }
    else if (v != null)   { out[k] = v; }
  }
  return out;
}
```

On the backend, split them back:
```js
function toArray(val) {
  if (!val) return [];
  return val.split(',').map(s => s.trim()).filter(Boolean);
}
// Use: WHERE column = ANY($n)  with an array param
```
