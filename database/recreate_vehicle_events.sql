-- Drop and recreate vehicle_events table for JDBC sink compatibility
-- This script changes event_timestamp from TIMESTAMP WITH TIME ZONE to BIGINT
-- to accept numeric timestamps directly from the telemetry processor

-- Drop the existing table if it exists
DROP TABLE IF EXISTS vehicle_events;

-- Recreate the table with BIGINT for event_timestamp
CREATE TABLE vehicle_events (
    policy_id BIGINT,
    vehicle_id BIGINT,
    vin VARCHAR(255),
    event_timestamp BIGINT,
    speed_mph REAL,
    current_street VARCHAR(255),
    g_force REAL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    altitude DOUBLE PRECISION,
    speed_ms REAL,
    bearing REAL,
    accuracy REAL,
    satellite_count INTEGER,
    gps_fix_time INTEGER,
    accel_x REAL,
    accel_y REAL,
    accel_z REAL,
    gyro_pitch REAL,
    gyro_roll REAL,
    gyro_yaw REAL,
    mag_x REAL,
    mag_y REAL,
    mag_z REAL,
    heading REAL,
    battery_level INTEGER,
    signal_strength INTEGER,
    orientation VARCHAR(255),
    screen_on BOOLEAN,
    charging BOOLEAN
)
WITH (
    APPENDONLY=true,
    OIDS=FALSE
)
DISTRIBUTED BY (vehicle_id);

-- Add indexes for performance
CREATE INDEX idx_vehicle_events_timestamp ON vehicle_events (event_timestamp);
CREATE INDEX idx_vehicle_events_policy_id ON vehicle_events (policy_id);
CREATE INDEX idx_vehicle_events_vehicle_id ON vehicle_events (vehicle_id);

-- Create a view for easy querying with proper timestamp conversion
-- The timestamp is stored as milliseconds since epoch, so divide by 1000 for seconds
CREATE VIEW vehicle_events_view AS
SELECT 
    policy_id,
    vehicle_id,
    vin,
    to_timestamp(event_timestamp/1000.0) AT TIME ZONE 'UTC' as event_timestamp,
    speed_mph,
    current_street,
    g_force,
    latitude,
    longitude,
    altitude,
    speed_ms,
    bearing,
    accuracy,
    satellite_count,
    gps_fix_time,
    accel_x,
    accel_y,
    accel_z,
    gyro_pitch,
    gyro_roll,
    gyro_yaw,
    mag_x,
    mag_y,
    mag_z,
    heading,
    battery_level,
    signal_strength,
    orientation,
    screen_on,
    charging
FROM vehicle_events;

-- Grant permissions (adjust as needed for your environment)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON vehicle_events TO your_user;
-- GRANT SELECT ON vehicle_events_view TO your_user;
