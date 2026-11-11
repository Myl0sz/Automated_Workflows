-- Write your own diagnostic SQL for the five new tables.
-- One worked example follows. Add your case queries below it.
SELECT r.run_id,r.command,a.item_id,a.asset_key,s.aoi_key,d.status,d.stage,
       d.network_bytes,d.http_status,d.error_code,d.error_message
FROM download_attempts d JOIN runs r ON r.run_id=d.run_id
JOIN subset_requests s ON s.subset_id=d.subset_id
JOIN assets a ON a.asset_id=s.asset_id
ORDER BY d.started_at,d.attempt_id;

-- Acquisition history with each artifact's latest known location.
-- Do not SUM network_bytes from this result: an artifact can appear on multiple attempts.
WITH latest_location AS (
    SELECT artifact_id,local_path,status,checked_at,
           ROW_NUMBER() OVER (
               PARTITION BY artifact_id
               ORDER BY checked_at DESC,location_id DESC
           ) AS location_rank
    FROM artifact_locations
)
SELECT a.item_id,a.asset_key,d.run_id,d.attempt_id,d.status AS attempt_status,
       d.stage,d.network_bytes,d.http_status,f.sha256,f.size_bytes,
       l.local_path,l.status AS location_status,l.checked_at
FROM download_attempts AS d
JOIN subset_requests AS s ON s.subset_id=d.subset_id
JOIN assets AS a ON a.asset_id=s.asset_id
LEFT JOIN artifacts AS f
       ON f.artifact_id=d.artifact_id AND f.subset_id=d.subset_id
LEFT JOIN latest_location AS l
       ON l.artifact_id=f.artifact_id AND l.location_rank=1
ORDER BY d.started_at,d.attempt_id;

-- Case A: show failed band, partial success and the later recovery history.
WITH failed_runs AS (
    SELECT DISTINCT run_id
    FROM download_attempts
    WHERE status='failed' AND error_code='RANGE_READ_FAILED'
),
affected_requests AS (
    SELECT DISTINCT d.subset_id
    FROM download_attempts AS d
    JOIN failed_runs AS f ON f.run_id=d.run_id
),
latest_location AS (
    SELECT artifact_id,local_path,status,checked_at,
           ROW_NUMBER() OVER (
               PARTITION BY artifact_id
               ORDER BY checked_at DESC,location_id DESC
           ) AS location_rank
    FROM artifact_locations
)
SELECT r.run_id,r.status AS run_status,a.item_id,a.asset_key,d.attempt_id,
       d.status AS attempt_status,d.stage,d.network_bytes,d.http_status,
       d.error_code,d.error_message,d.artifact_id,f.sha256,
       l.local_path,l.status AS location_status
FROM download_attempts AS d
JOIN affected_requests AS x ON x.subset_id=d.subset_id
JOIN runs AS r ON r.run_id=d.run_id
JOIN subset_requests AS s ON s.subset_id=d.subset_id
JOIN assets AS a ON a.asset_id=s.asset_id
LEFT JOIN artifacts AS f
       ON f.artifact_id=d.artifact_id AND f.subset_id=d.subset_id
LEFT JOIN latest_location AS l
       ON l.artifact_id=f.artifact_id AND l.location_rank=1
ORDER BY d.started_at,d.attempt_id;

-- Case B: show successful historical acquisition but current missing/corrupt location.

-- AOI identity: show one source band with separate requests for two AOIs.
