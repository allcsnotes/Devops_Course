package com.allcs.catalog;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

// catalog's local steps; always called inside the listener's transaction
@Service
class Seats {
    private final JdbcClient jdbc;

    Seats(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    SagaReply reserve(long sagaId, String courseId) {
        var held = jdbc.sql("select status from seat_holds where saga_id = ?")
            .param(sagaId).query(String.class).optional();
        if (held.isPresent()) {                       // seen this saga before: same answer
            return held.get().equals("RELEASED")
                ? SagaReply.of(sagaId, "SEAT_REJECTED", null, "already released")
                : SagaReply.of(sagaId, "SEAT_RESERVED", price(courseId), null);
        }
        var price = jdbc.sql("""
                update courses set seats_left = seats_left - 1
                where id = ? and seats_left > 0
                returning price_eur""")
            .param(courseId).query(Integer.class).optional();
        if (price.isEmpty()) {
            return SagaReply.of(sagaId, "SEAT_REJECTED", null, "no seats left in " + courseId);
        }
        jdbc.sql("insert into seat_holds (saga_id, course_id, status) values (?, ?, 'HELD')")
            .params(sagaId, courseId).update();
        return SagaReply.of(sagaId, "SEAT_RESERVED", price.get(), null);
    }

    SagaReply confirm(long sagaId) {
        jdbc.sql("""
                update seat_holds set status = 'CONFIRMED', updated_at = now()
                where saga_id = ? and status = 'HELD'""")
            .param(sagaId).update();
        return SagaReply.of(sagaId, "SEAT_CONFIRMED", null, null);
    }

    SagaReply release(long sagaId, String courseId) {
        var course = jdbc.sql("""
                update seat_holds set status = 'RELEASED', updated_at = now()
                where saga_id = ? and status = 'HELD'
                returning course_id""")
            .param(sagaId).query(String.class).optional();
        if (course.isEmpty()) {                       // nothing held: a no-op, but remember it
            jdbc.sql("""
                    insert into seat_holds (saga_id, course_id, status)
                    values (?, ?, 'RELEASED') on conflict (saga_id) do nothing""")
                .params(sagaId, courseId).update();
            return SagaReply.of(sagaId, "SEAT_RELEASED", null, "nothing to release");
        }
        jdbc.sql("update courses set seats_left = seats_left + 1 where id = ?")
            .param(course.get()).update();
        return SagaReply.of(sagaId, "SEAT_RELEASED", null, null);
    }

    private int price(String courseId) {
        return jdbc.sql("select price_eur from courses where id = ?")
            .param(courseId).query(Integer.class).single();
    }
}
