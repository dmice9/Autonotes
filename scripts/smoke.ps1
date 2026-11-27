[CmdletBinding()]
param(
    [uri]$BaseUrl = 'http://localhost:8090',
    [string]$ImagePath,
    [ValidateRange(10, 1800)][int]$TimeoutSec = 600,
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $ImagePath) { $ImagePath = Join-Path $repoRoot 'tests/fixtures/lecture.png' }
if (-not $ReportPath) { $ReportPath = Join-Path $repoRoot 'artifacts/lab-1/smoke.json' }
Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(40)
$rootUrl = $BaseUrl.AbsoluteUri.TrimEnd('/')
$checks = [System.Collections.Generic.List[object]]::new()
$report = [ordered]@{ startedAt = [DateTimeOffset]::Now.ToString('o'); baseUrl = $rootUrl; passed = $false; checks = $checks }

function Request-Json([string]$Method, [string]$Path, $Body, [int]$Expected = 200, [string]$Token) {
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), "$rootUrl$Path")
    if ($Token) { $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token) }
    if ($null -ne $Body) { $request.Content = [System.Net.Http.StringContent]::new(($Body | ConvertTo-Json -Depth 8), [System.Text.Encoding]::UTF8, 'application/json') }
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ([int]$response.StatusCode -ne $Expected) { throw "$Method $Path expected $Expected, received $([int]$response.StatusCode): $raw" }
            if ($raw) { return ($raw | ConvertFrom-Json) }
        } finally { $response.Dispose() }
    } finally { $request.Dispose() }
}
function Passed([string]$Name) {
    $checks.Add([ordered]@{ name = $Name; passed = $true })
    Write-Host "PASS $Name"
}
try {
    $health = Request-Json GET '/actuator/health/readiness' $null
    if ($health.status -ne 'UP') { throw 'Backend is not ready.' }
    Passed 'backend readiness'
    $null = Request-Json GET '/api/v1/system/info' $null
    Passed 'system info'
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $username = 'smoke_' + $suffix
    $password = [guid]::NewGuid().ToString('N') + '!Aa9'
    $registration = @{ username = $username; email = "$username@example.test"; password = $password }
    $auth = Request-Json POST '/api/v1/auth/register' $registration 201
    if (-not $auth.token) { throw 'Registration returned no token.' }
    Passed 'registration'
    $auth = Request-Json POST '/api/v1/auth/login' @{ username = $username; password = $password }
    if (-not $auth.token) { throw 'Login returned no token.' }
    $token = $auth.token
    Passed 'login'
    $null = Request-Json GET '/api/v1/notes' $null 401
    Passed 'unauthenticated notes access rejected'
    $null = Request-Json GET "/api/v1/users/$username" $null 200 $token
    Passed 'own profile'
    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) { throw "Fixture not found: $ImagePath" }
    $form = [System.Net.Http.MultipartFormDataContent]::new()
    $upload = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, "$rootUrl/api/v1/notes")
    try {
        $form.Add([System.Net.Http.StringContent]::new('Lab 1 database transactions'), 'title')
        $file = [System.Net.Http.ByteArrayContent]::new([System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ImagePath).Path))
        $file.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('image/png')
        $form.Add($file, 'files', 'lecture.png')
        $upload.Content = $form
        $upload.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
        $response = $client.SendAsync($upload).GetAwaiter().GetResult()
        try {
            $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ([int]$response.StatusCode -ne 201) { throw "Upload failed: $([int]$response.StatusCode) $raw" }
            $note = $raw | ConvertFrom-Json
        } finally { $response.Dispose() }
    } finally { $upload.Dispose() }
    $noteId = $note.id
    if (-not $noteId) { throw 'Upload returned no note id.' }
    $report.noteId = $noteId
    Passed 'image upload'
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        $detail = Request-Json GET "/api/v1/notes/$noteId" $null 200 $token
        if ($detail.status -eq 'FAILED') { throw "ML processing failed: $($detail.summaryText)" }
        if ($detail.status -eq 'COMPLETED') { break }
        Start-Sleep -Seconds 3
    } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSec)
    $report.processingSeconds = [math]::Round($watch.Elapsed.TotalSeconds, 2)
    if ($detail.status -ne 'COMPLETED') { throw "ML did not finish within $TimeoutSec seconds." }
    if ([string]::IsNullOrWhiteSpace($detail.recognizedText)) { throw 'Empty OCR text.' }
    if ([string]::IsNullOrWhiteSpace($detail.summaryText) -or $detail.summaryText -match 'Не удалось|Processing failed') { throw 'Summary missing or contains a failure message.' }
    if ($ImagePath -eq (Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/fixtures/lecture.png') -and $detail.recognizedText -notmatch '(?i)transaction') { throw 'Fixture keyword missing from OCR.' }
    $report.recognizedText = $detail.recognizedText
    $report.summaryText = $detail.summaryText
    Passed 'real OCR and summary completed'
    $list = Request-Json GET '/api/v1/notes' $null 200 $token
    if ($noteId -notin @($list.content | ForEach-Object { $_.id })) { throw 'Created note missing from list.' }
    Passed 'note listed'
    $otherName = 'other_' + $suffix
    $other = Request-Json POST '/api/v1/auth/register' @{ username = $otherName; email = "$otherName@example.test"; password = $password } 201
    $null = Request-Json GET "/api/v1/notes/$noteId" $null 404 $other.token
    Passed 'other user cannot read note'
    $null = Request-Json DELETE "/api/v1/notes/$noteId" $null 204 $token
    $null = Request-Json GET "/api/v1/notes/$noteId" $null 404 $token
    Passed 'own note deleted'
    $report.passed = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    $report.finishedAt = [DateTimeOffset]::Now.ToString('o')
    $parent = Split-Path ([System.IO.Path]::GetFullPath($ReportPath)) -Parent
    $null = New-Item -ItemType Directory -Path $parent -Force
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    $client.Dispose()
}
