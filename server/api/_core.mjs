/* LifeOS core: the one reducer shared by the app and the sync server.
   Every change, from the app, Gemini, or your iMessage assistant, is an "op": {op:"task.add", ...fields}.
   apply(doc, op) returns the changed doc. Same input, same result, on phone and server. */
const LifeOSCore=(()=>{
const SCHEMA='lifeos/2';
const clone=x=>JSON.parse(JSON.stringify(x));
const uid=p=>(p||'id')+'-'+Date.now().toString(36)+Math.random().toString(36).slice(2,7);
const str=(v,max=4000)=>typeof v==='string'?v.slice(0,max):v==null?'':String(v).slice(0,max);
const BAD=new Set(['__proto__','prototype','constructor']);
const COLS=['To do','Doing','Done'];

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
  'task.add'(d,o,at){const t={id:o.id||uid('task'),title:str(o.title,240).trim(),note:str(o.note,1500),src:str(o.src||'You',60),created:at};if(o.due)t.due=str(o.due,10);if(o.priority)t.priority=str(o.priority,10);if(!t.title)throw Error('Task needs a title');if(byId(d.state.tasks,t.id)<0)d.state.tasks.push(t)},
  'task.update'(d,o){const i=byId(d.state.tasks,o.id);if(i<0)throw Error('No such task');patch(d.state.tasks[i],o,['title','note','due','src','priority'])},
  'task.done'(d,o){const id=String(o.id),set=new Set(d.state.done.map(String));o.done===false?set.delete(id):set.add(id);d.state.done=[...set]},
  'task.remove'(d,o){d.state.tasks=d.state.tasks.filter(t=>String(t.id)!==String(o.id));d.state.done=d.state.done.filter(x=>String(x)!==String(o.id));if(!d.state.deletedTasks.includes(String(o.id)))d.state.deletedTasks.push(String(o.id))},

  'board.add'(d,o,at){const c=typeof o.column==='number'?o.column:Math.max(0,COLS.indexOf(o.column||'To do'));const b={id:o.id||uid('card'),t:str(o.title??o.t,240).trim(),c,created:at};if(o.due)b.due=str(o.due,10);if(o.filed===false)b.filed=false;if(o.note)b.note=str(o.note,1500);if(!b.t)throw Error('Card needs a title');if(byId(d.state.board,b.id)<0)d.state.board.push(b)},
  'board.update'(d,o){const i=byId(d.state.board,o.id);if(i<0)throw Error('No such card');const b=d.state.board[i];if(o.title!==undefined)b.t=str(o.title,240);patch(b,o,['due','note','filed']);if(o.column!==undefined)H['board.move'](d,o)},
  'board.move'(d,o){const b=d.state.board.find(x=>String(x.id)===String(o.id));if(!b)throw Error('No such card');const c=typeof o.column==='number'?o.column:COLS.indexOf(o.column);if(c<0||c>2)throw Error('Column must be To do, Doing or Done');b.c=c;if(c>0)b.filed=undefined},
  'board.remove'(d,o){d.state.board=d.state.board.filter(x=>String(x.id)!==String(o.id))},

  'saved.add'(d,o,at){const url=str(o.url,2000).trim();if(url&&!/^https?:\/\//i.test(url))throw Error('Links must start with http:// or https://');const s={id:o.id||uid('saved'),t:str(o.title??o.t,240).trim(),url,n:str(o.note??o.n,1500),s:str(o.source??o.s??'You',60),c:at};if(!s.t)throw Error('Saved item needs a title');if(byId(d.state.saved,s.id)<0)d.state.saved.unshift(s)},
  'saved.update'(d,o){const i=byId(d.state.saved,o.id);if(i<0)throw Error('No such item');const s=d.state.saved[i];if(o.title!==undefined)s.t=str(o.title,240);if(o.url!==undefined){if(o.url&&!/^https?:\/\//i.test(o.url))throw Error('Links must start with http:// or https://');s.url=str(o.url,2000)}if(o.note!==undefined)s.n=str(o.note,1500)},
  'saved.remove'(d,o){d.state.saved=d.state.saved.filter(x=>String(x.id)!==String(o.id))},

  'inbox.done'(d,o){const id=String(o.id),set=new Set(d.state.inboxDone.map(String));o.done===false?set.delete(id):set.add(id);d.state.inboxDone=[...set]},
  'inbox.priority'(d,o){if(o.value)d.state.priority[o.id]=str(o.value,10);else delete d.state.priority[o.id]},
  'inbox.snooze'(d,o){if(o.until||o.on)d.state.snooze[o.id]=o.until||true;else delete d.state.snooze[o.id]},

  'progress.set'(d,o){d.state.progress[o.id]={done:!!o.done,label:str(o.label,300),at:o.at||Date.now()}},
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
  'content.set'(d,o){const[p,k]=path(d.content,o.path,true);if(!p)throw Error('Bad path');p[k]=clone(o.value)},
  'content.merge'(d,o){const[p,k]=path(d.content,o.path,true);if(!p)throw Error('Bad path');p[k]=Object.assign(p[k]&&typeof p[k]==='object'?p[k]:{},clone(o.value))},
  'content.push'(d,o){const[p,k]=path(d.content,o.path,true);if(!Array.isArray(p[k]))p[k]=[];p[k].push(clone(o.value))},
  'content.upsert'(d,o){const[p,k]=path(d.content,o.path,true);if(!Array.isArray(p[k]))p[k]=[];const v=clone(o.value);if(v.id==null)throw Error('content.upsert needs value.id');const i=byId(p[k],v.id);i<0?p[k].push(v):p[k][i]=Object.assign(p[k][i],v)},
  'content.remove'(d,o){const[p,k]=path(d.content,o.path,false);if(p&&Array.isArray(p[k]))p[k]=p[k].filter(x=>!x||String(x.id)!==String(o.id));else if(p&&o.id==null)delete p[k]},
  'state.set'(d,o){const[p,k]=path(d.state,o.path,true);if(!p)throw Error('Bad path');p[k]=clone(o.value)},
  'profile.set'(d,o){const v=clone(o.value||{});for(const k of Object.keys(v))if(!BAD.has(k))d.profile[k]=v[k]},
  'settings.set'(d,o){const v=clone(o.value||{});for(const k of Object.keys(v))if(!BAD.has(k))d.settings[k]=(v[k]&&typeof v[k]==='object'&&!Array.isArray(v[k]))?Object.assign({},d.settings[k]||{},v[k]):v[k]},
};
const OPS=Object.keys(H);

/* Apply one op. Returns {doc, ok, error}. Never throws. Ops carrying an opId already applied are skipped. */
function apply(doc,op,opts={}){
  const d=normalize(opts.inPlace?doc:clone(doc));
  try{
    if(!op||typeof op.op!=='string'||!H[op.op])throw Error('Unknown op '+(op&&op.op));
    if(op.opId&&d.applied.includes(op.opId))return{doc:d,ok:true,skipped:true};
    const at=op.at||Date.now();
    H[op.op](d,op,at);
    if(op.opId)d.applied.push(op.opId);
    if(d.applied.length>400)d.applied=d.applied.slice(-400);
    d.state.log.unshift({op:op.op,by:str(op.by||'app',40),at,summary:str(op.title||op.text||op.path||op.id||'',120)});
    if(d.state.log.length>60)d.state.log.length=60;
    return{doc:d,ok:true};
  }catch(e){return{doc:d,ok:false,error:e.message}}
}
function applyAll(doc,ops,opts){let d=normalize(clone(doc));const results=[];for(const op of ops||[]){const r=apply(d,op,{inPlace:true});d=r.doc;results.push({op:op&&op.op,ok:r.ok,error:r.error,skipped:r.skipped})}return{doc:d,results}}
return{SCHEMA,OPS,COLS,apply,applyAll,normalize,uid,clone};
})();
export default LifeOSCore;
