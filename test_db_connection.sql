-- Test database connection and table structure
\l;  -- List databases
\c insurance_megacorp;  -- Connect to the database
\dt;  -- List tables
\d vehicle_events;  -- Describe the vehicle_events table structure
SELECT COUNT(*) FROM vehicle_events;  -- Check if table has any rows
