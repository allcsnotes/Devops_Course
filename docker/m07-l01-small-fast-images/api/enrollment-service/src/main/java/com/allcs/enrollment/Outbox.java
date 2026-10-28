package com.allcs.enrollment;

import io.micrometer.tracing.Span;
import io.micrometer.tracing.Tracer;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

// module 17, lesson 4: the message is a row, saved in the caller's transaction
@Component
public class Outbox {
    private final JdbcClient jdbc;
    private final JsonMapper json;
    private final Tracer tracer;

    Outbox(JdbcClient jdbc, JsonMapper json, Tracer tracer) {
        this.jdbc = jdbc;
        this.json = json;
        this.tracer = tracer;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public void add(String topic, Object key, Object message) {
        jdbc.sql("""
                insert into outbox (topic, msg_key, payload, traceparent)
                values (?, ?, ?::jsonb, ?)""")
            .params(topic, String.valueOf(key),
                    json.writeValueAsString(message), traceparent())
            .update();
    }

    // new in B11: keep the trace with the row, the relay sends it later
    private String traceparent() {
        Span span = tracer.currentSpan();
        if (span == null) return null;
        return "00-" + span.context().traceId() + "-"
                + span.context().spanId() + "-01";
    }
}
