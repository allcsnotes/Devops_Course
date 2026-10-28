package com.allcs.catalog;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

// the saga participant from M19-L05: seat commands in, replies out
@Component
class CatalogCommandListener {
    private static final Logger log = LoggerFactory.getLogger(CatalogCommandListener.class);
    private final Inbox inbox;
    private final Seats seats;
    private final Outbox outbox;

    CatalogCommandListener(Inbox inbox, Seats seats, Outbox outbox) {
        this.inbox = inbox;
        this.seats = seats;
        this.outbox = outbox;
    }

    @KafkaListener(topics = "catalog.commands", groupId = "catalog")
    @Transactional
    public void on(CatalogCommand cmd) {
        if (!inbox.firstTime(cmd.messageId())) {
            log.info("duplicate {} skipped", cmd.messageId());
            return;
        }
        SagaReply reply = switch (cmd.type()) {
            case "RESERVE_SEAT" -> seats.reserve(cmd.sagaId(), cmd.courseId());
            case "CONFIRM_SEAT" -> seats.confirm(cmd.sagaId());
            case "RELEASE_SEAT" -> seats.release(cmd.sagaId(), cmd.courseId());
            default -> throw new IllegalArgumentException(cmd.type());
        };
        outbox.add("enrollment.replies", cmd.sagaId(), reply);
        log.info("saga {}: {} -> {}{}", cmd.sagaId(), cmd.type(), reply.type(),
                reply.reason() == null ? "" : " (" + reply.reason() + ")");
    }
}
