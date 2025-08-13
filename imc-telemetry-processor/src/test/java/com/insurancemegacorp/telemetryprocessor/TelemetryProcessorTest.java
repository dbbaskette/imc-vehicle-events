package com.insurancemegacorp.telemetryprocessor;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import java.util.function.Function;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.cloud.stream.binder.test.TestChannelBinderConfiguration;
import org.springframework.context.annotation.Import;

import static org.assertj.core.api.Assertions.assertThat;

@Import(TestChannelBinderConfiguration.class)
@SpringBootTest(properties = {
        "spring.cloud.function.definition=vehicleEventsOut",
        "telemetry.accident.gforce.threshold=5.0",
        "spring.cloud.stream.defaultBinder=test"
})
class TelemetryProcessorTest {

    @Autowired
    private Function<org.springframework.messaging.Message<byte[]>, org.springframework.messaging.Message<byte[]>> vehicleEventsOut;

    @Test
    void emitsVehicleEventWhenGForceAboveThreshold() {
        String json = "{\"g_force\": 6.2, \"policy_id\":1, \"vehicle_id\":2, \"sensors\":{\"gps\":{\"latitude\":1.0,\"longitude\":2.0}}}";
        Message<byte[]> msg = MessageBuilder.withPayload(json.getBytes()).build();
        Message<byte[]> out = vehicleEventsOut.apply(msg);
        assertThat(out).isNotNull();
        String outStr = new String(out.getPayload());
        assertThat(outStr).contains("\"g_force\":6.2");
        assertThat(outStr).contains("\"latitude\":1.0");
        assertThat(outStr).contains("\"longitude\":2.0");
    }

    @Test
    void dropsWhenBelowThreshold() {
        String json = "{\"g_force\": 1.2}";
        Message<byte[]> msg = MessageBuilder.withPayload(json.getBytes()).build();
        Message<byte[]> out = vehicleEventsOut.apply(msg);
        assertThat(out).isNull();
    }
}


