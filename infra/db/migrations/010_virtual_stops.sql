-- Historical demand, candidate review, and stop lifecycle.
CREATE TABLE virtual_stop_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    window_start TIMESTAMPTZ NOT NULL,
    window_end TIMESTAMPTZ NOT NULL,
    endpoint TEXT NOT NULL CHECK (endpoint IN ('pickup', 'dropoff')),
    params JSONB NOT NULL,
    summary JSONB NOT NULL DEFAULT '{}'::jsonb,
    triggered_by UUID REFERENCES users(id) ON DELETE SET NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    CHECK (window_end > window_start)
);

CREATE TABLE demand_clusters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES virtual_stop_runs(id) ON DELETE CASCADE,
    service_cluster_id TEXT NOT NULL,
    corridor_id TEXT NOT NULL REFERENCES corridors(id),
    direction TEXT NOT NULL CHECK (direction IN ('forward', 'backward')),
    time_slot INTEGER NOT NULL,
    size INTEGER NOT NULL,
    unique_users INTEGER NOT NULL,
    centroid geography(Point, 4326) NOT NULL,
    snapped_location geography(Point, 4326),
    validated BOOLEAN NOT NULL,
    result JSONB NOT NULL,
    UNIQUE (run_id, service_cluster_id)
);
CREATE INDEX demand_clusters_centroid_gix ON demand_clusters USING GIST (centroid);

CREATE TABLE demand_cluster_members (
    cluster_id UUID NOT NULL REFERENCES demand_clusters(id) ON DELETE CASCADE,
    trip_plan_id UUID NOT NULL REFERENCES trip_plans(id) ON DELETE CASCADE,
    PRIMARY KEY (cluster_id, trip_plan_id)
);

CREATE TABLE stop_candidates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cluster_id UUID NOT NULL UNIQUE REFERENCES demand_clusters(id) ON DELETE CASCADE,
    location geography(Point, 4326) NOT NULL,
    evaluation JSONB NOT NULL,
    eligible BOOLEAN NOT NULL,
    rank INTEGER,
    score DOUBLE PRECISION,
    action TEXT CHECK (action IN ('new_stop', 'relocate_stop')),
    relocates_stop_id UUID REFERENCES stops(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'proposed'
        CHECK (status IN ('proposed', 'approved', 'rejected', 'superseded')),
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    review_note TEXT,
    approved_stop_id UUID UNIQUE REFERENCES stops(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX stop_candidates_location_gix ON stop_candidates USING GIST (location);
CREATE INDEX stop_candidates_status_idx ON stop_candidates (status, created_at DESC);

CREATE TABLE restricted_zones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind TEXT NOT NULL CHECK (kind IN ('intersection', 'no_stopping', 'other')),
    location geography(Point, 4326) NOT NULL,
    radius_m DOUBLE PRECISION NOT NULL CHECK (radius_m > 0),
    source TEXT NOT NULL
);
CREATE INDEX restricted_zones_location_gix ON restricted_zones USING GIST (location);

ALTER TABLE stops ADD COLUMN retired_at TIMESTAMPTZ;
