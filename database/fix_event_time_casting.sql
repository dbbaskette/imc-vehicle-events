-- Fix the event_time column with explicit casting
-- Since there's already some data, we need to handle the conversion properly

-- Option 1: Drop and recreate the column (safest for empty/test table)
ALTER TABLE vehicle_events DROP COLUMN event_time;
ALTER TABLE vehicle_events ADD COLUMN event_time BIGINT;

-- Option 2: If you have data you want to preserve, use this instead:
-- ALTER TABLE vehicle_events ALTER COLUMN event_time TYPE BIGINT USING EXTRACT(EPOCH FROM event_time);
