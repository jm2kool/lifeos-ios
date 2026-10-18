/* LifeOS core: the one reducer shared by the app (mirrored in LifeOS/Model/Reducer.swift) and the sync server.
   Every change, from the app, Gemini, or your iMessage assistant, is an "op": {op:"task.add", ...fields}.
   apply(doc, op) returns the changed doc. Same input, same result, on phone and server. */
const LifeOSCore=(()=>{
const SCHEMA='lifeos/2';
const clone=x=>JSON.parse(JSON.stringify(x));
const uid=p=>(p||'id')+'-'+Date.now().toString(36)+Math.random().toString(36).slice(2,7);
const str=(v,max=4000)=>typeof v==='string'?v.slice(0,max):v==null?'':String(v).slice(0,max);
const BAD=new Set(['__proto__','prototype','constructor']);
const COLS=['To do','Doing','Done'];
const MAPS=['priority','snooze','progress','draftReviews'];

function blank(){return{schema:SCHEMA,rev:0,updatedAt:null,updatedBy:null,profile:{name:'',timezone:'',assistant:{}},settings:{},content:{},state:{},applied:[]}}
function normalize(doc){
  const d=Object.assign(blank(),doc||{});
  d.profile=Object.assign({name:'',timezone:'',assistant:{}},d.profile||{});
  d.settings=Object.assign({theme:'auto',colorway:'purple',solidNav:false,tabs:['today','inbox','study','board'],ai:{},sync:{}},d.settings||{});
  d.content=d.content||{};
  const s=d.state=Object.assign({},d.state||{});
  for(const k of ['tasks','board','saved','done','inboxDone','focus','messages','deletedTasks','log'])if(!Array.isArray(s[k]))s[k]=[];
  for(const k of ['priority','snooze','progress','draftReviews'])if(!s[k]||typeof s[k]!=='object'||Array.isArray(s[k]))s[k]={};
  if(typeof s.timetable!=='string')s.timetable='';
  if(!Array.isArray(d.applied))d.applied=[];
  return d;
}
function path(obj,p,create){
  const parts=String(p||'').split('.').filter(Boolean);
  if(parts.some(k=>BAD.has(k)))throw Error('Bad path');
  let o=obj;for(let i=0;i<parts.length-1;i++){const k=parts[i];if(o[k]==null||typeof o[k]!=='object'){if(!create)return[null,null];o[k]={}}o=o[k]}
  return[o,parts[parts.length-1]];
}
const byId=(list,id)=>list.findIndex(x=>x&&String(x.id)===String(id));
function patch(item,f,keys){for(const k of keys)if(k in f&&f[k]!==undefined)item[k]=f[k]===null?undefined:f[k];return item}

/* op name -> handler(doc, op, at) */
const H={
  'task.add'(d,o,at){const t={id:o.id||uid('task'),title:str(o.title,240).trim(),note:str(o.note,1500),src:str(o.src||'You',60),created:o.created||at};if(o.due)t.due=str(o.due,10);if(o.priority)t.priority=str(o.priority,10);if(!t.title)throw Error('Task needs a title');if(byId(d.state.tasks,t.id)<0)d.state.tasks.push(t);d.state.deletedTasks=d.state.deletedTasks.filter(x=>String(x)!==String(t.id))},
  'task.update'(d,o){const i=byId(d.state.tasks,o.id);if(i<0)throw Error('No such task');patch(d.state.tasks[i],o,['title','note','due','src','priority'])},
  'task.done'(d,o){const id=String(o.id),set=new Set(d.state.done.map(String));o.done===false?set.delete(id):set.add(id);d.state.done=[...set]},
  'task.remove'(d,o){d.state.tasks=d.state.tasks.filter(t=>String(t.id)!==String(o.id));d.state.done=d.state.done.filter(x=>String(x)!==String(o.id));if(!d.state.deletedTasks.includes(String(o.id)))d.state.deletedTasks.push(String(o.id))},

  'board.add'(d,o,at){const c=typeof o.column==='number'?o.column:Math.max(0,COLS.indexOf(o.column||'To do'));const b={id:o.id||uid('card'),t:str(o.title??o.t,240).trim(),c,created:o.created||at};if(o.due)b.due=str(o.due,10);if(o.filed===false)b.filed=false;if(o.note)b.note=str(o.note,1500);if(!b.t)throw Error('Card needs a title');if(byId(d.state.board,b.id)<0)d.state.board.push(b)},
  'board.update'(d,o){const i=byId(d.state.board,o.id);if(i<0)throw Error('No such card');const b=d.state.board[i];if(o.title!==undefined)b.t=str(o.title,240);patch(b,o,['due','note','filed']);if(o.column!==undefined)H['board.move'](d,o)},
  'board.move'(d,o){const b=d.state.board.find(x=>String(x.id)===String(o.id));if(!b)throw Error('No such card');const c=typeof o.column==='number'?o.column:COLS.indexOf(o.column);if(c<0||c>2)throw Error('Column must be To do, Doing or Done');b.c=c;if(c>0)b.filed=undefined},
  'board.remove'(d,o){d.state.board=d.state.board.filter(x=>String(x.id)!==String(o.id))},

  'saved.add'(d,o,at){const url=str(o.url,2000).trim();if(url&&!/^https?:\/\//i.test(url))throw Error('Links must start with http:// or https://');const s={id:o.id||uid('saved'),t:str(o.title??o.t,240).trim(),url,n:str(o.note??o.n,1500),s:str(o.source??o.s??'You',60),c:o.created||at};if(!s.t)throw Error('Saved item needs a title');if(byId(d.state.saved,s.id)<0)d.state.saved.unshift(s)},
  'saved.update'(d,o){const i=byId(d.state.saved,o.id);if(i<0)throw Error('No such item');const s=d.state.saved[i];if(o.title!==undefined)s.t=str(o.title,240);if(o.url!==undefined){if(o.url&&!/^https?:\/\//i.test(o.url))throw Error('Links must start with http:// or https://');s.url=str(o.url,2000)}if(o.note!==undefined)s.n=str(o.note,1500)},
  'saved.remove'(d,o){d.state.saved=d.state.saved.filter(x=>String(x.id)!==String(o.id))},

  'inbox.done'(d,o){const id=String(o.id),set=new Set(d.state.inboxDone.map(String));o.done===false?set.delete(id):set.add(id);d.state.inboxDone=[...set]},
  'inbox.priority'(d,o){if(o.value)d.state.priority[o.id]=str(o.value,10);else delete d.state.priority[o.id]},
  'inbox.snooze'(d,o){if(o.until||o.on)d.state.snooze[o.id]=o.until||true;else delete d.state.snooze[o.id]},

  'progress.set'(d,o){d.state.progress[o.id]={done:!!o.done,label:str(o.label,300),at:o.at||Date.now()}},
  'focus.remove'(d,o){d.state.focus=d.state.focus.filter(f=>String(f.id)!==String(o.id))},
  'focus.log'(d,o,at){const m=Math.round(Number(o.minutes));if(!(m>0&&m<=600))throw Error('Minutes must be 1-600');d.state.focus.push({id:o.id||uid('focus'),date:str(o.date,10),minutes:m,label:str(o.label,200),at});if(d.state.focus.length>800)d.state.focus.splice(0,d.state.focus.length-800)},
  'timetable.set'(d,o){d.state.timetable=str(o.text,20000)},
  'draft.review'(d,o,at){const k=[o.draftId,o.version,o.week,o.action].join('|');d.state.draftReviews[k]={draftId:str(o.draftId,80),version:o.version,week:str(o.week,80),action:o.action==='changes'?'changes':'approve',changes:str(o.changes,4000),at,state:o.state||'recorded'}},

  'draft.email'(d,o,at){const body=str(o.body,8000);if(!body)throw Error('Email draft needs a body');if(!Array.isArray(d.content.drafts))d.content.drafts=[];const id=o.id||(o.inboxId!=null?'reply-'+o.inboxId:uid('email'));const now=new Date(at).toISOString();const i=byId(d.content.drafts,id);
    if(i>=0){const dr=d.content.drafts[i];const vs=dr.versions||(dr.versions=[]);const last=vs[vs.length-1]||{};const v=Object.assign({},last,{version:Math.max(0,...vs.map(x=>x.version||0))+1,createdAt:now,body,by:o.by||''});for(const k of ['to','cc','from','subject'])if(o[k]!==undefined)v[k]=o[k];vs.push(v)}
    else d.content.drafts.push({id,title:o.title||('Reply: '+String(o.subject||'').replace(/^Re:\s*/i,'')),type:'email',inboxId:o.inboxId!=null?String(o.inboxId):undefined,source:o.by||'',versions:[{version:1,createdAt:now,from:o.from||'',to:o.to||'',cc:o.cc||'',subject:o.subject||'',body,by:o.by||''}]})},
  'draft.remove'(d,o){if(Array.isArray(d.content.drafts))d.content.drafts=d.content.drafts.filter(x=>String(x.id)!==String(o.id))},
  'message.add'(d,o,at){d.state.messages.unshift({id:o.id||uid('msg'),from:str(o.from||'Assistant',60),text:str(o.text,2000),url:str(o.url,2000),at:o.at||at});d.state.messages=d.state.messages.slice(0,50)},
  'message.dismiss'(d,o){d.state.messages=d.state.messages.filter(m=>String(m.id)!==String(o.id))},

  /* generic content editing: lets an assistant change anything shown in the app */
  'content.set'(d,o){const[p,k]=path(d.content,o.path,true);if(!p)throw Error('Bad path');if(o.value===undefined)delete p[k];else p[k]=clone(o.value)},
  'content.merge'(d,o){const[p,k]=path(d.content,o.path,true);if(!p)throw Error('Bad path');p[k]=Object.assign(p[k]&&typeof p[k]==='object'?p[k]:{},clone(o.value))},
  'content.push'(d,o){const[p,k]=path(d.content,o.path,true);if(!Array.isArray(p[k]))p[k]=[];p[k].push(clone(o.value))},
  'content.upsert'(d,o){const[p,k]=path(d.content,o.path,true);if(!Array.isArray(p[k]))p[k]=[];const v=clone(o.value);if(v.id==null)throw Error('content.upsert needs value.id');const i=byId(p[k],v.id);i<0?p[k].push(v):p[k][i]=Object.assign(p[k][i],v)},
  'content.put'(d,o){const[p,k]=path(d.content,o.path,true);if(!Array.isArray(p[k]))p[k]=[];const v=clone(o.value);if(!v||v.id==null)throw Error('content.put needs value.id');const i=byId(p[k],v.id);i<0?p[k].push(v):p[k][i]=v},
  'content.remove'(d,o){const[p,k]=path(d.content,o.path,false);if(p&&Array.isArray(p[k]))p[k]=p[k].filter(x=>!x||String(x.id)!==String(o.id));else if(p&&o.id==null)delete p[k]},
  'state.set'(d,o){const[p,k]=path(d.state,o.path,true);if(!p)throw Error('Bad path');if(o.value===undefined)delete p[k];else p[k]=clone(o.value)},
  /* sets one key of a state map (priority, snooze, progress, draftReviews); keys may contain dots */
  'state.setKey'(d,o){if(!MAPS.includes(o.path))throw Error('state.setKey path must be one of '+MAPS.join(', '));const k=String(o.key);if(BAD.has(k))throw Error('Bad key');if(o.value===undefined||o.value===null)delete d.state[o.path][k];else d.state[o.path][k]=clone(o.value)},
  'profile.set'(d,o){const v=clone(o.value||{});for(const k of Object.keys(v))if(!BAD.has(k))d.profile[k]=v[k]},
  'settings.set'(d,o){const v=clone(o.value||{});for(const k of Object.keys(v))if(!BAD.has(k))d.settings[k]=(v[k]&&typeof v[k]==='object'&&!Array.isArray(v[k]))?Object.assign({},d.settings[k]||{},v[k]):v[k]},
};
const OPS=Object.keys(H);

/* Ops that undo `o` when applied to `d` as it was just before `o`. [] means it can't be undone. */
function get(root,p){const[o,k]=path(root,p,false);return o?o[k]:undefined}
function inverse(d,o){
  const id=o.id,s=d.state,find=k=>s[k].find(x=>x&&String(x.id)===String(id)),has=k=>s[k].map(String).includes(String(id));
  const prior=(list,vid)=>Array.isArray(list)?list.find(x=>x&&String(x.id)===String(vid)):undefined;
  const nul=v=>v===undefined?null:v;
  switch(o.op){
    case 'task.add':return find('tasks')?[]:[{op:'task.remove',id}];
    case 'task.update':{const t=find('tasks');if(!t)return[];const r={op:'task.update',id};for(const k of ['title','note','due','src','priority'])if(k in o)r[k]=nul(t[k]);return[r]}
    case 'task.done':return[{op:'task.done',id,done:has('done')}];
    case 'task.remove':{const t=find('tasks');if(!t)return[];const r=[Object.assign({},t,{op:'task.add'})];if(has('done'))r.push({op:'task.done',id,done:true});return r}
    case 'board.add':return find('board')?[]:[{op:'board.remove',id}];
    case 'board.update':case 'board.move':{const b=find('board');if(!b)return[];return[{op:'board.update',id,title:b.t,due:nul(b.due),note:nul(b.note),filed:nul(b.filed),column:b.c}]}
    case 'board.remove':{const b=find('board');if(!b)return[];return[{op:'board.add',id,title:b.t,column:b.c,due:b.due,note:b.note,filed:b.filed,created:b.created}]}
    case 'saved.add':return find('saved')?[]:[{op:'saved.remove',id}];
    case 'saved.update':{const x=find('saved');if(!x)return[];return[{op:'saved.update',id,title:x.t,url:x.url,note:x.n}]}
    case 'saved.remove':{const x=find('saved');if(!x)return[];return[{op:'saved.add',id,title:x.t,url:x.url,note:x.n,source:x.s,created:x.c}]}
    case 'inbox.done':return[{op:'inbox.done',id,done:has('inboxDone')}];
    case 'inbox.priority':return[{op:'inbox.priority',id,value:s.priority[id]||''}];
    case 'inbox.snooze':{const v=s.snooze[id];return[{op:'inbox.snooze',id,on:!!v,until:typeof v==='boolean'?undefined:v}]}
    case 'progress.set':return[{op:'state.setKey',path:'progress',key:String(id),value:s.progress[id]}];
    case 'focus.log':return[{op:'focus.remove',id}];
    case 'timetable.set':return[{op:'timetable.set',text:s.timetable}];
    case 'draft.review':{const k=[o.draftId,o.version,o.week,o.action].join('|');return[{op:'state.setKey',path:'draftReviews',key:k,value:s.draftReviews[k]}]}
    case 'draft.email':{const dr=prior(d.content.drafts,id);return dr?[{op:'content.put',path:'drafts',value:dr}]:[{op:'draft.remove',id}]}
    case 'draft.remove':{const dr=prior(d.content.drafts,id);return dr?[{op:'content.put',path:'drafts',value:dr}]:[]}
    case 'message.add':return[{op:'message.dismiss',id}];
    case 'message.dismiss':{const m=find('messages');return m?[Object.assign({},m,{op:'message.add'})]:[]}
    case 'content.upsert':case 'content.put':{const vid=o.value&&o.value.id;const p=prior(get(d.content,o.path),vid);return p?[{op:'content.put',path:o.path,value:p}]:[{op:'content.remove',path:o.path,id:vid}]}
    case 'content.remove':{const cur=get(d.content,o.path);if(o.id!=null){const p=prior(cur,o.id);return p?[{op:'content.put',path:o.path,value:p}]:[]}return[{op:'content.set',path:o.path,value:cur}]}
    case 'content.set':case 'content.merge':case 'content.push':return[{op:'content.set',path:o.path,value:get(d.content,o.path)}];
    case 'state.set':return[{op:'state.set',path:o.path,value:get(d.state,o.path)}];
    case 'state.setKey':return MAPS.includes(o.path)?[{op:'state.setKey',path:o.path,key:o.key,value:s[o.path][o.key]}]:[];
    case 'profile.set':{const v={};for(const k of Object.keys(o.value||{}))v[k]=d.profile[k]===undefined?'':clone(d.profile[k]);return[{op:'profile.set',value:v}]}
    case 'settings.set':{const v={};for(const k of Object.keys(o.value||{}))v[k]=d.settings[k]===undefined?'':clone(d.settings[k]);return[{op:'settings.set',value:v}]}
    default:return[];
  }
}

/* "changed by" label on the item an op touched */
function stamp(d,o,at){
  const by=str(o.by||'app',40);const mark=x=>{if(x&&typeof x==='object'){x.changedBy=by;x.changedAt=at}};
  const list={task:'tasks',board:'board',saved:'saved'}[o.op.split('.')[0]];
  if(list&&!/\.(remove|done)$/.test(o.op))return mark(d.state[list].find(x=>x&&String(x.id)===String(o.id)));
  if(o.op==='content.upsert'||o.op==='content.put'){const l=get(d.content,o.path);if(Array.isArray(l))mark(l.find(x=>x&&o.value&&String(x.id)===String(o.value.id)))}
  if(o.op==='draft.email'&&Array.isArray(d.content.drafts))mark(d.content.drafts.find(x=>String(x.id)===String(o.id)));
}

const ADDS={'task.add':'task','board.add':'card','saved.add':'saved','message.add':'msg','focus.log':'focus'};
const LOG_MAX=100,UNDO_MAX=16000;
/* Gives add-ops an id up front, so the change can be undone and the item found again. */
function prepare(op){
  const o=Object.assign({},op);
  if(ADDS[o.op]&&o.id==null)o.id=uid(ADDS[o.op]);
  if(o.op==='draft.email'&&o.id==null)o.id=o.inboxId!=null?'reply-'+o.inboxId:uid('email');
  return o;
}
const summaryOf=o=>str(o.title||o.subject||o.text||(o.value&&(o.value.title||o.value.t))||o.path||o.id||'',120);
function logEntry(d,e){d.state.log.unshift(e);if(d.state.log.length>LOG_MAX)d.state.log.length=LOG_MAX}

/* Apply one op. Returns {doc, ok, error, undo}. Never throws. Ops carrying an opId already applied are skipped.
   opts: inPlace, batch (groups a commit), keyId (who is calling), silent (don't log; caller logs a summary). */
function apply(doc,op,opts={}){
  const d=normalize(opts.inPlace?doc:clone(doc));
  try{
    if(!op||typeof op.op!=='string'||!H[op.op])throw Error('Unknown op '+(op&&op.op));
    if(op.opId&&d.applied.includes(op.opId))return{doc:d,ok:true,skipped:true};
    const o=prepare(op);
    const at=o.at||Date.now();
    const undo=clone(inverse(d,o));
    H[o.op](d,o,at);
    stamp(d,o,at);
    if(o.opId)d.applied.push(o.opId);
    if(d.applied.length>400)d.applied=d.applied.slice(-400);
    const fits=undo.length>0&&JSON.stringify(undo).length<=UNDO_MAX;
    if(!opts.silent)logEntry(d,{id:uid('log'),batch:opts.batch,op:o.op,by:str(o.by||'app',40),key:opts.keyId,at,summary:summaryOf(o),target:o.id??(o.value&&o.value.id)??o.path,undo:fits?undo:undefined});
    return{doc:d,ok:true,id:o.id,undo};
  }catch(e){return{doc:d,ok:false,error:e.message}}
}
function applyAll(doc,ops,opts={}){let d=normalize(clone(doc));const results=[];for(const op of ops||[]){const r=apply(d,op,Object.assign({},opts,{inPlace:true}));d=r.doc;results.push({op:op&&op.op,id:r.id,ok:r.ok,error:r.error,skipped:r.skipped})}return{doc:d,results}}

/* Undo logged changes (newest first). allow(entry) decides who may undo what. */
function undo(doc,ids,{by,keyId,batch,allow=()=>true}={}){
  let d=normalize(clone(doc));const want=new Set((Array.isArray(ids)?ids:[ids]).map(String));
  const entries=d.state.log.filter(e=>e&&(want.has(String(e.id))||(e.batch&&want.has(String(e.batch)))));
  if(!entries.length)throw Object.assign(Error('No such change in the recent log'),{status:404});
  for(const e of entries){
    if(e.undone)throw Object.assign(Error('Already undone: '+e.op+' '+(e.summary||'')),{status:409});
    if(!e.undo)throw Object.assign(Error('This change cannot be undone: '+e.op+' '+(e.summary||'')),{status:409});
    if(!allow(e))throw Object.assign(Error('This key can only undo its own changes'),{status:403});
  }
  const results=[],redo=[];
  for(const e of entries)for(const op of e.undo){const r=apply(d,Object.assign({},op,{by,at:undefined,opId:undefined}),{inPlace:true,batch,keyId,silent:true});d=r.doc;if(r.ok)redo.unshift(...(r.undo||[]));results.push({op:op.op,ok:r.ok,error:r.error})}
  const at=Date.now();
  for(const e of d.state.log)if(entries.some(x=>x.id===e.id))e.undone={by,at};
  logEntry(d,{id:uid('log'),batch,op:'undo',by:str(by,40),key:keyId,at,summary:str(entries.length===1?'Undid '+entries[0].op+' '+(entries[0].summary||''):'Undid '+entries.length+' changes',120),target:entries.map(e=>e.id).join(','),undo:redo.length&&JSON.stringify(redo).length<=UNDO_MAX*4?redo:undefined});
  return{doc:d,results,undone:entries.map(e=>e.id)};
}

/* ---------- duplicates ---------- */
const STOP=new Set(['the','a','an','and','of','for','to','in','on','at','with','re','fwd','fw']);
function words(s){return[...new Set(String(s||'').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]+/g,' ').split(' ').filter(w=>w&&!STOP.has(w)))].sort()}
function alike(a,b){const A=words(a),B=words(b);if(!A.length||!B.length)return false;const sb=new Set(B);const both=A.filter(w=>sb.has(w)).length;return both/(A.length+B.length-both)>=0.75}
const isActive=e=>e&&e.status!=='superseded'&&!/^(Paused|Superseded|Removed from live calendar)/i.test(e.note||'');
const minutes=s=>{const m=/T(\d\d):(\d\d)/.exec(String(s||''));return m?Number(m[1])*60+Number(m[2]):null};
/* is b a duplicate of a? (same kind, different ids) */
const SAME={
  events(a,b){if(String(a.start||'').slice(0,10)!==String(b.start||'').slice(0,10)||!alike(a.title,b.title))return false;const x=minutes(a.start),y=minutes(b.start);return x==null||y==null||Math.abs(x-y)<=90},
  tasks(a,b){return String(a.due||'')===String(b.due||'')&&alike(a.title,b.title)},
  inbox(a,b){return String(a.sender||'').toLowerCase()===String(b.sender||'').toLowerCase()&&alike(a.t,b.t)},
  board(a,b){return alike(a.t,b.t)&&(a.c===2)===(b.c===2)},
  saved(a,b){return(a.url&&a.url===b.url)||(!a.url&&!b.url&&alike(a.t,b.t))},
};
/* which of two duplicates to keep: active over superseded, timed over date-only */
const score=e=>(isActive(e)?2:0)+(String(e.start||'').length>10?1:0);
/* Groups of likely duplicates already in the doc (visible items only). */
function duplicates(doc){
  const d=normalize(doc),done=new Set(d.state.done.map(String)),idone=new Set(d.state.inboxDone.map(String));
  const lists={events:(d.content.events||[]).filter(isActive),tasks:d.state.tasks.filter(t=>!done.has(String(t.id))),inbox:(d.content.inbox||[]).filter(m=>!idone.has(String(m.id))),board:d.state.board,saved:d.state.saved};
  const out=[];
  for(const[kind,list]of Object.entries(lists)){const used=new Set();
    list.forEach((a,i)=>{if(!a||used.has(i))return;const g=[a];list.forEach((b,j)=>{if(j>i&&b&&!used.has(j)&&String(a.id)!==String(b.id)&&SAME[kind](a,b)){g.push(b);used.add(j)}});
      if(g.length>1){g.sort((x,y)=>kind==='events'?score(y)-score(x):0);out.push({kind,keep:g[0].id,items:g.map(x=>({id:x.id,title:x.title||x.t,start:x.start,due:x.due,sender:x.sender}))})}})}
  return out;
}

/* ---------- import (merge) ---------- */
function hash(s){let h=0x811c9dc5;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)}return(h>>>0).toString(36)}
const pick=(...v)=>v.find(x=>x!==undefined&&x!==null&&x!=='');
const DAY=/^\d{4}-\d{2}-\d{2}/;
/* Accepts friendly field names and returns the stored shape, or throws with what is missing. */
const SHAPE={
  tasks(x){const title=str(pick(x.title,x.t,x.text),240).trim();if(!title)throw Error('Task needs a title');const t={id:pick(x.id),title,note:str(pick(x.note,x.notes,''))};const src=pick(x.src,x.source);if(src)t.src=str(src,60);const due=pick(x.due,x.date);if(due){if(!DAY.test(due))throw Error('due must be YYYY-MM-DD');t.due=str(due,10)}if(x.priority)t.priority=str(x.priority,10);if(t.id==null)t.id='task-'+hash(title.toLowerCase()+'|'+(t.due||''));return t},
  events(x){const e=Object.assign({},x);e.title=str(pick(x.title,x.summary,x.t),240).trim();e.start=str(pick(x.start,x.date,x.when),40);if(!e.title)throw Error('Event needs a title');if(!e.start||!DAY.test(e.start)||isNaN(Date.parse(e.start.length>10?e.start:e.start+'T00:00:00Z')))throw Error('Event needs start as YYYY-MM-DD or an ISO date-time');for(const k of ['summary','date','when','t'])delete e[k];if(e.id==null)e.id='event-'+hash(words(e.title).join(' ')+'|'+e.start);return e},
  inbox(x){const m=Object.assign({},x);m.t=str(pick(x.t,x.subject,x.title),400).trim();m.sender=str(pick(x.sender,x.from,''),300);m.f=str(pick(x.f,x.account,'Mail'),80);m.b=str(pick(x.b,x.body,''),20000);if(x.gist==null&&m.b)m.gist=m.b.slice(0,200);if(!m.t)throw Error('Inbox item needs a subject (t or subject)');for(const k of ['subject','title','from','account','body'])delete m[k];if(m.id==null)m.id='inbox-'+hash(m.sender.toLowerCase()+'|'+words(m.t).join(' ')+'|'+str(x.date||x.receivedAt||'',30));return m},
  board(x){const t=str(pick(x.title,x.t),240).trim();if(!t)throw Error('Card needs a title');const c=typeof x.column==='number'?x.column:typeof x.c==='number'?x.c:Math.max(0,COLS.indexOf(x.column||'To do'));const b={id:pick(x.id),t,c};if(x.due)b.due=str(x.due,10);if(x.note)b.note=str(x.note,1500);if(b.id==null)b.id='card-'+hash(t.toLowerCase());return b},
  saved(x){const t=str(pick(x.title,x.t),240).trim();if(!t)throw Error('Saved item needs a title');const url=str(pick(x.url,''),2000);if(url&&!/^https?:\/\//i.test(url))throw Error('Links must start with http:// or https://');const s={id:pick(x.id),t,url,n:str(pick(x.note,x.n,''),1500),s:str(pick(x.source,x.s,'Import'),60)};if(s.id==null)s.id='saved-'+hash(url||t.toLowerCase());return s},
};
const where=kind=>({tasks:['state','tasks'],board:['state','board'],saved:['state','saved'],events:['content','events'],inbox:['content','inbox']})[kind];
const bare=x=>{if(!x||typeof x!=='object')return x;const{changedBy,changedAt,...r}=x;return r};
const same=(a,b)=>JSON.stringify(bare(a))===JSON.stringify(bare(b));
function addOp(kind,v){
  if(kind==='tasks')return{op:'task.add',...v};
  if(kind==='board')return{op:'board.add',id:v.id,title:v.t,column:v.c,due:v.due,note:v.note};
  if(kind==='saved')return{op:'saved.add',id:v.id,title:v.t,url:v.url,note:v.n,source:v.s};
  return{op:'content.put',path:kind,value:v};
}
function updateOp(kind,v){
  if(kind==='tasks')return{op:'task.update',id:v.id,title:v.title,note:v.note,due:v.due??null,priority:v.priority??null,src:v.src};
  if(kind==='board')return{op:'board.update',id:v.id,title:v.t,column:v.c,due:v.due??null,note:v.note??null};
  if(kind==='saved')return{op:'saved.update',id:v.id,title:v.t,url:v.url,note:v.n};
  return{op:'content.put',path:kind,value:v};
}

/* Turns an import (either {tasks,events,inbox,board,saved} lists or a whole exported doc) into ops,
   merging with what is already there. Same id = update, likely duplicate = skipped, bad item = failed. */
function planImport(doc,input){
  const d=normalize(doc);const lists={};let full=null;
  if(input&&input.doc&&typeof input.doc==='object'){full=normalize(input.doc);lists.tasks=full.state.tasks;lists.board=full.state.board;lists.saved=full.state.saved;lists.events=full.content.events||[];lists.inbox=full.content.inbox||[]}
  else for(const k of Object.keys(SHAPE))if(input&&input[k]!=null){if(!Array.isArray(input[k]))throw Object.assign(Error(k+' must be a list'),{status:400});lists[k]=input[k]}
  const ops=[],items=[],counts={};
  for(const[kind,list]of Object.entries(lists)){
    const c=counts[kind]={added:0,updated:0,unchanged:0,duplicate:0,failed:0};
    const[a,b]=where(kind);const existing=(d[a][b]||[]).filter(Boolean);const accepted=[];
    const shaped=list.map((x,index)=>{try{if(!x||typeof x!=='object')throw Error('Each item must be an object');return{index,v:SHAPE[kind](x),made:x.id==null}}catch(e){return{index,error:e.message}}});
    const mine=[];// reports of items this import adds, so a better copy later in the batch can take their place
    for(const s of shaped){
      const report={kind,index:s.index};
      if(s.error){c.failed++;items.push(Object.assign(report,{status:'failed',error:s.error}));continue}
      const v=s.v;report.id=v.id;report.title=v.title||v.t;
      const cur=existing.find(x=>String(x.id)===String(v.id));
      // an id made from the content that matches a different item is a near-duplicate, not an update
      if(cur&&s.made&&!same(cur,Object.assign({},cur,v))){c.duplicate++;items.push(Object.assign(report,{status:'duplicate',duplicateOf:cur.id,duplicateTitle:cur.title||cur.t}));continue}
      if(cur){if(same(cur,Object.assign({},cur,v))){c.unchanged++;report.status='unchanged'}else{c.updated++;report.status='updated';ops.push(updateOp(kind,kind==='events'||kind==='inbox'?Object.assign({},cur,v):v))}items.push(report);accepted.push(v);continue}
      if(accepted.some(x=>String(x.id)===String(v.id))){c.duplicate++;items.push(Object.assign(report,{status:'duplicate',duplicateOf:v.id,reason:'same id twice in this import'}));continue}
      const old=existing.filter(x=>kind!=='events'||isActive(x)||!isActive(v)).find(x=>SAME[kind](x,v));
      if(old){c.duplicate++;items.push(Object.assign(report,{status:'duplicate',duplicateOf:old.id,duplicateTitle:old.title||old.t}));continue}
      const twin=mine.find(m=>SAME[kind](m.v,v));
      if(twin&&kind==='events'&&score(v)>score(twin.v)){// the new copy is better (active, has a time): it replaces the earlier one
        ops.splice(ops.indexOf(twin.op),1);accepted.splice(accepted.indexOf(twin.v),1);mine.splice(mine.indexOf(twin),1);
        Object.assign(twin.report,{status:'duplicate',duplicateOf:v.id,duplicateTitle:v.title});c.added--;c.duplicate++;
      }else if(twin){c.duplicate++;items.push(Object.assign(report,{status:'duplicate',duplicateOf:twin.v.id,duplicateTitle:twin.v.title||twin.v.t}));continue}
      const op=addOp(kind,v);c.added++;report.status='added';items.push(report);accepted.push(v);ops.push(op);mine.push({v,op,report});
    }
  }
  items.sort((x,y)=>x.kind<y.kind?-1:x.kind>y.kind?1:x.index-y.index);
  if(full){
    const kept=[];
    // other content: arrays of items with ids merge by id; anything else is only filled in when missing here
    for(const[k,v]of Object.entries(full.content)){
      if(k==='events'||k==='inbox'||BAD.has(k))continue;
      const mine=d.content[k];
      if(Array.isArray(v)&&v.length&&v.every(x=>x&&typeof x==='object'&&x.id!=null)){
        const have=Array.isArray(mine)?mine:[];
        if(!Array.isArray(mine)&&mine!==undefined){kept.push(k);continue}
        for(const x of v){const cur=have.find(y=>String(y.id)===String(x.id));if(!cur||!same(cur,x))ops.push({op:'content.put',path:k,value:x})}
      }else if(mine===undefined||mine===null||(Array.isArray(mine)&&!mine.length)||(typeof mine==='object'&&!Array.isArray(mine)&&!Object.keys(mine).length))ops.push({op:'content.set',path:k,value:v});
      else if(!same(mine,v))kept.push(k);
    }
    const doneNow=new Set(d.state.done.map(String)),idoneNow=new Set(d.state.inboxDone.map(String));
    for(const id of full.state.done)if(!doneNow.has(String(id))&&!items.some(i=>i.kind==='tasks'&&i.status==='duplicate'&&String(i.id)===String(id)))ops.push({op:'task.done',id,done:true});
    for(const id of full.state.inboxDone)if(!idoneNow.has(String(id)))ops.push({op:'inbox.done',id,done:true});
    for(const m of MAPS)for(const[k,v]of Object.entries(full.state[m]||{}))if(!(k in d.state[m]))ops.push({op:'state.setKey',path:m,key:k,value:v});
    if(!d.state.timetable&&full.state.timetable)ops.push({op:'timetable.set',text:full.state.timetable});
    const fids=new Set(d.state.focus.map(f=>String(f.id)));for(const f of full.state.focus)if(f&&f.id!=null&&!fids.has(String(f.id))&&f.minutes>0&&f.minutes<=600)ops.push({op:'focus.log',id:f.id,date:f.date,minutes:f.minutes,label:f.label,at:f.at});
    const prof={};for(const[k,v]of Object.entries(full.profile||{}))if(!BAD.has(k)&&(d.profile[k]===undefined||d.profile[k]===''||(typeof d.profile[k]==='object'&&d.profile[k]&&!Array.isArray(d.profile[k])&&!Object.keys(d.profile[k]).length)))prof[k]=v;if(Object.keys(prof).length)ops.push({op:'profile.set',value:prof});
    const sets={};for(const[k,v]of Object.entries(full.settings||{}))if(!BAD.has(k)&&d.settings[k]===undefined)sets[k]=v;if(Object.keys(sets).length)ops.push({op:'settings.set',value:sets});
    return{ops,items,counts,kept};
  }
  return{ops,items,counts,kept:[]};
}
const plural=(n,w)=>n+' '+w+(n===1?'':'s');
function importSummary(counts,dryRun){
  const names={tasks:'task',events:'event',inbox:'inbox item',board:'board card',saved:'saved item'};
  // tasks, events and inbox are always named; other kinds only when something was added
  const add=Object.keys(names).filter(k=>counts[k]&&(['tasks','events','inbox'].includes(k)||counts[k].added)).map(k=>plural(counts[k].added,names[k]));
  const dup=Object.values(counts).reduce((n,c)=>n+c.duplicate,0),upd=Object.values(counts).reduce((n,c)=>n+c.updated,0),bad=Object.values(counts).reduce((n,c)=>n+c.failed,0);
  let s=(dryRun?'Would import ':'Imported ')+(add.length?add.join(', '):'nothing');
  if(upd)s+='; '+plural(upd,'item')+' updated';
  if(dup)s+='; '+plural(dup,'likely duplicate')+' skipped';
  if(bad)s+='; '+plural(bad,'item')+' failed';
  return s+'.';
}
/* Applies an import as one logged change that can be undone in one step. */
function runImport(doc,input,{by='Import',keyId,batch,dryRun=false}={}){
  const plan=planImport(doc,input);
  const summary=importSummary(plan.counts,dryRun);
  if(dryRun)return Object.assign({doc:normalize(doc),summary,changed:false},plan);
  let d=normalize(clone(doc));const undoOps=[];let failedOps=0;
  for(const op of plan.ops){const r=apply(d,Object.assign({by},op),{inPlace:true,batch,keyId,silent:true});d=r.doc;if(r.ok)undoOps.unshift(...(r.undo||[]));else failedOps++}
  if(plan.ops.length){const u=JSON.stringify(undoOps).length<=200000?undoOps:undefined;logEntry(d,{id:uid('log'),batch,op:'import',by:str(by,40),key:keyId,at:Date.now(),summary:str(summary,120),undo:u&&u.length?u:undefined})}
  return Object.assign({doc:d,summary,changed:plan.ops.length>0,failedOps},plan);
}

return{SCHEMA,OPS,COLS,MAPS,apply,applyAll,inverse,undo,normalize,uid,clone,duplicates,planImport,runImport,importSummary,alike};
})();
export default LifeOSCore;
