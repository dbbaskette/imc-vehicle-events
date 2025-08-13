package com.insurancemegacorp.vehicleevents.service;

import com.insurancemegacorp.vehicleevents.dto.TelematicsData;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Service;

import java.util.function.Consumer;

@Service
public class TelematicsConsumerService {

    private static final Logger logger = LoggerFactory.getLogger(TelematicsConsumerService.class);
    private static final double CRASH_THRESHOLD = 5.0;

    @Bean
    public Consumer<byte[]> consumeTelematicsData() {
        return rawBytes -> {
            String message = new String(rawBytes);
            logger.info("Received message: {}", message);
        };
    }

    private boolean isCrashEvent(TelematicsData data) {
        return data.getgForce() > CRASH_THRESHOLD || "CRASH".equalsIgnoreCase(data.getEventType());
    }

    private void handleCrashEvent(TelematicsData data) {
        logger.warn("CRASH EVENT DETECTED for vehicle {}: G-Force = {}, Event Type = {}", 
                   data.getVehicleId(), data.getgForce(), data.getEventType());
        
        logger.info("Crash location: Lat={}, Lon={}", data.getLatitude(), data.getLongitude());
        logger.info("Speed at crash: {} mph, Acceleration: {}", data.getSpeed(), data.getAcceleration());
        
        // Here you could trigger additional crash processing logic such as:
        // - Send emergency notifications
        // - Store crash data in a separate database
        // - Trigger insurance claim processing
        // - Contact emergency services
    }

    private void handleNormalEvent(TelematicsData data) {
        logger.debug("Processing normal telematics data for vehicle {}: Speed={}, G-Force={}", 
                    data.getVehicleId(), data.getSpeed(), data.getgForce());
        
        // Here you could process normal telematics data such as:
        // - Update vehicle location tracking
        // - Calculate driving behavior scores
        // - Monitor speed patterns
        // - Track fuel efficiency
    }
}