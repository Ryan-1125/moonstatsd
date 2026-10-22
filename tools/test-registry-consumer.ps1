param([switch]$SkipUpdate)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$app = Join-Path $projectRoot ('.local/registry-consumer-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $app | Out-Null
# No workspace override or path dependency: resolve the published registry module.
@'
name = "local/moonstatsd-registry-check"
preferred_target = "native"
import { "Ryan-1125/moonstatsd@0.2.0", "moonbitlang/async@0.20.0" }
'@ | Set-Content (Join-Path $app 'moon.mod')
@'
import { "Ryan-1125/moonstatsd" @statsd, "Ryan-1125/moonstatsd/client", "moonbitlang/async", "moonbitlang/async/socket" }
pkgtype(kind: "executable")
'@ | Set-Content (Join-Path $app 'moon.pkg')
@'
///|
async fn main {
  let message = @statsd.encode("requests", Counter(1.0))
  assert_eq(message.bytes(), b"requests:1|c")
  let datagrams = @statsd.pack([message], max_bytes=512)
  assert_eq(datagrams.length(), 1)
  let receiver = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer receiver.close()
  @async.with_timeout(2000, () => @client.with_client(receiver.addr, client => {
    ignore(client.record("requests", Counter(1.0), tags=["route:home"]))
    ignore(client.record("latency", Timer(12.5)))
    ignore(client.record("queue", Gauge(7.0)))
    let report = client.flush()
    assert_eq(report.submitted, 3L)
    assert_eq(report.send_errors, 0L)
    let buffer = FixedArray::make(512, b'\x00')
    let (n, _) = receiver.recvfrom(buffer)
    assert_eq(Bytes::from_array(buffer[:n].to_owned()),
      b"service.requests:1|c|#env:dev,route:home\nservice.latency:12.5|ms|#env:dev\nservice.queue:7|g|#env:dev")
    let jobs = client.scope(prefix="jobs.", tags=["team:worker"])
    let mut now = 10UL
    let timer = jobs.start_timer("duration", clock=() => now)
    now = 15UL
    ignore(timer.stop())
    assert_eq(client.flush().submitted, 4L)
    let (n, _) = receiver.recvfrom(buffer)
    assert_eq(Bytes::from_array(buffer[:n].to_owned()), b"service.jobs.duration:5|ms|#env:dev,team:worker")
  }, mode=DogStatsD, prefix="service.", fixed_tags=["env:dev"]))
  println("Registry 0.2.0 consumer: codec, packing, scopes, timers and real DogStatsD UDP passed")
}
'@ | Set-Content (Join-Path $app 'main.mbt')
Push-Location $app
try {
  if (-not $SkipUpdate) {
    & moon update
    if ($LASTEXITCODE -ne 0) { throw 'registry update failed' }
  }
  & moon run . --target native
  if ($LASTEXITCODE -ne 0) { throw 'registry consumer failed' }
  Write-Output "Registry consumer sources: $app"
} finally { Pop-Location }
