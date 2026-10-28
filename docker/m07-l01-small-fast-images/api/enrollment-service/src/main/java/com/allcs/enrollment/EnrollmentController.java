package com.allcs.enrollment;

import java.net.URI;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

@RestController
@RequestMapping("/enrollments")
class EnrollmentController {
    private final CatalogPrices catalog;
    private final EnrollmentSaga saga;
    private final JdbcClient jdbc;

    EnrollmentController(CatalogPrices catalog, EnrollmentSaga saga, JdbcClient jdbc) {
        this.catalog = catalog;
        this.saga = saga;
        this.jdbc = jdbc;
    }

    record EnrollRequest(String courseId) {}
    record EnrollmentView(long id, String studentId, String courseId,
                          String courseTitle, int priceEur,
                          String status, String reason) {}

    @PostMapping
    ResponseEntity<EnrollmentView> enroll(@RequestBody EnrollRequest req,
                                          @AuthenticationPrincipal Jwt jwt) {
        CourseInfo course = catalog.course(req.courseId()); // HTTP
        long id = saga.start(jwt.getSubject(), course);     // saga
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}").build(id);
        return ResponseEntity.accepted().location(location)
                .body(find(id, jwt));
    }

    @GetMapping("/{id}")
    EnrollmentView find(@PathVariable long id,
                        @AuthenticationPrincipal Jwt jwt) {
        return jdbc.sql("""
                select id, student_id, course_id, course_title,
                       price_eur, status, reason
                from enrollments where id = ? and student_id = ?""")
            .params(id, jwt.getSubject())             // only your own
            .query(EnrollmentView.class).optional()
            .orElseThrow(() -> new ResponseStatusException(
                HttpStatus.NOT_FOUND, "No enrollment " + id));
    }
}
