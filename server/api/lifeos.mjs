// LifeOS sync + agent endpoint (Vercel Node function).
// The phone and your iMessage assistant both talk to this. Storage: Upstash Redis (Vercel Marketplace).
// Env: LIFEOS_TOKEN (phone), LIFEOS_AGENT_TOKEN (assistant, optional), KV_REST_API_URL + KV_REST_API_TOKEN
//      (or UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN).
import Core from './_core.mjs';
import {readFileSync} from 'node:fs';
import {timingSafeEqual} from 'node:crypto';

const KEY='lifeos:doc';
const env=process.env;
const kvUrl=()=>env.KV_REST_API_URL||env.UPSTASH_REDIS_REST_URL;
const kvTok=()=>env.KV_REST_API_TOKEN||env.UPSTASH_REDIS_REST_TOKEN;

// Works with either Upstash (REST) or a plain Redis URL (Vercel's Redis store).
let conn=null;
function redis(){if(!conn)conn=import('redis').then(async({createClient})=>{const c=createClient({url:env.REDIS_URL,socket:{connectTimeout:8000}});c.on('error',()=>{});await c.connect();return c}).catch(e=>{conn=null;throw e});return conn}
export const hasStore=()=>!!(env.REDIS_URL||(kvUrl()&&kvTok()));
export async function kv(cmd,fetcher=fetch){
  if(!kvUrl()&&env.REDIS_URL){const c=await redis();return c.sendCommand(cmd.map(String))}
  if(!hasStore())throw Object.assign(Error('Storage is not connected yet: add a Redis store to this Vercel project'),{status:503});
  const r=await fetcher(kvUrl(),{method:'POST',headers:{Authorization:'Bearer '+kvTok(),'Content-Type':'application/json'},body:JSON.stringify(cmd)});
  const j=await r.json().catch(()=>({}));if(!r.ok||j.error)throw Error(j.error||'Storage error '+r.status);return j.result;
}
function seedDoc(){try{return JSON.parse(readFileSync(new URL('./_seed.json',import.meta.url),'utf8'))}catch{return Core.normalize({})}} // optional private seed; not committed
const same=(a,b)=>{const x=Buffer.from(String(a||'')),y=Buffer.from(String(b||''));return x.length===y.length&&x.length>0&&timingSafeEqual(x,y)};
export function who(req){
  const t=/^Bearer\s+(\S+)$/.exec(req.headers.authorization||'')?.[1];
  if(!t)return null;
  if(same(t,env.LIFEOS_AGENT_TOKEN))return'agent';
  if(same(t,env.LIFEOS_TOKEN))return'app';
  return null;
}
async function body(req){if(req.body&&typeof req.body==='object')return req.body;if(typeof req.body==='string')return JSON.parse(req.body||'{}');let s='';for await(const c of req)s+=c;return s?JSON.parse(s):{}}
export async function load(store=kv){const raw=await store(['GET',KEY]);if(raw)return Core.normalize(JSON.parse(raw));const d=Core.normalize(seedDoc());d.rev=Math.max(1,d.rev||1);d.updatedAt=new Date().toISOString();d.updatedBy='seed';await store(['SET',KEY,JSON.stringify(d)]);return d}
export const save=(store,d)=>store(['SET',KEY,JSON.stringify(d)]);
export async function commit(store,ops,by){const d=await load(store);const list=ops.map(o=>Object.assign({by},o,{opId:o.opId||Core.uid('srv')}));const r=Core.applyAll(d,list);if(r.results.some(x=>x.ok&&!x.skipped)){r.doc.rev=(d.rev||0)+1;r.doc.updatedAt=new Date().toISOString();r.doc.updatedBy=by;await save(store,r.doc)}return r}

