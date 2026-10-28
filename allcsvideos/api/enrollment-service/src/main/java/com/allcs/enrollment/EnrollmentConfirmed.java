package com.allcs.enrollment;

import java.util.UUID;

// enrollment -> notification, on enrollments
public record EnrollmentConfirmed(String messageId, long enrollmentId,
                                  String studentId, String courseId,
                                  String courseTitle) {

    static EnrollmentConfirmed of(long id, String studentId, String courseId,
                                  String courseTitle) {
        return new EnrollmentConfirmed(UUID.randomUUID().toString(), id,
                studentId, courseId, courseTitle);
    }
}
