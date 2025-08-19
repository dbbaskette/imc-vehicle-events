package com.insurancemegacorp.jdbcconsumer;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest
@TestPropertySource(properties = {
    "spring.datasource.url=jdbc:h2:mem:testdb",
    "spring.datasource.driver-class-name=org.h2.Driver",
    "jdbc.consumer.initialize=true",
    "jdbc.consumer.table-name=test_messages",
    "jdbc.consumer.columns=id:payload.id,message:payload.message"
})
class JdbcConsumerApplicationTests {

    @Test
    void contextLoads() {
        // Basic context loading test
    }
}
