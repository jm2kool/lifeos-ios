import { test } from 'node:test';
import assert from 'node:assert/strict';
import Core from '../api/_core.mjs';

const base = () => Core.normalize({ content: { events: [], inbox: [] }, state: {} });
const undoLast = d => Core.undo(d, d.state.log[0].id, { by: 'you' }).doc;
const strip = d => JSON.stringify({ content: { ...d.content, drafts: d.content.drafts?.length ? d.content.drafts : undefined }, tasks: d.state.tasks, board: d.state.board, saved: d.state.saved, done: d.state.done, priority: d.state.priority, timetable: d.state.timetable, drafts: d.content.drafts?.length ? d.content.drafts : undefined, reviews: d.state.draftReviews });

test('every logged change records who made it and can be undone back to the start', () => {
  let d = base();
  const steps = [
    { op: 'task.add', title: 'Revise Sound', due: '2026-10-19' },
    { op: 'board.add', title: 'Graph paper' },
    { op: 'saved.add', title: 'Link', url: 'https://example.com' },
    { op: 'timetable.set', text: '2026-10-19\n18:00 Study' },
    { op: 'content.upsert', path: 'events', value: { id: 'e1', title: 'Exam', start: '2026-10-25' } },
    { op: 'draft.email', inboxId: 'm1', subject: 'Re: Hi', body: 'Hello' },
    { op: 'draft.review', draftId: 'p', version: 1, week: 'w1', action: 'approve' },
  ];
  const snaps = [strip(d)];
  for (const s of steps) { d = Core.apply(d, { ...s, by: 'FRIDAY' }).doc; assert.equal(d.state.log[0].by, 'FRIDAY'); assert.ok(d.state.log[0].undo, s.op + ' has undo'); snaps.push(strip(d)) }
  assert.equal(d.state.tasks[0].changedBy, 'FRIDAY');
  assert.equal(d.content.events[0].changedBy, 'FRIDAY');
  // updates and removes undo too
  const tid = d.state.tasks[0].id;
  d = Core.apply(d, { op: 'task.update', id: tid, title: 'Revise Light', by: 'FRIDAY' }).doc; d = undoLast(d);
  assert.equal(d.state.tasks[0].title, 'Revise Sound');
  d = Core.apply(d, { op: 'task.remove', id: tid, by: 'FRIDAY' }).doc; d = undoLast(d);
  assert.equal(d.state.tasks.length, 1); assert.ok(!d.state.deletedTasks.includes(tid));
  // unwind everything, newest first, matching each earlier snapshot
  for (let i = steps.length - 1; i >= 0; i--) {
    const entry = d.state.log.find(e => e.by === 'FRIDAY' && !e.undone && e.op === steps[i].op);
    d = Core.undo(d, entry.id, { by: 'you' }).doc;
    assert.equal(strip(d).replace(/"changed(By|At)":[^,}]*,?/g, ''), snaps[i].replace(/"changed(By|At)":[^,}]*,?/g, ''), 'after undoing ' + steps[i].op);
  }
});

test('undo refuses twice, refuses other keys’ changes when not allowed', () => {
  let d = Core.apply(base(), { op: 'task.add', title: 'x', by: 'FRIDAY' }, { keyId: 'k1' }).doc;
  const id = d.state.log[0].id;
  assert.throws(() => Core.undo(d, id, { by: 'Other', allow: e => e.key === 'k2' }), /only undo its own/);
  d = Core.undo(d, id, { by: 'FRIDAY', allow: e => e.key === 'k1' }).doc;
  assert.throws(() => Core.undo(d, id, { by: 'FRIDAY' }), /Already undone/);
});

test('duplicates: the seeded 24 and 25 Oct calendar pairs', () => {
  const d = Core.normalize({ content: { events: [
    { id: 'a', title: 'Tallentex mock + review', start: '2026-10-24T15:00:00+05:30', status: 'superseded' },
    { id: 'b', title: 'Tallentex mock + review', start: '2026-10-24T15:00:00+05:30' },
    { id: 'c', title: 'TALLENTEX mock + review', start: '2026-10-24T15:00:00+05:30' },
    { id: 'tallentex-20261025', title: 'TALLENTEX - offline exam', start: '2026-10-25' },
    { id: 'x', title: 'TALLENTEX exam (offline)', start: '2026-10-25T08:00:00+05:30' },
    { id: 'p', title: 'Physics Tuition', start: '2026-10-22T19:00:00+05:30' },
    { id: 'q', title: 'Chemistry Tuition', start: '2026-10-22T19:00:00+05:30' },
    { id: 'r', title: 'Tallentex prep', start: '2026-10-21T18:45:00+05:30' },
    { id: 's', title: 'TALLENTEX Prep Class - Chemistry (ALLEN)', start: '2026-10-21T18:00:00+05:30' },
  ] }, state: {} });
  const g = Core.duplicates(d);
  assert.equal(g.length, 2);
  assert.deepEqual(g[0].items.map(i => i.id).sort(), ['b', 'c']);
  assert.deepEqual(g[1].items.map(i => i.id).sort(), ['tallentex-20261025', 'x']);
  assert.equal(g[1].keep, 'x', 'keeps the timed copy');
});

