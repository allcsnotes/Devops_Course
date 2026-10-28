package com.allcs.catalog;

import java.util.List;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

// M07-B01: the course list, cached in Redis (key "courses::SimpleKey []")
@Service
class CourseCatalog {
    private final JdbcClient jdbc;

    CourseCatalog(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @Cacheable("courses")
    public List<Course> all() {
        return jdbc.sql("select * from courses order by title")
            .query(Course.class).list();
    }
}
