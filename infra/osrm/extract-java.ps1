param(
    [Parameter(Mandatory = $true)]
    [string]$Bbox,
    [string]$SourcePbf
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dataDir = Join-Path $PSScriptRoot 'data'
$download = Join-Path $dataDir 'java-latest.osm.pbf'
$target = Join-Path $dataDir 'bandung.osm.pbf'
$url = 'https://download.geofabrik.de/asia/indonesia/java-latest.osm.pbf'

$parts = $Bbox.Split(',')
if ($parts.Count -ne 4) {
    throw 'Bbox must be LEFT,BOTTOM,RIGHT,TOP in longitude,latitude order.'
}
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$coords = @()
foreach ($part in $parts) {
    $value = 0.0
    if (-not [double]::TryParse($part.Trim(), [System.Globalization.NumberStyles]::Float, $culture, [ref]$value)) {
        throw "Invalid Bbox coordinate: $part"
    }
    $coords += $value
}
$left, $bottom, $right, $top = $coords
if ($left -ge $right -or $bottom -ge $top -or
    $left -lt -180 -or $right -gt 180 -or $bottom -lt -90 -or $top -gt 90) {
    throw 'Invalid Bbox limits.'
}

$routeFile = Join-Path $repoRoot 'ROUTES.md'
$routeRows = @(Get-Content -LiteralPath $routeFile | Where-Object {
    $_ -match '^\|\s*\d+\s*\|[^|]+\|\s*-?\d+(?:\.\d+)?\s*\|\s*-?\d+(?:\.\d+)?\s*\|$'
})
if ($routeRows.Count -ne 51) {
    throw "Expected 51 K1 route points in ROUTES.md, found $($routeRows.Count)."
}
foreach ($row in $routeRows) {
    $fields = $row.Split('|')
    $lat = [double]::Parse($fields[3].Trim(), $culture)
    $lng = [double]::Parse($fields[4].Trim(), $culture)
    if ($lng -lt $left -or $lng -gt $right -or $lat -lt $bottom -or $lat -gt $top) {
        throw "Bbox excludes K1 stop $($fields[1].Trim()): $($fields[2].Trim())."
    }
}

New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
if (Test-Path -LiteralPath $target) {
    throw "Extract already exists: $target. Move it aside before generating a replacement."
}
if ($SourcePbf) {
    $source = (Resolve-Path -LiteralPath $SourcePbf).Path
} else {
    $source = $download
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Host "Downloading Java PBF from $url"
        & curl.exe --fail --location --retry 3 --output $source $url
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed. Remove incomplete file before retrying: $source"
        }
    }
}
if ((Get-Item -LiteralPath $source).Length -lt 100MB) {
    throw "Source PBF appears incomplete: $source"
}

$image = 'konekta-osmium:bookworm'
& docker build -t $image (Join-Path $PSScriptRoot 'osmium')
if ($LASTEXITCODE -ne 0) { throw 'Osmium image build failed.' }
$inputDir = Split-Path -Parent $source
$inputName = Split-Path -Leaf $source
$inputVolume = "${inputDir}:/source:ro"
$outputVolume = "${dataDir}:/data"
$normalizedBbox = ($coords | ForEach-Object { $_.ToString('R', $culture) }) -join ','
& docker run --rm -v $inputVolume -v $outputVolume $image extract --bbox $normalizedBbox --strategy complete_ways "/source/$inputName" -o /data/bandung.osm.pbf
if ($LASTEXITCODE -ne 0) { throw 'Osmium extraction failed.' }
if (-not (Test-Path -LiteralPath $target) -or (Get-Item -LiteralPath $target).Length -eq 0) {
    throw 'Osmium returned without a usable Bandung PBF.'
}
Write-Host "Ready: $target"
Write-Host 'Next: ./infra/osrm/prepare.ps1'
