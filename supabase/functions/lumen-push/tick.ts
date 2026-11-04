// One run of the push scheduler (every minute, from pg_cron): starts the study block Live Activity on each iPhone
// about 10 minutes before a block, and ends activities whose block is over, skipped or deleted.
import type { Db, Row } from '../_shared/db.ts';
import { type ApnsConfig, endActivityPayload, sendActivity, startActivityPayload, type StudyState } from '../_shared/apns.ts';

export const LEAD_MINUTES = 10;

const unix = (iso: string) => Math.floor(Date.parse(iso) / 1000);

export async function tick(db: Db, cfg: ApnsConfig, now = new Date(), fetcher: typeof fetch = fetch) {
  const out = { started: 0, ended: 0, users: 0, errors: [] as string[] };
  const tokens = await db.select('push_tokens', { kind: 'in.(live_activity_start,live_activity)', disabled_at: 'is.null', select: '*' });
  const users = [...new Set(tokens.map((t) => t.user_id as string))];
  out.users = users.length;
  const lead = new Date(now.getTime() + LEAD_MINUTES * 60e3).toISOString();

  for (const user of users) {
    const mine = tokens.filter((t) => t.user_id === user);
    const starters = mine.filter((t) => t.kind === 'live_activity_start');
    const running = mine.filter((t) => t.kind === 'live_activity' && t.activity_key);

    // Blocks starting within the next ten minutes (or already on), still planned.
    const due = starters.length
      ? await db.select('blocks', {
        user_id: `eq.${user}`, deleted: 'is.false', status: 'eq.planned', select: '*', order: 'start_at.asc',
        and: `(start_at.lte."${lead}",end_at.gt."${now.toISOString()}")`,
      })
      : [];
    const keyed = running.length
      ? await db.select('blocks', { user_id: `eq.${user}`, id: `in.(${[...new Set(running.map((t) => t.activity_key))].join(',')})`, select: '*' })
      : [];
    const named = await describe(db, user, [...due, ...keyed]);

    for (const b of due) {
      const key = `la-start:${b.id}`;
      const already = await db.select('push_sent', { user_id: `eq.${user}`, key: `eq.${key}`, select: 'key' });
      if (already.length) continue;
      // An iPhone that already has this block's activity (the app started it) is left alone.
      if (running.some((t) => t.activity_key === b.id)) { await markSent(db, user, key); continue; }
      const state = stateFor(b, named, new Date(b.start_at) > now ? 'upcoming' : 'during');
      const minutes = Math.max(1, Math.round((Date.parse(b.start_at) - now.getTime()) / 60e3));
      const alert = new Date(b.start_at) > now
        ? { title: `${state.subject || 'Study'} in ${minutes} min`, body: state.goal || state.title }
        : { title: `${state.subject || 'Study'} is on`, body: state.goal || state.title };
      let any = false;
      for (const t of starters) {
        const r = await sendActivity(db, cfg, t, startActivityPayload(b.id, state, alert), fetcher);
        if (r.ok) any = true; else out.errors.push(`start ${b.id}: ${r.reason ?? r.status}`);
      }
      if (any) { out.started++; await markSent(db, user, key); }
    }

    for (const t of running) {
      const b = keyed.find((x) => x.id === t.activity_key);
      const over = !b || b.deleted || b.status !== 'planned' || Date.parse(b.end_at) <= now.getTime();
      if (!over) continue;
      const key = `la-end:${t.activity_key}:${t.id}`;
      const already = await db.select('push_sent', { user_id: `eq.${user}`, key: `eq.${key}`, select: 'key' });
      if (!already.length) {
        const state = b ? stateFor(b, named, 'ended') : { phase: 'ended', title: 'Study block', goal: '', subject: '', colorHex: '#8FA8FF', kind: 'study', start: 0, end: 0, note: '' } as StudyState;
        if (b?.status === 'skipped') state.note = 'Skipped';
        const r = await sendActivity(db, cfg, t, endActivityPayload(state), fetcher);
        if (r.ok) out.ended++; else out.errors.push(`end ${t.activity_key}: ${r.reason ?? r.status}`);
        await markSent(db, user, key);
      }
      // An ended activity's token is never used again.
      await db.update('push_tokens', { id: `eq.${t.id}` }, { disabled_at: now.toISOString() }).catch(() => {});
    }
  }
  return out;
}

async function markSent(db: Db, user: string, key: string) {
  await db.insert('push_sent', { user_id: user, key }).catch(() => {});
}

interface Names { subjects: Map<string, Row>; assignments: Map<string, string> }

async function describe(db: Db, user: string, blocks: Row[]): Promise<Names> {
  const sids = [...new Set(blocks.map((b) => b.subject_id).filter(Boolean))];
  const aids = [...new Set(blocks.map((b) => b.assignment_id).filter(Boolean))];
  const [subjects, assignments] = await Promise.all([
    sids.length ? db.select('subjects', { user_id: `eq.${user}`, id: `in.(${sids.join(',')})`, select: 'id,name,color' }) : Promise.resolve([] as Row[]),
    aids.length ? db.select('assignments', { user_id: `eq.${user}`, id: `in.(${aids.join(',')})`, select: 'id,title' }) : Promise.resolve([] as Row[]),
  ]);
  return { subjects: new Map(subjects.map((s) => [s.id, s])), assignments: new Map(assignments.map((a) => [a.id, a.title])) };
}

const LABEL: Record<string, string> = { study: 'Study', revision: 'Revision', review: 'Card review', practice: 'Practice' };

export function stateFor(b: Row, names: Names, phase: StudyState['phase']): StudyState {
  const s = names.subjects.get(b.subject_id);
  const title = names.assignments.get(b.assignment_id) ?? (b.goal || LABEL[b.kind] || 'Study');
  return {
    phase, title, goal: b.goal && b.goal !== title ? b.goal : '', subject: s?.name ?? (LABEL[b.kind] ?? 'Study'),
    colorHex: s?.color ?? '#8FA8FF', kind: b.kind ?? 'study', start: unix(b.start_at), end: unix(b.end_at), note: '',
  };
}
