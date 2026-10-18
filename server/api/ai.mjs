// Gemini proxy so your API key stays on the server. Env: GEMINI_API_KEY, LIFEOS_TOKEN.
import {who} from './lifeos.mjs';
export default async function handler(req,res){
  res.setHeader('Cache-Control','no-store');
  if(req.method==='GET'){ // health check: GET /api/ai?key=...  -> is the Gemini key working, which models exist
    const q=req.query||{};if(q.key&&!req.headers.authorization)req.headers.authorization='Bearer '+q.key;
    if(!who(req))return res.status(401).json({error:'Missing or wrong key'});
    const k={'x-goog-api-key':process.env.GEMINI_API_KEY||''},out={};
    try{const t=Date.now();const r=await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200',{headers:k,signal:AbortSignal.timeout(15000)});const j=await r.json().catch(()=>({}));out.list={status:r.status,ms:Date.now()-t,error:j.error?.message,flash:(j.models||[]).map(m=>m.name.replace('models/','')).filter(n=>/flash/.test(n))}}catch(e){out.list={error:String(e.message)}}
    const m=String(q.model||process.env.GEMINI_MODEL||'gemini-3.5-flash');
    try{const t=Date.now();const r=await fetch('https://generativelanguage.googleapis.com/v1beta/models/'+m+':generateContent',{method:'POST',headers:{...k,'Content-Type':'application/json'},body:JSON.stringify({contents:[{role:'user',parts:[{text:'Reply with the word ok'}]}],...(/^gemini-3/.test(m)&&q.think!=='default'?{generationConfig:{thinkingConfig:{thinkingLevel:'low'}}}:{})}),signal:AbortSignal.timeout(40000)});const j=await r.json().catch(()=>({}));out.generate={model:m,status:r.status,ms:Date.now()-t,error:j.error?.message,text:(j.candidates?.[0]?.content?.parts||[]).map(p=>p.text||'').join('').slice(0,80)}}catch(e){out.generate={model:m,error:String(e.message)}}
    return res.status(200).json(out);
  }
  if(req.method!=='POST')return res.status(405).json({error:'POST only'});
  if(!process.env.GEMINI_API_KEY)return res.status(503).json({error:'Add GEMINI_API_KEY in Vercel to use Gemini through the server'});
  if(who(req)!=='app'&&who(req)!=='agent')return res.status(401).json({error:'Add your sync key in Settings'});
  const b=typeof req.body==='object'?req.body:JSON.parse(req.body||'{}');
  const model=String(b.model||'gemini-3.5-flash');
  if(!/^[a-z0-9.\-]{3,60}$/.test(model))return res.status(400).json({error:'Bad model name'});
  if(!b.body||JSON.stringify(b.body).length>200000)return res.status(400).json({error:'Bad request'});
  try{
    const r=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,{method:'POST',headers:{'Content-Type':'application/json','x-goog-api-key':process.env.GEMINI_API_KEY},body:JSON.stringify(b.body),signal:AbortSignal.timeout(45000)});
    const j=await r.json().catch(()=>({}));return res.status(r.status).json(j);
  }catch{return res.status(504).json({error:'Gemini did not respond'})}
}
