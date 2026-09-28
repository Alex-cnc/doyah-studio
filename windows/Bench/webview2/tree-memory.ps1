# tree-memory.ps1 -- working-set sum of a process and all of its descendants.
#
# Called by windows/Bench/webview2/bench.mjs (the WebView2 grid bench harness) to sample the host
# process tree while the measurement runs. Output is one line of JSON on stdout.
#
# Why this file is ASCII-only: PowerShell 5.1 decodes a file WITHOUT a UTF-8 BOM as ANSI (cp936 on
# this machine), so non-ASCII text in a script is unsafe unless the BOM is guaranteed. This script
# is machine-facing (parsed by Node) and keeps zero non-ASCII bytes on purpose; the prose lives in
# the Chinese README next to it.
#
# Usage: powershell -NoProfile -File tree-memory.ps1 -ParentPid <pid>
# Output: {"parentPid":N,"processes":N,"workingSetBytes":N,"names":["..."]}
param(
  [Parameter(Mandatory = $true)][int]$ParentPid
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
  $all = Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, WorkingSetSize, Name
} catch {
  # A process may exit mid-enumeration; report an empty (but valid) reading rather than failing.
  Write-Output '{"parentPid":0,"processes":0,"workingSetBytes":0,"names":[]}'
  exit 0
}

$treeIds = New-Object System.Collections.Generic.HashSet[int]
[void]$treeIds.Add($ParentPid)
$frontier = @($ParentPid)
while ($frontier.Count -gt 0) {
  $next = @()
  foreach ($proc in $all) {
    if ($frontier -contains [int]$proc.ParentProcessId) {
      if ($treeIds.Add([int]$proc.ProcessId)) { $next += [int]$proc.ProcessId }
    }
  }
  $frontier = $next
}

$bytes = 0
$names = @()
foreach ($proc in $all) {
  if ($treeIds.Contains([int]$proc.ProcessId)) {
    $bytes += [int64]$proc.WorkingSetSize
    $names += [string]$proc.Name
  }
}

$payload = [ordered]@{
  parentPid        = $ParentPid
  processes        = $treeIds.Count
  workingSetBytes  = $bytes
  names            = @($names | Sort-Object -Unique)
}
Write-Output ($payload | ConvertTo-Json -Compress)
