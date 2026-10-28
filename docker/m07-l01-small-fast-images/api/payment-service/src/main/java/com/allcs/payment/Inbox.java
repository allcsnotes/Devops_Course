package com.allcs.payment;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

// the idempotent consumer from module 17, lesson 3: remember every message id
@Component
public class Inbox {
    private final JdbcClient jdbc;

    Inbox(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public boolean firstTime(String messageId) {
        return jdbc.sql("""
                insert into processed_messages (message_id) values (?)
                on conflict (message_id) do nothing""")
            .param(messageId).update() == 1;
    }
}
