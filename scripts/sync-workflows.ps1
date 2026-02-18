# scripts/sync-workflows.ps1
# Sync repo workflows -> n8n (UPSERT + dedupe + short ASCII names)
# Run from repo root: C:\Users\USUARIO\Desktop\N8NSEO

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── HELPERS ──────────────────────────────────────────────────────────────────

function ConvertTo-NormalizedName([string]$s) {
  if (-not $s) { return "" }
  $s = $s.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $s.ToCharArray()) {
    $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($c)
    if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
  }
  (($sb.ToString()) -replace '[^a-zA-Z0-9]+', ' ').Trim().ToLowerInvariant()
}

function ConvertTo-AsciiTitle([string]$s) {
  if (-not $s) { return "" }
  $s = $s.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $s.ToCharArray()) {
    $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($c)
    if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
  }
  $t = $sb.ToString()
  $t = $t -replace '[^\x20-\x7E]', ''
  $t = $t -replace '\s+', ' '
  $t.Trim()
}

function Get-N8NWorkflows {
  $all = @()
  $cursor = $null
  do {
    $uri = if ($cursor) { "$url/api/v1/workflows?limit=200&cursor=$cursor" } else { "$url/api/v1/workflows?limit=200" }
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    if ($resp.data) { $all += $resp.data }
    $cursor = $resp.nextCursor
  } while ($cursor)
  return $all
}

function Remove-N8NWorkflow([string]$id) {
  Invoke-RestMethod -Method Delete -Uri "$url/api/v1/workflows/$id" -Headers $headers | Out-Null
}

function ConvertTo-N8NPayload([string]$path, [string]$forcedName) {
  $full = Join-Path $repoRoot $path
  if (-not (Test-Path $full)) { throw "No existe: $full" }

  $raw = Get-Content $full -Raw -Encoding utf8
  $j = $raw | ConvertFrom-Json
  if ($j.PSObject.Properties.Name -contains 'workflow' -and $j.workflow) { $j = $j.workflow }

  foreach ($k in @(
      'id', 'versionId', 'active', 'createdAt', 'updatedAt', 'meta', 'pinData', 'staticData',
      'versionCounter', 'triggerCount', 'activeVersionId', 'isArchived', 'shared', 'tags'
    )) {
    $null = $j.PSObject.Properties.Remove($k)
  }

  $j.name = ConvertTo-AsciiTitle $forcedName

  $allowed = @(
    'id', 'name', 'type', 'typeVersion', 'position', 'parameters', 'credentials',
    'disabled', 'notes', 'notesInFlow', 'continueOnFail', 'alwaysOutputData',
    'retryOnFail', 'maxTries', 'waitBetweenTries', 'onError', 'executeOnce', 'webhookId'
  )

  for ($i = 0; $i -lt $j.nodes.Count; $i++) {
    $n = $j.nodes[$i]
    foreach ($prop in @($n.PSObject.Properties.Name)) {
      if ($allowed -notcontains $prop) { $null = $n.PSObject.Properties.Remove($prop) }
    }
  }

  # n8n API rejects settings with unknown keys; keep payload schema-safe.
  $safeSettings = @{}

  return [ordered]@{
    name        = $j.name
    nodes       = $j.nodes
    connections = $j.connections
    settings    = $safeSettings
  }
}

function Set-N8NWorkflow($payload) {
  $body = $payload | ConvertTo-Json -Depth 100

  $all = Get-N8NWorkflows
  $norm = ConvertTo-NormalizedName $payload.name
  # Use $hits (not $matches — $matches is a PS automatic variable for regex)
  $hits = @($all | Where-Object { (ConvertTo-NormalizedName $_.name) -eq $norm } | Sort-Object updatedAt -Descending)

  if ($hits.Count -gt 1) {
    $hits | Select-Object -Skip 1 | ForEach-Object {
      Write-Host ("DEDUPE_DELETE -> {0} ({1})" -f $_.name, $_.id)
      Remove-N8NWorkflow $_.id
    }
  }

  $existing = $hits | Select-Object -First 1
  if ($existing) {
    Invoke-RestMethod -Method Put -Uri "$url/api/v1/workflows/$($existing.id)" -Headers $headers -ContentType "application/json" -Body $body | Out-Null
    Write-Host ("UPDATED -> {0}" -f $payload.name)
  }
  else {
    Invoke-RestMethod -Method Post -Uri "$url/api/v1/workflows" -Headers $headers -ContentType "application/json" -Body $body | Out-Null
    Write-Host ("CREATED -> {0}" -f $payload.name)
  }
}

