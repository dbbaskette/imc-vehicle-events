-- Fix the event_time column by handling the dependent view
-- Step 1: Drop the dependent view
DROP VIEW IF EXISTS vehicle_events_view CASCADE;

-- Step 2: Drop and recreate the column
ALTER TABLE vehicle_events DROP COLUMN event_time;
ALTER TABLE vehicle_events ADD COLUMN event_time BIGINT;

-- Step 3: Recreate the view if needed (you can adjust this query as needed)
-- CREATE VIEW vehicle_events_view AS 
-- SELECT *, to_timestamp(event_time) as event_timestamp 
-- FROM vehicle_events;
