package com.allcs.catalog;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cache.Cache;
import org.springframework.cache.annotation.CachingConfigurer;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.interceptor.CacheErrorHandler;
import org.springframework.context.annotation.Configuration;

// Redis is a cache, not a dependency: if it is down, log it and read Postgres
@Configuration
@EnableCaching
class CacheConfig implements CachingConfigurer {
    private static final Logger log = LoggerFactory.getLogger(CacheConfig.class);

    @Override
    public CacheErrorHandler errorHandler() {
        return new CacheErrorHandler() {
            public void handleCacheGetError(RuntimeException e, Cache c, Object key) {
                log.warn("cache {} unavailable, reading the database: {}", c.getName(), e.getMessage());
            }
            public void handleCachePutError(RuntimeException e, Cache c, Object key, Object value) {
                log.warn("cache {} unavailable, not cached: {}", c.getName(), e.getMessage());
            }
            public void handleCacheEvictError(RuntimeException e, Cache c, Object key) {
                log.warn("cache {} evict failed: {}", c.getName(), e.getMessage());
            }
            public void handleCacheClearError(RuntimeException e, Cache c) {
                log.warn("cache {} clear failed: {}", c.getName(), e.getMessage());
            }
        };
    }
}
