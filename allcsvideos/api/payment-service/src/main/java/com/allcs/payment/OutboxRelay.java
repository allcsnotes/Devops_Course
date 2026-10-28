package com.allcs.payment;

import static java.nio.charset.StandardCharsets.UTF_8;

import java.util.concurrent.TimeUnit;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
class OutboxRelay {
    private static final Logger log = LoggerFactory.getLogger(OutboxRelay.class);
    private final JdbcClient jdbc;
    private final KafkaTemplate<String, String> kafka;

    OutboxRelay(JdbcClient jdbc, KafkaTemplate<String, String> kafka) {
        this.jdbc = jdbc;
        this.kafka = kafka;
    }

    record Row(long id, String topic, String msgKey, String payload, String traceparent) {}

    @Scheduled(fixedDelayString = "${outbox.relay.delay:500ms}")
    @Transactional
    public void publish() {
        var batch = jdbc.sql("""
                select id, topic, msg_key, payload::text as payload, traceparent
                from outbox where published_at is null order by id limit 100
                for update skip locked""")
            .query(Row.class).list();
        for (Row r : batch) {
            var record = new ProducerRecord<>(r.topic(), r.msgKey(), r.payload());
            if (r.traceparent() != null) {   // continue this trace
                record.headers().add("traceparent",
                        r.traceparent().getBytes(UTF_8));
            }
            try {
                kafka.send(record).get(10, TimeUnit.SECONDS);
            } catch (Exception ex) {
                log.warn("Kafka unavailable, {} messages wait for the next run", batch.size());
                break;                       // keep the order: stop at the first failure
            }
            jdbc.sql("update outbox set published_at = now() where id = ?")
                .param(r.id()).update();
        }
    }
}
