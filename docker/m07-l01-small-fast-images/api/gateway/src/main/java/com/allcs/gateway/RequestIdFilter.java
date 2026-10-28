package com.allcs.gateway;

import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

// every route: one request id, one access log line with the time
@Component
class RequestIdFilter implements GlobalFilter, Ordered {

    private static final Logger log =
            LoggerFactory.getLogger(RequestIdFilter.class);

    @Override
    public Mono<Void> filter(ServerWebExchange exchange,
                             GatewayFilterChain chain) {
        String id = exchange.getRequest().getHeaders()
                .getFirst("X-Request-Id");
        String requestId = id != null ? id
                : UUID.randomUUID().toString().substring(0, 8);
        ServerWebExchange ex = exchange.mutate()
                .request(r -> r.header("X-Request-Id", requestId))
                .build();
        ex.getResponse().getHeaders().set("X-Request-Id", requestId);
        long start = System.nanoTime();
        return chain.filter(ex).doFinally(signal -> log.info(
                "{} {} -> {} in {} ms (request {})",
                ex.getRequest().getMethod(), ex.getRequest().getPath(),
                ex.getResponse().getStatusCode(),
                (System.nanoTime() - start) / 1_000_000, requestId));
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}
