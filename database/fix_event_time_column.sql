-- Fix the event_time column to accept Unix epoch timestamps
-- Change from TIMESTAMP to BIGINT to match the incoming data format

ALTER TABLE vehicle_events 
ALTER COLUMN event_time TYPE BIGINT;

-- Add a computed column for human-readable timestamps if needed
-- ALTER TABLE vehicle_events 
-- ADD COLUMN event_timestamp TIMESTAMP WITH TIME ZONE 
-- GENERATED ALWAYS AS (to_timestamp(event_time)) STORED;
