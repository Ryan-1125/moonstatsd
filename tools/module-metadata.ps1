# Read the current project's literal module identity; fail rather than auditing a stale ZIP.
function Get-ModuleMetadata {
  param([Parameter(Mandatory)][string]$ProjectRoot)
  $manifest = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'moon.mod'))
  $moduleMatch = [regex]::Match($manifest, '(?m)^name\s*=\s*"([A-Za-z0-9_-]+/[A-Za-z0-9_.-]+)"\s*$')
  $versionMatch = [regex]::Match($manifest, '(?m)^version\s*=\s*"(\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?(?:\+[A-Za-z0-9.-]+)?)"\s*$')
  if (-not $moduleMatch.Success -or -not $versionMatch.Success) {
    throw 'Expected literal name and semantic version assignments in moon.mod'
  }
  $moduleName = $moduleMatch.Groups[1].Value
  $moduleVersion = $versionMatch.Groups[1].Value
  [pscustomobject]@{
    Name = $moduleName
    Version = $moduleVersion
    Archive = Join-Path $ProjectRoot ('_build/publish/' + $moduleName.Replace('/', '-') + '-' + $moduleVersion + '.zip')
  }
}
