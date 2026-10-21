$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'module-metadata.ps1')
$module = Get-ModuleMetadata -ProjectRoot $projectRoot
Push-Location $projectRoot
try {
  New-Item -ItemType Directory -Force (Join-Path $projectRoot '.local/evidence') | Out-Null
  & moon package --list
  if ($LASTEXITCODE -ne 0) { throw 'package check failed' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = $module.Archive
  $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
  try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    $names | Set-Content (Join-Path $projectRoot '.local/package-list.txt')
    $names | Set-Content (Join-Path $projectRoot '.local/evidence/package-list.txt')
    $bad = $names | Where-Object { $_ -match '(^|[/\\])(\.local|\.git|\.github|\.mooncakes|_build)([/\\])|credentials|(^|[/\\])shenbao\.md$|\.log$|\.exe$|\.pid$' }
    if ($bad) { throw "Unexpected package entries: $bad" }
    if ($names -notcontains 'moon.mod' -or $names -notcontains 'client/client.mbt') { throw 'Required library sources missing' }
    Write-Output "Actual ZIP audit passed: $($names.Count) entries, no private/build artifacts."
  } finally { $zip.Dispose() }
} finally { Pop-Location }
