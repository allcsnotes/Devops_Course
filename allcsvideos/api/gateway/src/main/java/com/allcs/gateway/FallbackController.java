package com.allcs.gateway;

import static org.springframework.cloud.gateway.support.ServerWebExchangeUtils.CIRCUITBREAKER_EXECUTION_EXCEPTION_ATTR;

import java.util.Map;
import java.util.concurrent.TimeoutException;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.server.ServerWebExchange;

// where the CircuitBreaker filter forwards when catalog fails
@RestController
class FallbackController {

    @RequestMapping("/fallback/catalog")
    ResponseEntity<Map<String, String>> catalog(ServerWebExchange ex) {
        Throwable cause =
                ex.getAttribute(CIRCUITBREAKER_EXECUTION_EXCEPTION_ATTR);
        HttpStatusCode status = switch (cause) {
            // e.g. 504 when the response timeout fires
            case ResponseStatusException e -> e.getStatusCode();
            // the breaker's own time limiter
            case TimeoutException e -> HttpStatus.GATEWAY_TIMEOUT;
            case null, default -> HttpStatus.SERVICE_UNAVAILABLE;
        };
        String name = cause == null
                ? "none" : cause.getClass().getSimpleName();
        return ResponseEntity.status(status).body(Map.of(
                "message", "Catalog is unavailable. Please try again soon.",
                "cause", name));
    }
}
