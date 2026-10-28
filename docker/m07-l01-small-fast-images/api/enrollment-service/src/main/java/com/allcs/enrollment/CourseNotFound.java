package com.allcs.enrollment;

import java.net.URI;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.ErrorResponseException;

public class CourseNotFound extends ErrorResponseException {
    public CourseNotFound(URI uri) {
        super(HttpStatus.NOT_FOUND, ProblemDetail.forStatusAndDetail(
                HttpStatus.NOT_FOUND, "Catalog has no " + uri.getPath()), null);
    }
}
