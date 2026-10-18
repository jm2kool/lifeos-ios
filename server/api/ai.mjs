// Gemini proxy so your API key stays on the server. Env: GEMINI_API_KEY, LIFEOS_TOKEN.
import {who} from './lifeos.mjs';
export default async function handler(req,res){
  res.setHeader('Cache-Control','no-store');
  if(req.method!=='POST')return res.status(405).json({error:'POST only'});
  if(!process.env.GEMINI_API_KEY)return res.status(503).json({error:'Add GEMINI_API_KEY in Vercel to use Gemini through the server'});
  if(who(req)!=='app'&&who(req)!=='agent')return res.status(401).json({error:'Add your sync key in Settings'});
  const b=typeof req.body==='object'?req.body:JSON.parse(req.body||'{}');
  const model=String(b.model||'gemini-3.8-flash');
  if(!/^[a-z0-9.\-]{3,60}$/.test(model))return res.status(400).json({error:'Bad model name'});
  if(!b.body||JSON.stringify(b.body).length>200000)return res.status(400).json({error:'Bad request'});
  try{
    const r=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,{method:'POST',headers:{'Content-Type':'application/json','x-goog-api-key':process.env.GEMINI_API_KEY},body:JSON.stringify(b.body),signal:AbortSignal.timeout(45000)});
    const j=await r.json().catch(()=>({}));return res.status(r.status).json(j);
  }catch{return res.status(504).json({error:'Gemini did not respond'})}
}
