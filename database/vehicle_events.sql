-- Greenplum CREATE TABLE script for vehicle_events
-- This table is optimized for time-series analytics and large-scale data warehousing.

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
DISTRIBUTED BY (vehicle_id)


-- Optional: Add indexes for faster lookups
CREATE INDEX idx_vehicle_events_timestamp ON vehicle_events (event_timestamp);
CREATE INDEX idx_vehicle_events_policy_id ON vehicle_events (policy_id);
