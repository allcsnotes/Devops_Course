package com.allcs.catalog;

import jakarta.servlet.http.HttpServletResponse;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

// the monolith's /api/courses, now in its own service and database (M19-B11)
@RestController
@RequestMapping("/courses")
class CourseController {
    private static final Logger log = LoggerFactory.getLogger(CourseController.class);
    private final JdbcClient jdbc;
    private final String me;

    // on Kubernetes, HOSTNAME is the pod name
    CourseController(JdbcClient jdbc, @Value("${HOSTNAME:local}") String pod) {
        this.jdbc = jdbc;
        this.me = pod;
    }

    record Course(String id, String title, int priceEur, int seatsLeft) {}

    @GetMapping
    List<Course> all(HttpServletResponse res) {
        res.setHeader("X-Served-By", me);   // which instance answered
        return jdbc.sql("select * from courses order by title")
            .query(Course.class).list();
    }

    @GetMapping("/{id}")
    Course one(@PathVariable String id, HttpServletResponse res) {
        res.setHeader("X-Served-By", me);
        log.info("course {} served by {}", id, me);
        return jdbc.sql("select * from courses where id = ?").param(id)
            .query(Course.class).optional()
            .orElseThrow(() -> new ResponseStatusException(
                HttpStatus.NOT_FOUND, "No course " + id));
    }
}
