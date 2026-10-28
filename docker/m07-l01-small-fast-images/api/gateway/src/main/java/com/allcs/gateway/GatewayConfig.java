package com.allcs.gateway;

import java.security.Principal;
import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import reactor.core.publisher.Mono;

// the routes live in the config repo (gateway.yml); this is the rate-limit key
@Configuration
class GatewayConfig {

    // the user id from the JWT (sub), else the client IP
    @Bean
    KeyResolver userKeyResolver() {
        return exchange -> exchange.getPrincipal()
                .map(Principal::getName)
                .switchIfEmpty(Mono.fromSupplier(() -> exchange.getRequest()
                        .getRemoteAddress().getAddress().getHostAddress()));
    }
}
