-- Drop and recreate vehicle_events table for JDBC sink compatibility
-- Updated schema to align with new flattened JSON structure including new fields

-- Drop the existing table if it exists
DROP TABLE IF EXISTS vehicle_events;

-- Recreate the table with contextual field names for better clarity
CREATE TABLE vehicle_events (
    -- Core telemetry fields
    policy_id BIGINT,
    vehicle_id BIGINT,
    vin VARCHAR(255),
    event_time VARCHAR(255),
    speed_mph REAL,
    speed_limit_mph REAL,
    current_street VARCHAR(255),
    g_force REAL,
    driver_id VARCHAR(255),
    
    -- GPS sensor data
    gps_latitude DOUBLE PRECISION,
    gps_longitude DOUBLE PRECISION,
    gps_altitude DOUBLE PRECISION,
    gps_speed_ms REAL,
    gps_bearing REAL,
    gps_accuracy REAL,
    gps_satellite_count INTEGER,
    gps_fix_time INTEGER,
    
    -- Accelerometer sensor data
    accelerometer_x REAL,
    accelerometer_y REAL,
    accelerometer_z REAL,
    
    -- Gyroscope sensor data
    gyroscope_pitch REAL,
    gyroscope_roll REAL,
    gyroscope_yaw REAL,
    
    -- Magnetometer sensor data
    magnetometer_x REAL,
    magnetometer_y REAL,
    magnetometer_z REAL,
    magnetometer_heading REAL,
    
    -- Environmental sensor data
    sensors_barometric_pressure REAL,
    
    -- Device status data
    device_battery_level REAL,
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

-- Create a view for easy querying with proper timestamp conversion
-- The event_time is stored as ISO 8601 string, this view converts it to timestamp
CREATE VIEW vehicle_events_view AS
SELECT 
    -- Core telemetry fields
    policy_id,
    vehicle_id,
    vin,
    event_time::timestamp with time zone as event_timestamp,
    speed_mph,
    speed_limit_mph,
    current_street,
    g_force,
    driver_id,
    
    -- GPS sensor data
    gps_latitude,
    gps_longitude,
    gps_altitude,
    gps_speed_ms,
    gps_bearing,
    gps_accuracy,
    gps_satellite_count,
    gps_fix_time,
    
    -- Accelerometer sensor data
    accelerometer_x,
    accelerometer_y,
    accelerometer_z,
    
    -- Gyroscope sensor data
    gyroscope_pitch,
    gyroscope_roll,
    gyroscope_yaw,
    
    -- Magnetometer sensor data
    magnetometer_x,
    magnetometer_y,
    magnetometer_z,
    magnetometer_heading,
    
    -- Environmental sensor data
    sensors_barometric_pressure,
    
    -- Device status data
    device_battery_level,
    device_signal_strength,
    device_orientation,
    device_screen_on,
    device_charging
FROM vehicle_events;

-- Grant permissions (adjust as needed for your environment)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON vehicle_events TO your_user;
-- GRANT SELECT ON vehicle_events_view TO your_user;
