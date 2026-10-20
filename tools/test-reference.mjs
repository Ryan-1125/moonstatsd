import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {mkdirSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const root=process.cwd();
mkdirSync('.local/evidence',{recursive:true});
function run(file,args,cwd){const r=spawnSync(file,args,{cwd,encoding:'utf8',windowsHide:true,timeout:120000,env:{...process.env,GOCACHE:resolve('.local/go-cache'),GOMODCACHE:resolve('.local/go-modules')}}); assert.equal(r.status,0,String(r.error||r.stderr));return r.stdout;}
const go=process.env.GO_EXE||'go';
run(go,['mod','download'],resolve('tools/reference-client'));
const reference=run(go,['run','-mod=mod','.'],resolve('tools/reference-client'));
const moon=run('moon',['run','cmd/wire','--target','native'],root);
writeFileSync('.local/evidence/reference-wire.txt',reference);
writeFileSync('.local/evidence/moon-wire.txt',moon);
function normalize(wire){return wire.trim().split(/\r?\n/).filter(Boolean).map(line=>{const [head,type,...ext]=line.split('|');const colon=head.indexOf(':');assert.ok(ext.every(s=>s.startsWith('#')), 'unexpected wire extension');assert.ok(type==='s'||Number.isFinite(Number(head.slice(colon+1))), 'non-finite wire number');return {name:head.slice(0,colon),value:type==='s'?head.slice(colon+1):Number(head.slice(colon+1)),type,tags:ext.filter(s=>s.startsWith('#')).flatMap(s=>s.slice(1).split(',')).sort()}}).sort((a,b)=>a.name.localeCompare(b.name));}
assert.equal(normalize(reference).length,6);
assert.deepEqual(normalize(moon),normalize(reference));
console.log('datadog-go v5.8.3: 6 wire cases semantically equal (timer decimal formatting normalized)');
