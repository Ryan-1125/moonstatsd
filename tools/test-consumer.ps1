param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
  & moon package
  if ($LASTEXITCODE -ne 0) { throw 'moon package failed' }
  $archive = Join-Path $projectRoot '_build/publish/Ryan-1125-moonstatsd-0.1.0.zip'
  $consumerRoot = Join-Path $projectRoot ('.local/consumer-' + [guid]::NewGuid().ToString('N'))
  $library = Join-Path $consumerRoot 'library'
  $app = Join-Path $consumerRoot 'app'
  New-Item -ItemType Directory -Force $app | Out-Null
  Expand-Archive -LiteralPath $archive -DestinationPath $library
  'members = ["library", "app"]' | Set-Content (Join-Path $consumerRoot 'moon.work')
  @'
name = "local/moonstatsd-consumer"
preferred_target = "native"
import { "Ryan-1125/moonstatsd@0.1.0", "moonbitlang/async@0.20.0" }
'@ | Set-Content (Join-Path $app 'moon.mod')
  @'
import { "Ryan-1125/moonstatsd" @codec, "Ryan-1125/moonstatsd/client", "moonbitlang/async", "moonbitlang/async/socket" }
pkgtype(kind: "executable")
'@ | Set-Content (Join-Path $app 'moon.pkg')
  @'
///|
async fn main {
  assert_eq(@codec.encode("consumer", Counter(3.0)).bytes(), b"consumer:3|c")
  let receiver = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer receiver.close()
  @async.with_timeout(2000, () => @client.with_client(receiver.addr, client => {
    ignore(client.record("consumer", Counter(3.0)))
    assert_eq(client.flush().submitted, 1L)
    let buffer = FixedArray::make(128, b'\x00')
    let (n, _) = receiver.recvfrom(buffer)
    assert_eq(Bytes::from_array(buffer[:n].to_owned()), b"consumer:3|c")
  }))
  println("Independent published-ZIP consumer: codec and real UDP passed")
}
'@ | Set-Content (Join-Path $app 'main.mbt')
  Push-Location $app
  try {
    & moon update
    if ($LASTEXITCODE -ne 0) { throw 'consumer dependency update failed' }
    & moon run . --target native
    if ($LASTEXITCODE -ne 0) { throw 'independent consumer failed' }
  } finally { Pop-Location }
  Write-Output "Consumer sources and extracted package: $consumerRoot"
} finally { Pop-Location }
