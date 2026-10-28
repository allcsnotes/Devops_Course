package com.allcs.catalog;

import java.util.UUID;

// participant -> orchestrator, on enrollment.replies
public record SagaReply(String messageId, long sagaId, String type,
                        Integer amountEur, String reason) {

    static SagaReply of(long sagaId, String type, Integer amountEur, String reason) {
        return new SagaReply(UUID.randomUUID().toString(), sagaId, type, amountEur, reason);
    }
}
