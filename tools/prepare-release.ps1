param([switch]$SkipUpdate)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'module-metadata.ps1')
$module = Get-ModuleMetadata -ProjectRoot $projectRoot
Push-Location $projectRoot
try {
  if (-not $SkipUpdate) {
    & moon update
    if ($LASTEXITCODE) { throw 'dependency update failed' }
  }
  foreach ($arguments in @(
    @('fmt', '--check'),
    @('check', '--target', 'native', '--deny-warn'),
    @('build', '--target', 'native', '--deny-warn'),
    @('test', '--target', 'native', '--deny-warn'),
    @('test', '--target', 'wasm-gc', '--package', $module.Name, '--deny-warn')
  )) {
    & moon @arguments
    if ($LASTEXITCODE) { throw "Release check failed: moon $arguments" }
  }
  & (Join-Path $PSScriptRoot 'audit-package.ps1')
  & (Join-Path $PSScriptRoot 'test-consumer.ps1') -SkipUpdate:$SkipUpdate
  $hash = (Get-FileHash -LiteralPath $module.Archive -Algorithm SHA256).Hash.ToLowerInvariant()
  $evidencePath = Join-Path $projectRoot '.local/evidence/release.json'
  $commit = (& git rev-parse HEAD | Out-String).Trim()
  if ($LASTEXITCODE) { throw 'Cannot identify release source commit' }
  $dirty = [bool](& git status --porcelain | Out-String).Trim()
  [pscustomobject]@{ module = $module.Name; version = $module.Version; sha256 = $hash; gitCommit = $commit; workingTreeClean = -not $dirty; sdk = (& moon version | Out-String).Trim(); verifiedAt = [DateTime]::UtcNow.ToString('o') } |
    ConvertTo-Json | Set-Content $evidencePath
  Write-Output "Release preflight passed: $($module.Name)@$($module.Version), SHA256=$hash"
  Write-Output 'No upload performed. Publish this verified archive using moon publish, then run registry consumer verification.'
} finally { Pop-Location }
