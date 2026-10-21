// Real official DogStatsD parser/aggregator/forwarder, with an HTTP output sink.
// The sink only decodes Agent v1 JSON output; it does not interpret StatsD input.
import {spawnSync} from 'node:child_process';
import {mkdirSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import http from 'node:http';
import {inflateSync, gunzipSync} from 'node:zlib';
import assert from 'node:assert/strict';
assert.equal(process.platform, 'linux', 'Real Agent integration requires Linux Docker; no mock fallback');
const image='datadog/dogstatsd@sha256:e4cbd4b82011b3dec10d7598e51d766e5a4ba9d4fe372f54197daeccb27529ee';
const suffix=`${process.pid}-${Date.now()}`;
const network=`moonstatsd-agent-${suffix}`;
const container=`moonstatsd-agent-${suffix}`;
const dir=resolve('.local/evidence/agent');
mkdirSync(dir,{recursive:true});
let commandLog='';
function docker(args, required=true){
  const r=spawnSync('docker',args,{encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024});
  commandLog+=`> docker ${args.join(' ')}\n${r.stdout||''}${r.stderr||''}exit=${r.status}\n`;
  if(required)assert.equal(r.status,0,String(r.error||r.stderr));
  return r.stdout||'';
}
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function until(f, attempts=180){
  for(let i=0;i<attempts;i++){const value=await f();if(value)return value;await pause(500);}
  throw Error('Real DogStatsD output did not satisfy assertions before deadline');
}
const series=[];
const requests=[];
const intakeErrors=[];
const intake=http.createServer(async(req,res)=>{
  try {
    const parts=[];let size=0;
    for await(const part of req){size+=part.length;if(size>2*1024*1024)throw Error('intake request exceeds limit');parts.push(part);}
    const raw=Buffer.concat(parts);
    const path=new URL(req.url,'http://localhost').pathname;
    requests.push({path,encoding:req.headers['content-encoding']||'',bytes:raw.length});
    if(path==='/api/v1/series'){
      const encoding=req.headers['content-encoding'];
      const decoded=encoding==='deflate'?inflateSync(raw,{maxOutputLength:8*1024*1024}):encoding==='gzip'?gunzipSync(raw,{maxOutputLength:8*1024*1024}):raw;
      const body=JSON.parse(decoded.toString('utf8'));
      assert.ok(Array.isArray(body.series),'Agent must emit actual v1 JSON series');
      series.push(...body.series);
    }
    res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({valid:true}));
  } catch(e){intakeErrors.push(String(e));res.writeHead(400);res.end('invalid test intake payload');}
});
let networkCreated=false;
let started=false;
try {
  await new Promise((ok,bad)=>{intake.once('error',bad);intake.listen(19129,'0.0.0.0',ok);});
  docker(['version']);
  docker(['pull',image]);
  writeFileSync(resolve(dir,'image.json'),docker(['image','inspect',image]));
  docker(['network','create','--internal',network]);networkCreated=true;
  const meta=JSON.parse(docker(['network','inspect',network]));
  const gateway=meta[0].IPAM.Config[0].Gateway;
  assert.match(gateway,/^\d+\.\d+\.\d+\.\d+$/);
  const config=resolve('.local/agent-runtime.yaml');
  writeFileSync(config, `health_port: 5555\nenable_gohai: false\ndogstatsd_socket: ""\ndogstatsd_port: 8125\nbind_host: 0.0.0.0\ndogstatsd_non_local_traffic: true\n`);
  docker(['run','-d','--rm','--name',container,'--network',network,
    '-v',`${config}:/etc/datadog-agent/dogstatsd.yaml:ro`,
    '-e','DD_API_KEY=00000000000000000000000000000000',
    '-e',`DD_DD_URL=http://${gateway}:19129`,
    '-e','DD_HOSTNAME=moonstatsd-integration',
    '-e','DD_USE_V2_API_SERIES=false',
    '-e','DD_SERIALIZER_COMPRESSOR_KIND=zlib',
    '-e','DD_ENABLE_PAYLOADS_SKETCHES=false',
    '-e','DD_LOG_LEVEL=warn',image]);started=true;
  const address=JSON.parse(docker(['inspect',container]))[0].NetworkSettings.Networks[network].IPAddress;
  assert.match(address,/^\d+\.\d+\.\d+\.\d+$/);
  const version=docker(['exec',container,'/dogstatsd','version']);
  assert.match(version,/7\.60\.0/);writeFileSync(resolve(dir,'version.txt'),version);
  await until(()=>{
    const result=spawnSync('docker',['exec',container,'/probe.sh'],{encoding:'utf8',timeout:10000});
    return result.status===0;
  },60);
  await until(()=>{
    const sockets=docker(['exec',container,'cat','/proc/net/udp','/proc/net/udp6'],false);
    writeFileSync(resolve(dir,'udp-listeners.txt'),sockets);
    return /^\s*\d+:\s+[A-F0-9]+:1FBD\s/im.test(sockets);
  },60);
  const workload=spawnSync('moon',['run','cmd/agent','--target','native'],{encoding:'utf8',timeout:60000,env:{...process.env,MOONSTATSD_ADDR:`${address}:8125`}});
  writeFileSync(resolve(dir,'workload.log'),(workload.stdout||'')+(workload.stderr||''));
  assert.equal(workload.status,0,String(workload.error||workload.stderr));
  const sample=(name,predicate)=>series.find(s=>s.metric===name && predicate(s));
  const hasValue=(s,v)=>s.points?.some(p=>Math.abs(p[1]-v)<1e-9);
  const counter=s=>s.type==='rate' && s.interval>0 && s.points?.some(p=>Math.abs(p[1]*s.interval-4)<1e-9);
  const selected=await until(()=>{
    assert.deepEqual(intakeErrors,[]);
    const found=[sample('moonagent.count',counter),sample('moonagent.queue',s=>hasValue(s,7)),sample('moonagent.timer.avg',s=>hasValue(s,250)),sample('moonagent.payload.avg',s=>hasValue(s,42)),sample('moonagent.unique',s=>hasValue(s,2))];
    return found.every(Boolean)&&found;
  });
  for(const item of selected){for(const tag of ['env:test','service:demo','route:home'])assert.ok(item.tags.includes(tag),`${item.metric} missing ${tag}`);}
  writeFileSync(resolve(dir,'asserted-series.json'),JSON.stringify(selected,null,2));
  console.log('Official DogStatsD Agent 7.60.0: sampled count=4, gauge=7, timer.avg=250ms, histogram.avg=42, set=2; tags verified');
} finally {
  if(started){writeFileSync(resolve(dir,'agent.log'),docker(['logs',container],false));docker(['rm','-f',container],false);}
  if(networkCreated)docker(['network','rm',network],false);
  writeFileSync(resolve(dir,'requests.json'),JSON.stringify(requests,null,2));
  writeFileSync(resolve(dir,'series.json'),JSON.stringify(series,null,2));
  writeFileSync(resolve(dir,'intake-errors.json'),JSON.stringify(intakeErrors,null,2));
  writeFileSync(resolve(dir,'commands.log'),commandLog);
  await new Promise(ok=>intake.close(ok));
}
