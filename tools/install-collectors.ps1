$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$refs = Join-Path $projectRoot '.local/references'
$destination = Join-Path $projectRoot '.local/tools'
New-Item -ItemType Directory -Force $refs,$destination | Out-Null
$windows = $IsWindows -or $env:OS -eq 'Windows_NT'
if ($windows) {
  $asset = 'statsd_exporter-0.28.0.windows-amd64.zip'
  $expected = '2270601d87b78200e485731755c3d99f0aa7c68da92801e56bbfe031ad81e257'
} else {
  $asset = 'statsd_exporter-0.28.0.linux-amd64.tar.gz'
  $expected = '6951081e3115669e4353975f897dda1cefddef5a5d16addc908485d9be16b72b'
}
$archive = Join-Path $refs $asset
Invoke-WebRequest "https://github.com/prometheus/statsd_exporter/releases/download/v0.28.0/$asset" -OutFile $archive
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $expected) { throw 'exporter checksum mismatch' }
if ($windows) { Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force }
else {
  & tar -xzf $archive -C $destination
  if ($LASTEXITCODE -ne 0) { throw 'exporter extraction failed' }
}
$statsdArchive = Join-Path $refs 'statsd-v0.9.0.zip'
Invoke-WebRequest 'https://github.com/statsd/statsd/archive/refs/tags/v0.9.0.zip' -OutFile $statsdArchive
if ((Get-FileHash $statsdArchive -Algorithm SHA256).Hash.ToLower() -ne 'e30a298c5a3d99bf5dc6a2ff69aadcd4df188b5eae2deb4dfb391f3e183517ff') { throw 'StatsD archive checksum mismatch' }
Expand-Archive -LiteralPath $statsdArchive -DestinationPath $destination -Force
Write-Output 'Fixed collectors downloaded and SHA256 verified (no npm install needed).'
