import {spawn, spawnSync} from 'node:child_process';
import {mkdirSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import net from 'node:net';
import dgram from 'node:dgram';
import assert from 'node:assert/strict';
const root = process.cwd();
const evidence = resolve('.local/evidence');
mkdirSync(evidence, {recursive:true});
const win = process.platform === 'win32';
const exporter = resolve(process.env.STATSD_EXPORTER || `.local/tools/statsd_exporter-0.28.0.${win?'windows':'linux'}-amd64/statsd_exporter${win?'.exe':''}`);
const statsd = resolve(process.env.STATSD_SOURCE || '.local/tools/statsd-0.9.0/stats.js');
const delay = ms => new Promise(r=>setTimeout(r,ms));
function launch(file,args,name) {
  const p=spawn(file,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let log='';
  p.stdout.on('data',b=>{log+=b}); p.stderr.on('data',b=>{log+=b});
  p.on('error',e=>{log+=String(e)});
  return {p,log:()=>log,save:()=>writeFileSync(resolve(evidence,name+'.log'),log)};
}
async function until(f) {
  let last;
  for(let i=0;i<100;i++){try {const v=await f(); if(v)return v;}catch(e){last=e} await delay(50);}
  throw new Error('condition timed out', {cause:last});
}
function run(pkg,addr){
  const r=spawnSync('moon',['run',pkg,'--target','native'],{cwd:root,env:{...process.env,MOONSTATSD_ADDR:addr},encoding:'utf8',windowsHide:true,timeout:30000});
  writeFileSync(resolve(evidence,pkg.replaceAll('/','-')+'.log'),(r.stdout||'')+(r.stderr||''));
  assert.equal(r.status,0,String(r.error||r.stderr));
  console.log(r.stdout.trim());
}
async function stop(c){
  if(c.p.exitCode===null && !c.p.killed){c.p.kill(); await Promise.race([new Promise(r=>c.p.once('exit',r)),delay(1000)]);}
  c.save();
}
// Check ports before launch so a pre-existing collector cannot satisfy this test.
async function free(port){await new Promise((ok,bad)=>{const s=net.createServer();s.once('error',bad);s.listen(port,'127.0.0.1',()=>s.close(ok));});}
await free(19102); await free(19127);
async function freeUdp(port){await new Promise((ok,bad)=>{const s=dgram.createSocket('udp4');s.once('error',e=>{s.close();bad(e)});s.bind(port,'127.0.0.1',()=>s.close(ok));});}
await freeUdp(19125); await freeUdp(19126);
const exp=launch(exporter,['--web.listen-address=127.0.0.1:19102','--statsd.listen-udp=127.0.0.1:19125','--statsd.listen-tcp='],'exporter');
try {
  await until(async()=>{if(exp.p.exitCode!==null)throw Error(exp.log());return (await fetch('http://127.0.0.1:19102/metrics')).ok});
  run('cmd/main','127.0.0.1:19125');
  const expected=[
    'moon_requests{env="test",route="home",service="demo",status="200"} 2',
    'moon_queue{env="test",service="demo"} 7',
    'moon_active{env="test",service="demo"} 2',
    'moon_latency_sum{env="test",route="home",service="demo"} 0.25',
    'moon_latency_count{env="test",route="home",service="demo"} 1',
    'moon_jobs{env="test",result="success",service="demo"} 1',
    'moon_job_time_sum{env="test",service="demo"} 1.5',
    'moon_payload_sum{env="test",service="demo"} 42',
    'moon_payload_count{env="test",service="demo"} 1',
    'moon_distribution_sum{env="test",service="demo"} 5',
    'moon_distribution_count{env="test",service="demo"} 1',
    'statsd_exporter_lines_total 9',
  ];
  const text=await until(async()=>{const t=await (await fetch('http://127.0.0.1:19102/metrics')).text();return expected.every(line=>t.split('\n').includes(line)) && t});
  writeFileSync(resolve(evidence,'exporter-metrics.txt'),text);
  console.log('statsd_exporter v0.28.0: 12 collector assertions passed');
} finally {await stop(exp)}
const config=resolve('.local/statsd-test-config.json');
writeFileSync(config,JSON.stringify({port:19126,address:'127.0.0.1',mgmt_port:19127,mgmt_address:'127.0.0.1',flushInterval:1000,backends:[resolve('tools/statsd-json-backend.cjs')],automaticConfigReload:false,deleteCounters:true,deleteTimers:true,deleteSets:true}));
const upstream=launch(process.execPath,[statsd,config],'statsd');
try {
  await until(()=>new Promise(ok=>{const s=net.connect(19127,'127.0.0.1');s.once('connect',()=>{s.end();ok(true)});s.once('error',()=>{s.destroy();ok(false)})}));
  run('cmd/statsd','127.0.0.1:19126');
  const metrics=await until(()=>{
    for(const line of upstream.log().split('\n')) {
      if(!line.startsWith('MOONSTATSD_JSON='))continue;
      const m=JSON.parse(line.slice('MOONSTATSD_JSON='.length));
      if(m.counters['plain.count']===4 && m.gauges['plain.queue']===7 && m.sets['plain.unique']?.length===2)return m;
    }
  });
  assert.deepEqual([...metrics.sets['plain.unique']].sort(),['alice','bob']);
  assert.deepEqual(metrics.timers['plain.time'],[250]);
  writeFileSync(resolve(evidence,'statsd-metrics.json'),JSON.stringify(metrics,null,2));
  console.log('StatsD v0.9.0: sampled counter=4, gauge=7, timer=250ms, unique set=2');
} finally {await stop(upstream)}
