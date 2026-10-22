param([switch]$SkipUpdate)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$readme = [IO.File]::ReadAllText((Join-Path $projectRoot 'README.md'))
$blocks = [regex]::Matches($readme, '(?s)```moonbit\r?\n(.*?)```')
if ($blocks.Count -ne 4) { throw 'Expected two complete README examples (moon.pkg and main.mbt pairs)' }
$app = Join-Path $projectRoot ('.local/readme-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $app | Out-Null
@'
name = "local/moonstatsd-readme"
preferred_target = "native"
import { "Ryan-1125/moonstatsd@0.2.0", "moonbitlang/async@0.20.0" }
'@ | Set-Content (Join-Path $app 'moon.mod')
for ($index = 0; $index -lt 2; $index++) {
  $example = Join-Path $app "example$index"
  New-Item -ItemType Directory -Force $example | Out-Null
  [IO.File]::WriteAllText((Join-Path $example 'moon.pkg'), $blocks[$index * 2].Groups[1].Value)
  [IO.File]::WriteAllText((Join-Path $example 'main.mbt'), $blocks[$index * 2 + 1].Groups[1].Value)
}
Push-Location $app
try {
  if (-not $SkipUpdate) {
    & moon update
    if ($LASTEXITCODE -ne 0) { throw 'README dependency resolution failed' }
  }
  & moon check --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'README examples failed compilation' }
  for ($index = 0; $index -lt 2; $index++) {
    & moon run "example$index" --target native
    if ($LASTEXITCODE -ne 0) { throw "README example $index failed" }
  }
  Write-Output 'README examples passed: published dependency, exact source, compile and run (UDP output is local submission only).'
} finally { Pop-Location }
