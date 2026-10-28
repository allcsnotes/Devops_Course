package com.allcs.enrollment;

import java.util.UUID;

// orchestrator -> catalog, on catalog.commands
public record CatalogCommand(String messageId, long sagaId, String type, String courseId) {

    static CatalogCommand of(long sagaId, String type, String courseId) {
        return new CatalogCommand(UUID.randomUUID().toString(), sagaId, type, courseId);
    }
}