export function summary(d){
  const s=d.state,c=d.content,tz=d.profile.timezone||'UTC';
  const day=new Intl.DateTimeFormat('en-CA',{timeZone:tz}).format(new Date());
  const done=new Set((s.done||[]).map(String)),idone=new Set((s.inboxDone||[]).map(String));
  const ev=(c.events||[]).filter(e=>e.status!=='superseded'&&!/^(Paused|Superseded|Removed)/i.test(e.note||'')).filter(e=>String(e.end||e.start)>=day).slice(0,15);
  const L=[`LifeOS for ${d.profile.name||'owner'} · ${day} (${tz}) · rev ${d.rev}`,'',
    'Open tasks:',...(s.tasks||[]).filter(t=>!done.has(String(t.id))).map(t=>`- [${t.id}] ${t.title}${t.due?' (due '+t.due+')':''}`),'',
    'Board:',...(s.board||[]).map(b=>`- [${b.id}] ${['To do','Doing','Done'][b.c]}: ${b.t}${b.due?' (due '+b.due+')':''}`),'',
    'Upcoming events:',...ev.map(e=>`- ${e.start}: ${e.title}`),'',
    'Inbox to review:',...(c.inbox||[]).filter(m=>!idone.has(String(m.id))).map(m=>`- [${m.id}] ${m.t} (${m.f})`),'',
    'Draft reviews:',...Object.values(s.draftReviews||{}).map(r=>`- ${r.draftId} v${r.version} ${r.week}: ${r.action}${r.changes?' — '+r.changes:''}`),'',
    'Recent changes:',...(s.log||[]).slice(0,10).map(l=>`- ${new Date(l.at).toISOString()} ${l.by}: ${l.op} ${l.summary||''}`)];
  return L.join('\n');
}

export function createHandler({store=kv}={}){return async function handler(req,res){
  res.setHeader('Cache-Control','no-store');
  res.setHeader('Access-Control-Allow-Origin','*');res.setHeader('Access-Control-Allow-Headers','Authorization, Content-Type');res.setHeader('Access-Control-Allow-Methods','GET, POST, PUT, OPTIONS');
  if(req.method==='OPTIONS')return res.status(204).end();
  if(!env.LIFEOS_TOKEN)return res.status(503).json({error:'Sync is not set up: add LIFEOS_TOKEN in Vercel'});
  if(!hasStore())return res.status(503).json({error:'Sync is not set up: connect a Redis store in Vercel'});
  const qk=(req.query||Object.fromEntries(new URL(req.url,'http://x').searchParams)).key;
  if(qk&&!req.headers.authorization)req.headers.authorization='Bearer '+qk;
  const role=who(req);if(!role)return res.status(401).json({error:'Missing or wrong token'});
  try{
    if(req.method==='GET'){
      const d=await load(store);const q=req.query||Object.fromEntries(new URL(req.url,'http://x').searchParams);
      if(q.view==='summary'){res.setHeader('Content-Type','text/plain; charset=utf-8');return res.status(200).send(summary(d))}
      if(q.view==='ops')return res.status(200).json({ops:Core.OPS});
      if(q.since!=null&&Number(q.since)===d.rev)return res.status(200).json({unchanged:true,rev:d.rev});
      return res.status(200).json({doc:d});
    }
    const b=await body(req);
    if(req.method==='POST'){
      if(!Array.isArray(b.ops)||!b.ops.length||b.ops.length>200)return res.status(400).json({error:'Send {"ops":[...]} with 1-200 ops'});
      if(JSON.stringify(b).length>900000)return res.status(413).json({error:'Too large'});
      const by=String(b.by||(role==='agent'?'agent':'app')).slice(0,40);
      const d=await load(store);
      const ops=b.ops.map(o=>Object.assign({by},o,{opId:o.opId||Core.uid('srv')}));
      const r=Core.applyAll(d,ops);
      const changed=r.results.some(x=>x.ok&&!x.skipped);
      if(changed){r.doc.rev=(d.rev||0)+1;r.doc.updatedAt=new Date().toISOString();r.doc.updatedBy=by;await save(store,r.doc)}
      return res.status(r.results.every(x=>x.ok)?200:207).json({doc:r.doc,results:r.results});
    }
    if(req.method==='PUT'){
      if(!b.doc||typeof b.doc!=='object'||!b.doc.content||!b.doc.state)return res.status(400).json({error:'Send {"doc":{...}} with content and state'});
      const old=await load(store);const d=Core.normalize(b.doc);d.rev=(old.rev||0)+1;d.updatedAt=new Date().toISOString();d.updatedBy=String(b.by||role);
      await save(store,d);return res.status(200).json({doc:d});
    }
    return res.status(405).json({error:'Use GET, POST or PUT'});
  }catch(e){return res.status(500).json({error:e.message||'Server error'})}
}}
export default createHandler();
