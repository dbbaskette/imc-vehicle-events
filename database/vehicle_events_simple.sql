-- Drop and recreate vehicle_events table (simplified, no partitioning)
-- Schema matches exact field names from FLATTENED_SCHEMA.md

-- Drop the existing table if it exists
DROP TABLE IF EXISTS vehicle_events CASCADE;

-- Create table with exact field names matching the flattened JSON
CREATE TABLE vehicle_events (
    -- Core vehicle data
    policy_id INTEGER,
    vehicle_id INTEGER,
    vin VARCHAR(255),
    event_time BIGINT,
    speed_mph REAL,
    speed_limit_mph INTEGER,
    current_street VARCHAR(255),
    g_force REAL,
    driver_id INTEGER,
    
    -- GPS data fields (gps_*)
    gps_latitude DOUBLE PRECISION,
    gps_longitude DOUBLE PRECISION,
    gps_altitude REAL,
    gps_speed REAL,
    gps_bearing REAL,
    gps_accuracy REAL,
    gps_satellite_count INTEGER,
    gps_fix_time INTEGER,
    
    -- Accelerometer data fields (accelerometer_*)
    accelerometer_x REAL,
    accelerometer_y REAL,
    accelerometer_z REAL,
    
    -- Gyroscope data fields (gyroscope_*)
    gyroscope_x REAL,
    gyroscope_y REAL,
    gyroscope_z REAL,
    
    -- Magnetometer data fields (magnetometer_*)
    magnetometer_x REAL,
    magnetometer_y REAL,
    magnetometer_z REAL,
    magnetometer_heading REAL,
    
    -- Environmental data
    barometric_pressure REAL,
    
    -- Device data fields (device_*)
    device_battery_level INTEGER,
    device_signal_strength INTEGER,
    device_orientation VARCHAR(255),
    device_screen_on BOOLEAN,
    device_charging BOOLEAN
)
WITH (
    APPENDONLY=true,
    OIDS=FALSE
)
DISTRIBUTED BY (vehicle_id);

-- Add indexes for performance
CREATE INDEX idx_vehicle_events_event_time ON vehicle_events (event_time);
CREATE INDEX idx_vehicle_events_policy_id ON vehicle_events (policy_id);
CREATE INDEX idx_vehicle_events_vehicle_id ON vehicle_events (vehicle_id);
CREATE INDEX idx_vehicle_events_driver_id ON vehicle_events (driver_id);
CREATE INDEX idx_vehicle_events_g_force ON vehicle_events (g_force);
