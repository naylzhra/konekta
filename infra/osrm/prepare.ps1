# Put a Bandung-area OSM PBF at infra/osrm/data/bandung.osm.pbf first.
param([string]$Modes = 'car,foot,motorcycle')
$ErrorActionPreference = 'Stop'
$dataDir = Join-Path $PSScriptRoot 'data'
$pbf = Join-Path $dataDir 'bandung.osm.pbf'
if (-not (Test-Path -LiteralPath $pbf -PathType Leaf)) {
    throw "OSM extract missing: $pbf"
}

$image = 'ghcr.io/project-osrm/osrm-backend:latest'
$volume = "${dataDir}:/data"
$profiles = "${PSScriptRoot}:/profiles:ro"
$selectedModes = $Modes.Split(',')
foreach ($mode in $selectedModes) {
    if ($mode -notin @('car', 'foot', 'motorcycle')) { throw "Unsupported routing mode: $mode" }
    $profile = if ($mode -eq 'motorcycle') { '/profiles/motorcycle.lua' } else { "/opt/$mode.lua" }
    $base = if ($mode -eq 'car') { '/data/bandung' } else { "/data/bandung-$mode" }
    $graph = "$base.osrm"
    docker run --rm -v $volume -v $profiles $image osrm-extract -p $profile --output $base /data/bandung.osm.pbf
    if ($LASTEXITCODE -ne 0) { throw "osrm-extract failed for $mode" }
    docker run --rm -v $volume $image osrm-partition $graph
    if ($LASTEXITCODE -ne 0) { throw "osrm-partition failed for $mode" }
    docker run --rm -v $volume $image osrm-customize $graph
    if ($LASTEXITCODE -ne 0) { throw "osrm-customize failed for $mode" }
}
Write-Host "OSRM graphs ready: $($selectedModes -join ', '). Start docker-compose.yml with docker-compose.osrm.yml."
