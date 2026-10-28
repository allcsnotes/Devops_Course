package com.allcs.enrollment;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class CatalogPrices {

    private static final Logger log =
            LoggerFactory.getLogger(CatalogPrices.class);
    private final CatalogClient catalog;

    CatalogPrices(CatalogClient catalog) {
        this.catalog = catalog;
    }

    @CircuitBreaker(name = "catalog", fallbackMethod = "unavailable")
    public CourseInfo course(String id) {
        return catalog.course(id);    // a GET: the load balancer may retry it
    }

    public CourseInfo unavailable(String id, Exception e) {
        if (e instanceof CourseNotFound notFound) {
            throw notFound;           // a 404 is an answer, not an outage
        }
        log.warn("catalog call failed: {}", e.toString());
        throw new PriceUnavailable(e);
    }
}
