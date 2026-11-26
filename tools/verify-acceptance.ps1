param([switch]$SkipUpdate, [switch]$Published, [switch]$Agent)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$evidence = Join-Path $projectRoot ('.local/evidence/acceptance-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $evidence | Out-Null
$checks = [Collections.Generic.List[object]]::new()
function Invoke-AcceptanceCheck {
  param([string]$Name, [scriptblock]$Action)
  $log = Join-Path $evidence ($Name + '.log')
  try {
    & $Action *> $log
    $checks.Add([pscustomobject]@{ name=$Name; status='passed'; log=$log })
    Write-Output "$Name passed"
  } catch {
    $checks.Add([pscustomobject]@{ name=$Name; status='failed'; log=$log; error=$_.Exception.Message })
    throw
  }
}
Push-Location $projectRoot
try {
  Invoke-AcceptanceCheck 'source-package-consumer' { & ./tools/prepare-release.ps1 -SkipUpdate:$SkipUpdate }
  Invoke-AcceptanceCheck 'real-collectors' {
    & ./tools/install-collectors.ps1
    & node tools/test-interop.mjs
    if ($LASTEXITCODE) { throw 'StatsD/exporter interoperability failed' }
  }
  Invoke-AcceptanceCheck 'reference-client' {
    & node tools/test-reference.mjs
    if ($LASTEXITCODE) { throw 'Reference differential failed' }
  }
  if ($Agent) {
    Invoke-AcceptanceCheck 'official-agent' {
      & node tools/test-agent.mjs
      if ($LASTEXITCODE) { throw 'Official Agent verification failed' }
    }
  }
  if ($Published) {
    Invoke-AcceptanceCheck 'published-consumer' { & ./tools/test-registry-consumer.ps1 -SkipUpdate:$SkipUpdate }
    Invoke-AcceptanceCheck 'readme-examples' { & ./tools/test-readme.ps1 -SkipUpdate:$SkipUpdate }
  }
} finally {
  [pscustomobject]@{ completedAt=[DateTime]::UtcNow.ToString('o'); requested=@{published=[bool]$Published; agent=[bool]$Agent}; checks=@($checks.ToArray()) } |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $evidence 'summary.json')
  Pop-Location
  Write-Output "Acceptance evidence: $evidence"
}