test('import: merges, skips duplicates, reports bad items, is idempotent and undoable in one step', () => {
  let d = Core.apply(base(), { op: 'content.upsert', path: 'events', value: { id: 'old', title: 'TALLENTEX exam (offline)', start: '2026-10-25T08:00:00+05:30' } }).doc;
  const input = {
    events: [{ title: 'TALLENTEX - offline exam', start: '2026-10-25' }, { title: 'Mock + review', start: '2026-10-24T15:00:00+05:30' }, { title: 'mock & review', start: '2026-10-24T15:00:00+05:30' }, { title: 'No date' }],
    inbox: Array.from({ length: 11 }, (_, i) => ({ subject: 'Mail ' + i, from: 'a@b.c', body: 'x' })),
    tasks: [{ title: 'Revise Sound', due: '2026-10-19' }, { title: 'revise   sound!', due: '2026-10-19' }, { title: 'Bad due', due: 'tomorrow' }],
  };
  const r = Core.runImport(d, input, { by: 'FRIDAY', batch: 'b1' });
  assert.deepEqual(r.counts.inbox, { added: 11, updated: 0, unchanged: 0, duplicate: 0, failed: 0 });
  assert.deepEqual(r.counts.events, { added: 1, updated: 0, unchanged: 0, duplicate: 2, failed: 1 });
  assert.equal(r.items.find(i => i.kind === 'events' && i.index === 0).duplicateOf, 'old');
  assert.equal(r.counts.tasks.added, 1); assert.equal(r.counts.tasks.duplicate, 1); assert.equal(r.counts.tasks.failed, 1);
  assert.match(r.summary, /^Imported 1 task, 1 event, 11 inbox items; 3 likely duplicates skipped; 2 items failed\.$/);
  assert.equal(r.doc.content.inbox.length, 11);
  assert.equal(r.doc.state.log[0].op, 'import'); assert.equal(r.doc.state.log.filter(e => e.op === 'content.put').length, 0, 'one log entry, not 13');
  // same batch again: nothing new
  const again = Core.runImport(r.doc, input, { by: 'FRIDAY' });
  assert.equal(again.counts.inbox.unchanged, 11); assert.equal(again.changed, false);
  // one-step undo
  const u = Core.undo(r.doc, r.doc.state.log[0].id, { by: 'you' }).doc;
  assert.equal(u.content.inbox.length, 0); assert.equal(u.state.tasks.length, 0); assert.equal(u.content.events.length, 1);
});

test('import of a whole exported doc fills an empty server', () => {
  const exported = Core.normalize({ profile: { name: 'Ram', timezone: 'Asia/Kolkata' }, content: { events: [{ id: 'e', title: 'Exam', start: '2026-10-25' }], inbox: [{ id: 'm', t: 'Hi', sender: 'a@b.c', f: 'Gmail' }], drafts: [{ id: 'p', title: 'Plan', versions: [{ version: 1, body: 'Text' }] }], study: { block: 'Sound' } },
    state: { tasks: [{ id: 't1', title: 'A' }, { id: 't2', title: 'B' }], done: ['t2'], priority: { m: 'High' }, timetable: '2026-10-19\n18:00 x' } });
  const r = Core.runImport(Core.normalize({}), { doc: exported }, { by: 'you' });
  assert.equal(r.summary, 'Imported 2 tasks, 1 event, 1 inbox item.');
  const d = r.doc;
  assert.equal(d.profile.name, 'Ram'); assert.equal(d.content.drafts[0].versions[0].body, 'Text'); assert.equal(d.content.study.block, 'Sound');
  assert.deepEqual(d.state.done, ['t2']); assert.equal(d.state.priority.m, 'High'); assert.ok(d.state.timetable);
});
