package com.allcs.enrollment;

import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.service.annotation.GetExchange;
import org.springframework.web.service.annotation.HttpExchange;

@HttpExchange("/courses")
public interface CatalogClient {

    @GetExchange("/{id}")
    CourseInfo course(@PathVariable String id);
}
