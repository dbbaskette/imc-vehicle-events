package com.insurancemegacorp.vehicleevents.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.LocalDateTime;

public class TelematicsData {
    
    @JsonProperty("vehicle_id")
    private String vehicleId;
    
    @JsonProperty("timestamp")
    private LocalDateTime timestamp;
    
    @JsonProperty("speed")
    private double speed;
    
    @JsonProperty("acceleration")
    private double acceleration;
    
    @JsonProperty("g_force")
    private double gForce;
    
    @JsonProperty("latitude")
    private double latitude;
    
    @JsonProperty("longitude")
    private double longitude;
    
    @JsonProperty("heading")
    private double heading;
    
    @JsonProperty("event_type")
    private String eventType;

    public TelematicsData() {}

    public TelematicsData(String vehicleId, LocalDateTime timestamp, double speed, 
                         double acceleration, double gForce, double latitude, 
                         double longitude, double heading, String eventType) {
        this.vehicleId = vehicleId;
        this.timestamp = timestamp;
        this.speed = speed;
        this.acceleration = acceleration;
        this.gForce = gForce;
        this.latitude = latitude;
        this.longitude = longitude;
        this.heading = heading;
        this.eventType = eventType;
    }

    public String getVehicleId() {
        return vehicleId;
    }

    public void setVehicleId(String vehicleId) {
        this.vehicleId = vehicleId;
    }

    public LocalDateTime getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(LocalDateTime timestamp) {
        this.timestamp = timestamp;
    }

    public double getSpeed() {
        return speed;
    }

    public void setSpeed(double speed) {
        this.speed = speed;
    }

    public double getAcceleration() {
        return acceleration;
    }

    public void setAcceleration(double acceleration) {
        this.acceleration = acceleration;
    }

    public double getgForce() {
        return gForce;
    }

    public void setgForce(double gForce) {
        this.gForce = gForce;
    }

    public double getLatitude() {
        return latitude;
    }

    public void setLatitude(double latitude) {
        this.latitude = latitude;
    }

    public double getLongitude() {
        return longitude;
    }

    public void setLongitude(double longitude) {
        this.longitude = longitude;
    }

    public double getHeading() {
        return heading;
    }

    public void setHeading(double heading) {
        this.heading = heading;
    }

    public String getEventType() {
        return eventType;
    }

    public void setEventType(String eventType) {
        this.eventType = eventType;
    }

    @Override
    public String toString() {
        return "TelematicsData{" +
                "vehicleId='" + vehicleId + '\'' +
                ", timestamp=" + timestamp +
                ", speed=" + speed +
                ", acceleration=" + acceleration +
                ", gForce=" + gForce +
                ", latitude=" + latitude +
                ", longitude=" + longitude +
                ", heading=" + heading +
                ", eventType='" + eventType + '\'' +
                '}';
    }
}