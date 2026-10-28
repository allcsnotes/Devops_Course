package com.allcs.payment;

import java.util.UUID;

// orchestrator -> payment, on payment.commands
public record PaymentCommand(String messageId, long sagaId, String type,
                             String studentId, Integer amountEur) {

    static PaymentCommand of(long sagaId, String type, String studentId, Integer amountEur) {
        return new PaymentCommand(UUID.randomUUID().toString(), sagaId, type, studentId, amountEur);
    }
}
