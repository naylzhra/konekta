# Put a Bandung-area OSM PBF at infra/osrm/data/bandung.osm.pbf first.
$ErrorActionPreference = 'Stop'
$dataDir = Join-Path $PSScriptRoot 'data'
$pbf = Join-Path $dataDir 'bandung.osm.pbf'
if (-not (Test-Path -LiteralPath $pbf -PathType Leaf)) {
    throw "OSM extract missing: $pbf"
}

$image = 'ghcr.io/project-osrm/osrm-backend:latest'
$volume = "${dataDir}:/data"
docker run --rm -v $volume $image osrm-extract -p /opt/car.lua /data/bandung.osm.pbf
if ($LASTEXITCODE -ne 0) { throw 'osrm-extract failed' }
docker run --rm -v $volume $image osrm-partition /data/bandung.osrm
if ($LASTEXITCODE -ne 0) { throw 'osrm-partition failed' }
docker run --rm -v $volume $image osrm-customize /data/bandung.osrm
if ($LASTEXITCODE -ne 0) { throw 'osrm-customize failed' }
Write-Host 'OSRM graph ready. Start docker-compose.yml with docker-compose.osrm.yml.'
