param(
    [ValidateSet('start','status','backup','stop')]
    [string]$Mode = 'start',
    [ValidateRange(1024,65535)]
    [int]$Port = 8090,
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$demoRepoRoot = Split-Path -Parent $PSScriptRoot
$demoNodePath = Join-Path $demoRepoRoot 'node_modules/node/bin/node.exe'
if (-not (Test-Path -LiteralPath $demoNodePath)) { throw 'Run npm.cmd ci in the repository root first.' }
$demoLaunchArgs = @((Join-Path $PSScriptRoot 'tool/demo_runtime.cjs'),$Mode,'--port',"$Port")
if ($SkipBuild) { $demoLaunchArgs += '--skip-build' }
& $demoNodePath @demoLaunchArgs
if ($LASTEXITCODE -ne 0) { throw 'Demo launcher did not finish. Read the message above; no reset was performed.' }
