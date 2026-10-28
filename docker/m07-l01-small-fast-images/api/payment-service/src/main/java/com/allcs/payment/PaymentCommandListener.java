package com.allcs.payment;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

// the saga participant from M19-L05: charge and refund
@Component
class PaymentCommandListener {
    private static final Logger log = LoggerFactory.getLogger(PaymentCommandListener.class);
    private final Inbox inbox;
    private final Charges charges;
    private final Outbox outbox;

    PaymentCommandListener(Inbox inbox, Charges charges, Outbox outbox) {
        this.inbox = inbox;
        this.charges = charges;
        this.outbox = outbox;
    }

    @KafkaListener(topics = "payment.commands", groupId = "payment")
    @Transactional
    public void on(PaymentCommand cmd) {
        if (!inbox.firstTime(cmd.messageId())) {
            log.info("duplicate {} skipped", cmd.messageId());
            return;
        }
        SagaReply reply = switch (cmd.type()) {
            case "CHARGE" -> charges.charge(cmd.sagaId(), cmd.studentId(), cmd.amountEur());
            case "REFUND" -> charges.refund(cmd.sagaId(), cmd.studentId());
            default -> throw new IllegalArgumentException("unknown command " + cmd.type());
        };
        outbox.add("enrollment.replies", cmd.sagaId(), reply);   // same transaction
        log.info("saga {}: {} {} EUR -> {}{}", cmd.sagaId(), cmd.type(), reply.amountEur(),
                reply.type(), reply.reason() == null ? "" : " (" + reply.reason() + ")");
    }
}
