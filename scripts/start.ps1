[CmdletBinding()]
param(
    [string]$OllamaBaseUrl,
    [string]$OllamaModel,
    [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$ProjectName = 'autonotes',
    [ValidateRange(60, 3600)][int]$WaitTimeoutSec = 900
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Push-Location $repoRoot
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Install Docker Desktop with Compose first.' }
    & docker info --format '{{.ServerVersion}}'
    if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop (Linux containers) and retry.' }
    $envPath = Join-Path $repoRoot '.env'
    if (-not (Test-Path -LiteralPath $envPath)) {
        Copy-Item -LiteralPath (Join-Path $repoRoot '.env.example') -Destination $envPath
    }
    $settings = Get-Content -LiteralPath $envPath -Raw -Encoding UTF8
    foreach ($entry in @(@('OLLAMA_BASE_URL', $OllamaBaseUrl), @('OLLAMA_MODEL', $OllamaModel))) {
        if ($entry[1]) {
            if ($entry[1] -match '[\r\n]') { throw 'Configuration values must be a single line.' }
            $pattern = '(?m)^' + [regex]::Escape($entry[0]) + '=.*$'
            if ($settings -match $pattern) {
                $replacement = $entry[0] + '=' + $entry[1]
                $settings = [regex]::Replace($settings, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement })
            } else { $settings += "`n$($entry[0])=$($entry[1])`n" }
        }
    }
    if ($settings -match '<[^>]+>') { throw 'Replace placeholders in .env before starting.' }
    [System.IO.File]::WriteAllText($envPath, $settings, [System.Text.UTF8Encoding]::new($false))
    & docker compose --project-name $ProjectName config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Invalid Compose configuration.' }
    & docker compose --project-name $ProjectName build
    if ($LASTEXITCODE -ne 0) { throw 'Build failed. See the output above.' }
    # Check the actual network route from an ML container, not just its /health.
    $probe = "from ml.settings import get_settings; import httpx; s=get_settings(); r=httpx.get(s.ollama_base_url+'/api/tags',timeout=20); r.raise_for_status(); names={m['name'] for m in r.json().get('models',[])}; required={s.ollama_model,s.ollama_fallback_model}-{None,''}; missing=required-names; print('Ollama models:',sorted(names)); assert not missing, 'Pull missing models: '+str(sorted(missing))"
    & docker compose --project-name $ProjectName run --rm --no-deps -T ml python -c $probe
    if ($LASTEXITCODE -ne 0) { throw 'ML container cannot use Ollama. Check URL, model names and network access.' }
    & docker compose --project-name $ProjectName up -d --wait --wait-timeout $WaitTimeoutSec
    if ($LASTEXITCODE -ne 0) { throw "Startup failed. Inspect: docker compose --project-name $ProjectName logs --tail 100" }
    Write-Host 'Started. Open http://localhost:3000 and run scripts/smoke.ps1.'
} finally { Pop-Location }
