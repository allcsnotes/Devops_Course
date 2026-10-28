package com.allcs.enrollment;

// enrollment's own view of a course: only the fields it needs
public record CourseInfo(String id, String title, int priceEur, int seatsLeft) {}