function Sync-N8NWorkflows {
  $targets = @(
    @{ path = "workflows/01-creacion-post/workflow.json";   name = "S01 - Creacion Post" },
    @{ path = "workflows/02-kw-organicas-slack/workflow.json"; name = "S02 - KW Organicas Slack" },
    @{ path = "workflows/03-kw-organicas-slack-v2/workflow.json"; name = "S03 - KW Organicas Slack V2" }
  )

  Write-Host ("Syncing {0} workflows into {1} ..." -f $targets.Count, $url)
  foreach ($t in $targets) {
    $payload = ConvertTo-N8NPayload $t.path $t.name
    Set-N8NWorkflow $payload
  }

  # Global dedupe: remove any extra workflow with the same normalized name.
  $all = Get-N8NWorkflows
  $groups = $all | Group-Object { ConvertTo-NormalizedName $_.name }
  foreach ($g in $groups) {
    if ($g.Count -gt 1) {
      $g.Group | Sort-Object updatedAt -Descending | Select-Object -Skip 1 | ForEach-Object {
        Write-Host ("GLOBAL_DEDUPE_DELETE -> {0} ({1})" -f $_.name, $_.id)
        Remove-N8NWorkflow $_.id
      }
    }
  }

  # ── FINAL STATE ──────────────────────────────────────────────────────────
  $final = Get-N8NWorkflows
  Write-Host "`nFinal workflows:"
  $final |
    Select-Object id, name, updatedAt, isArchived |
    Sort-Object updatedAt -Descending |
    Format-Table -AutoSize

  # ── VALIDATE (managed workflows only) ───────────────────────────────────
  $targetNorms = @($targets | ForEach-Object { ConvertTo-NormalizedName $_.name })
  $managed = @($final | Where-Object { $targetNorms -contains (ConvertTo-NormalizedName $_.name) })
  $managedGroups = @($managed | Group-Object { ConvertTo-NormalizedName $_.name } | Where-Object { $_.Count -gt 1 })
  $managedCount = @($managed).Count
  $dupes = @($managedGroups).Count

  Write-Host ("MANAGED_TOTAL={0}  MANAGED_DUPLICADOS={1}" -f $managedCount, $dupes)

  if ($managedCount -ne $targets.Count -or $dupes -ne 0) {
    Write-Error ("Validacion fallida: MANAGED_TOTAL={0} (esperado {1}), MANAGED_DUPLICADOS={2}" -f $managedCount, $targets.Count, $dupes)
    exit 1
  }
  Write-Host ("OK: MANAGED_TOTAL={0}, MANAGED_DUPLICADOS={1}" -f $targets.Count, $dupes)
}

# ── MAIN ─────────────────────────────────────────────────────────────────────
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

$mcpPath = Join-Path $repoRoot ".cursor\mcp.json"
if (-not (Test-Path $mcpPath)) {
  throw "No existe $mcpPath. Copia .cursor\mcp.example.json -> .cursor\mcp.json y rellena la API key."
}

$mcpRaw = Get-Content $mcpPath -Raw -Encoding utf8
if ($mcpRaw.Length -gt 0 -and [int][char]$mcpRaw[0] -eq 0xFEFF) {
  $mcpRaw = $mcpRaw.Substring(1)
}

$cfg    = $mcpRaw | ConvertFrom-Json
$url    = "$($cfg.mcpServers.'n8n-mcp'.env.N8N_API_URL)".Trim().TrimEnd('/')
$key    = "$($cfg.mcpServers.'n8n-mcp'.env.N8N_API_KEY)".Trim().Trim('"')

if (-not $url) { throw "N8N_API_URL vacío en .cursor/mcp.json" }
if (-not $key -or $key -match 'YOUR_|HERE') { throw "N8N_API_KEY inválida/placeholder en .cursor/mcp.json" }

$headers = @{ 'X-N8N-API-KEY' = $key }

Sync-N8NWorkflows
