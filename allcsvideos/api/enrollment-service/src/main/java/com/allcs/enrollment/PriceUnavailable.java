package com.allcs.enrollment;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.ErrorResponseException;

public class PriceUnavailable extends ErrorResponseException {
    public PriceUnavailable(Throwable cause) {
        super(HttpStatus.SERVICE_UNAVAILABLE, ProblemDetail.forStatusAndDetail(
                HttpStatus.SERVICE_UNAVAILABLE, "Price unavailable, try again"), cause);
    }
}
