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
    private final CourseCatalog catalog;
    private final String me;

    // on Kubernetes, HOSTNAME is the pod name
    CourseController(JdbcClient jdbc, CourseCatalog catalog,
                     @Value("${HOSTNAME:local}") String pod) {
        this.jdbc = jdbc;
        this.catalog = catalog;
        this.me = pod;
    }

    @GetMapping
    List<Course> all(HttpServletResponse res) {
        res.setHeader("X-Served-By", me);   // which instance answered
        return catalog.all();             // Redis first, then Postgres (M07-B01)
    }

    @GetMapping("/{id}")
    Course one(@PathVariable String id, HttpServletResponse res) {
        res.setHeader("X-Served-By", me);
        log.info("course {} served by {}", id, me);
        return jdbc.sql("select id, name as title, price_eur, seats_left from courses where id = ?").param(id)
            .query(Course.class).optional()
            .orElseThrow(() -> new ResponseStatusException(
                HttpStatus.NOT_FOUND, "No course " + id));
    }
    // instructors add a course (an internal admin call: the gateway does not route it)
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    Course add(@RequestBody Course c) {
        jdbc.sql("insert into courses (id, name, price_eur, seats_left) values (?, ?, ?, ?)")
            .params(c.id(), c.title(), c.priceEur(), c.seatsLeft()).update();
        log.info("course {} added by an instructor", c.id());
        return c;
    }
}
