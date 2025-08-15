# Flattened Telemetry Schema

This document describes the flattened JSON schema produced by the `imc-telemetry-flattener` service from nested telemetry data.

## Schema Overview

The flattening process transforms nested sensor data into a flat structure with contextual field names that preserve the origin and meaning of each data point.

## Complete Flattened Schema

```json
{
  // Core telemetry fields
  "policy_id": 200018,
  "vehicle_id": 300021,
  "vin": "1HGBH41JXMN109186",
  "event_time": "2024-01-15T10:30:45.123Z",
  "speed_mph": 32.5,
  "speed_limit_mph": 35,
  "current_street": "Peachtree Street",
  "g_force": 1.18,
  "driver_id": "DRIVER-400018",
  
  // GPS sensor data (contextual prefix: gps_)
  "gps_latitude": 33.7701,
  "gps_longitude": -84.3876,
  "gps_altitude": 351.59,
  "gps_speed_ms": 14.5,
  "gps_bearing": 148.37,
  "gps_accuracy": 2.64,
  "gps_satellite_count": 11,
  "gps_fix_time": 150,
  
  // Accelerometer sensor data (contextual prefix: accelerometer_)
  "accelerometer_x": 0.1234,
  "accelerometer_y": -0.0567,
  "accelerometer_z": 0.9876,
  
  // Gyroscope sensor data (contextual prefix: gyroscope_)
  "gyroscope_pitch": 0.02,
  "gyroscope_roll": -0.01,
  "gyroscope_yaw": 0.15,
  
  // Magnetometer sensor data (contextual prefix: magnetometer_)
  "magnetometer_x": 25.74,
  "magnetometer_y": -8.73,
  "magnetometer_z": 40.51,
  "magnetometer_heading": 148.37,
  
  // Environmental sensor data (contextual prefix: sensors_)
  "sensors_barometric_pressure": 1013.25,
  
  // Device status data (contextual prefix: device_)
  "device_battery_level": 82.0,
  "device_signal_strength": -63,
  "device_orientation": "portrait",
  "device_screen_on": false,
  "device_charging": true
}
```

## Field Mapping from Nested to Flattened

| **Nested JSON Path** | **Flattened Field Name** | **Description** |
|---------------------|-------------------------|-----------------|
| `sensors.gps.latitude` | `gps_latitude` | GPS latitude coordinate |
| `sensors.gps.longitude` | `gps_longitude` | GPS longitude coordinate |
| `sensors.gps.altitude` | `gps_altitude` | GPS altitude in meters |
| `sensors.gps.speed_ms` | `gps_speed_ms` | GPS-measured speed in m/s |
| `sensors.gps.bearing` | `gps_bearing` | GPS bearing/direction |
| `sensors.gps.accuracy` | `gps_accuracy` | GPS accuracy in meters |
| `sensors.gps.satellite_count` | `gps_satellite_count` | Number of GPS satellites |
| `sensors.gps.gps_fix_time` | `gps_fix_time` | GPS fix time in milliseconds |
| `sensors.accelerometer.x` | `accelerometer_x` | Accelerometer X-axis |
| `sensors.accelerometer.y` | `accelerometer_y` | Accelerometer Y-axis |
| `sensors.accelerometer.z` | `accelerometer_z` | Accelerometer Z-axis |
| `sensors.gyroscope.pitch` | `gyroscope_pitch` | Gyroscope pitch rotation |
| `sensors.gyroscope.roll` | `gyroscope_roll` | Gyroscope roll rotation |
| `sensors.gyroscope.yaw` | `gyroscope_yaw` | Gyroscope yaw rotation |
| `sensors.magnetometer.x` | `magnetometer_x` | Magnetometer X-axis |
| `sensors.magnetometer.y` | `magnetometer_y` | Magnetometer Y-axis |
| `sensors.magnetometer.z` | `magnetometer_z` | Magnetometer Z-axis |
| `sensors.magnetometer.heading` | `magnetometer_heading` | Magnetometer compass heading |
| `sensors.barometric_pressure` | `sensors_barometric_pressure` | Atmospheric pressure |
| `sensors.device.battery_level` | `device_battery_level` | Device battery percentage |
| `sensors.device.signal_strength` | `device_signal_strength` | Device signal strength in dBm |
| `sensors.device.orientation` | `device_orientation` | Device orientation |
| `sensors.device.screen_on` | `device_screen_on` | Device screen status |
| `sensors.device.charging` | `device_charging` | Device charging status |

## Benefits of Contextual Naming

1. **Clear Origin**: Field names immediately indicate sensor type
2. **No Collisions**: Eliminates ambiguity between similar fields
3. **Self-Documenting**: Schema is readable without external documentation
4. **Database Friendly**: Column names are explicit and meaningful
5. **Query Clarity**: SQL queries are more understandable

## Database Schema

The corresponding PostgreSQL/Greenplum table schema mirrors the flattened structure:

```sql
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
);
```

## Legacy Compatibility

The flattener maintains compatibility with legacy schemas:
- Maps `timestamp` → `event_time` when `event_time` is not present
- Handles missing nested structures gracefully
- Preserves all original top-level fields

## Total Field Count

The flattened schema contains **33 total fields**:
- 9 core telemetry fields
- 8 GPS fields  
- 3 accelerometer fields
- 3 gyroscope fields
- 4 magnetometer fields
- 1 environmental field
- 5 device fields