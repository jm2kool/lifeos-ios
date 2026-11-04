// Time-zone arithmetic without libraries: the user's weekly windows ("Mon 16:00–20:00") become real instants.

export interface Parts { y: number; m: number; d: number; h: number; mi: number; weekday: number }

const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const formatters = new Map<string, Intl.DateTimeFormat>();

export function validZone(tz: string): string {
  try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); return tz; } catch { return 'UTC'; }
}

function fmt(tz: string): Intl.DateTimeFormat {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: tz, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
      hour: 'numeric', minute: 'numeric', second: 'numeric', weekday: 'short',
    });
    formatters.set(tz, f);
  }
  return f;
}

/** The wall-clock date and time in `tz` at instant `d`. */
export function partsIn(d: Date, tz: string): Parts {
  const p = Object.fromEntries(fmt(tz).formatToParts(d).map((x) => [x.type, x.value]));
  return { y: +p.year, m: +p.month, d: +p.day, h: +p.hour % 24, mi: +p.minute, weekday: WEEKDAYS[p.weekday] ?? 0 };
}

/** Milliseconds the zone is ahead of UTC at instant `d`. */
export function offsetAt(d: Date, tz: string): number {
  const p = partsIn(d, tz);
  return Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi) - Math.floor(d.getTime() / 60000) * 60000;
}

/** The instant when the wall clock in `tz` shows y-m-d h:mi. */
export function zoned(y: number, m: number, d: number, h: number, mi: number, tz: string): Date {
  const guess = Date.UTC(y, m - 1, d, h, mi);
  let t = guess - offsetAt(new Date(guess), tz);
  const again = guess - offsetAt(new Date(t), tz);
  if (again !== t) t = again;
  return new Date(t);
}

/** "HH:MM" → minutes after midnight. */
export function minutes(hhmm: string | null | undefined, fallback = 0): number {
  const m = /^(\d{1,2}):(\d{2})/.exec(hhmm ?? '');
  return m ? Math.min(24 * 60, +m[1] * 60 + +m[2]) : fallback;
}

/** Each local day from `from` to `to`: its date, weekday and start instant. */
export function days(from: Date, to: Date, tz: string): { y: number; m: number; d: number; weekday: number; start: Date; key: string }[] {
  const out = [];
  const p = partsIn(from, tz);
  let cursor = Date.UTC(p.y, p.m - 1, p.d);
  for (let i = 0; i < 400; i++) {
    const c = new Date(cursor);
    const y = c.getUTCFullYear(), m = c.getUTCMonth() + 1, d = c.getUTCDate();
    const start = zoned(y, m, d, 0, 0, tz);
    if (start >= to) break;
    out.push({ y, m, d, weekday: c.getUTCDay(), start, key: `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}` });
    cursor += 86400e3;
  }
  return out;
}

export function startOfDay(d: Date, tz: string): Date {
  const p = partsIn(d, tz);
  return zoned(p.y, p.m, p.d, 0, 0, tz);
}

export function dayKey(d: Date, tz: string): string {
  const p = partsIn(d, tz);
  return `${p.y}-${String(p.m).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`;
}

/** "Thu 14:00" in the user's zone. */
export function label(d: Date, tz: string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone: tz, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(d).replace(',', '');
}

export function isoLocal(d: Date, tz: string): string {
  const p = partsIn(d, tz);
  const off = Math.round(offsetAt(d, tz) / 60000);
  const sign = off >= 0 ? '+' : '-';
  const a = Math.abs(off);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${p.y}-${pad(p.m)}-${pad(p.d)}T${pad(p.h)}:${pad(p.mi)}:00${sign}${pad(Math.floor(a / 60))}:${pad(a % 60)}`;
}

export interface Span { start: number; end: number }

/** Removes the `minus` spans from `base` (all in ms). */
export function subtract(base: Span[], minus: Span[]): Span[] {
  let out = base.filter((b) => b.end > b.start);
  for (const m of minus) {
    if (m.end <= m.start) continue;
    const next: Span[] = [];
    for (const b of out) {
      if (m.end <= b.start || m.start >= b.end) { next.push(b); continue; }
      if (m.start > b.start) next.push({ start: b.start, end: m.start });
      if (m.end < b.end) next.push({ start: m.end, end: b.end });
    }
    out = next;
  }
  return out.filter((s) => s.end - s.start >= 60e3).sort((a, b) => a.start - b.start);
}

export const overlaps = (a: Span, b: Span) => a.start < b.end && b.start < a.end;
