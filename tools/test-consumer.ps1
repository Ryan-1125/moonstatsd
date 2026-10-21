param([switch]$SkipUpdate)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'module-metadata.ps1')
$module = Get-ModuleMetadata -ProjectRoot $projectRoot
Push-Location $projectRoot
try {
  & moon package
  if ($LASTEXITCODE -ne 0) { throw 'moon package failed' }
  $archive = $module.Archive
  $consumerRoot = Join-Path $projectRoot ('.local/consumer-' + [guid]::NewGuid().ToString('N'))
  $library = Join-Path $consumerRoot 'library'
  $app = Join-Path $consumerRoot 'app'
  New-Item -ItemType Directory -Force $app | Out-Null
  Expand-Archive -LiteralPath $archive -DestinationPath $library
  'members = ["library", "app"]' | Set-Content (Join-Path $consumerRoot 'moon.work')
  $consumerManifest = @'
name = "local/moonstatsd-consumer"
preferred_target = "native"
import { "__MODULE__@__VERSION__", "moonbitlang/async@0.20.0" }
'@
  $consumerManifest.Replace('__MODULE__', $module.Name).Replace('__VERSION__', $module.Version) | Set-Content (Join-Path $app 'moon.mod')
  $consumerPackage = @'
import { "__MODULE__" @codec, "__MODULE__/client", "moonbitlang/async", "moonbitlang/async/socket" }
pkgtype(kind: "executable")
'@
  $consumerPackage.Replace('__MODULE__', $module.Name) | Set-Content (Join-Path $app 'moon.pkg')
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
    if (-not $SkipUpdate) {
      & moon update
      if ($LASTEXITCODE -ne 0) { throw 'consumer dependency update failed' }
    }
    & moon run . --target native
    if ($LASTEXITCODE -ne 0) { throw 'independent consumer failed' }
  } finally { Pop-Location }
  Write-Output "Consumer sources and extracted package: $consumerRoot"
} finally { Pop-Location }
