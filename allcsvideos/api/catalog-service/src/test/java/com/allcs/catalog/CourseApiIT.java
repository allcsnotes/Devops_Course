package com.allcs.catalog;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.web.client.RestClient;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

// real Postgres + Flyway; Kafka is not needed to read the catalog
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"spring.kafka.listener.auto-startup=false",
                      "spring.kafka.admin.auto-create=false",
                      "outbox.relay.delay=1h"})
@Testcontainers
class CourseApiIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer postgres = new PostgreSQLContainer("postgres:18");

    @LocalServerPort int port;

    @Test
    void listsTheSeededCourses() {
        String json = RestClient.create("http://localhost:" + port)
                .get().uri("/courses").retrieve().body(String.class);
        assertThat(json).contains("\"id\":\"SPRING-101\"")
                .contains("\"priceEur\":19");
    }
}
