package com.allcs.enrollment;

import static com.allcs.enrollment.SagaState.*;

import java.time.Duration;
import java.time.OffsetDateTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

// the orchestrator from M19-L05: a state machine, saved in saga_instance after every step
@Service
public class EnrollmentSaga {
    private static final Logger log = LoggerFactory.getLogger(EnrollmentSaga.class);
    private final JdbcClient jdbc;
    private final Outbox outbox;
    private final Inbox inbox;
    private final Duration stepTimeout;

    EnrollmentSaga(JdbcClient jdbc, Outbox outbox, Inbox inbox,
                   @Value("${saga.step-timeout}") Duration stepTimeout) {
        this.jdbc = jdbc;
        this.outbox = outbox;
        this.inbox = inbox;
        this.stepTimeout = stepTimeout;
    }

    record Saga(long id, SagaState state, String studentId, String courseId,
                String courseTitle, int amountEur, OffsetDateTime deadline) {}

    @Transactional
    public long start(String studentId, CourseInfo course) {
        long id = jdbc.sql("""
                insert into enrollments
                    (student_id, course_id, course_title, price_eur, status)
                values (?, ?, ?, ?, 'PENDING') returning id""")
            .params(studentId, course.id(), course.title(), course.priceEur())
            .query(Long.class).single();
        jdbc.sql("""
                insert into saga_instance (id, state, amount_eur, deadline)
                values (?, 'STARTED', ?, ?)""")
            .params(id, course.priceEur(), deadline()).update();
        outbox.add("catalog.commands", id,
            CatalogCommand.of(id, "RESERVE_SEAT", course.id()));
        log.info("saga {}: STARTED ({} wants {}, {} EUR)",
                id, studentId, course.id(), course.priceEur());
        return id;
    }

    @KafkaListener(topics = "enrollment.replies", groupId = "enrollment")
    @Transactional
    public void on(SagaReply r) {
        if (!inbox.firstTime(r.messageId())) return;
        Saga s = load(r.sagaId());               // row lock
        switch (r.type()) {
            case "SEAT_RESERVED" -> {
                if (!expect(s, STARTED, r)) return;
                move(s, SEAT_RESERVED, null);
                outbox.add("payment.commands", s.id(),
                    PaymentCommand.of(s.id(), "CHARGE",
                                      s.studentId(), s.amountEur()));
            }
            case "SEAT_REJECTED" -> {
                if (!expect(s, STARTED, r)) return;
                finish(s, CANCELLED, r.reason());   // nothing to undo
            }
            case "PAYMENT_COMPLETED" -> {           // the pivot
                if (!expect(s, SEAT_RESERVED, r)) return;
                move(s, PAID, s.amountEur() + " EUR");
                outbox.add("catalog.commands", s.id(),
                    CatalogCommand.of(s.id(), "CONFIRM_SEAT", s.courseId()));
            }
            case "PAYMENT_DECLINED" -> {
                if (!expect(s, SEAT_RESERVED, r)) return;
                compensate(s, r.reason());
                outbox.add("catalog.commands", s.id(),
                    CatalogCommand.of(s.id(), "RELEASE_SEAT", s.courseId()));
            }
            case "SEAT_CONFIRMED" -> {
                if (!expect(s, PAID, r)) return;
                finish(s, CONFIRMED, null);
                outbox.add("enrollments", s.studentId(),
                    EnrollmentConfirmed.of(s.id(), s.studentId(),
                                           s.courseId(), s.courseTitle()));
            }
            case "PAYMENT_REFUNDED" -> {     // reverse order: seat next
                if (!expect(s, COMPENSATING, r)) return;
                outbox.add("catalog.commands", s.id(),
                    CatalogCommand.of(s.id(), "RELEASE_SEAT", s.courseId()));
            }
            case "SEAT_RELEASED" -> {
                if (!expect(s, COMPENSATING, r)) return;
                finish(s, CANCELLED, null);
            }
            default -> throw new IllegalArgumentException(r.type());
        }
    }

    // called by SagaTimeouts for sagas past their deadline
    @Transactional
    public void timeOut(long id) {
        Saga s = load(id);                       // row lock again
        if (s.deadline().isAfter(OffsetDateTime.now())) {
            return;                      // a reply just moved it
        }
        switch (s.state()) {
            case STARTED -> {
                compensate(s, "timed out waiting for catalog");
                outbox.add("catalog.commands", id,
                    CatalogCommand.of(id, "RELEASE_SEAT", s.courseId()));
            }
            case SEAT_RESERVED -> {      // maybe charged already
                compensate(s, "timed out waiting for payment");
                outbox.add("payment.commands", id,
                    PaymentCommand.of(id, "REFUND", s.studentId(), s.amountEur()));
            }
            default -> { }               // after the pivot: never undo
        }
    }

    private Saga load(long id) {
        return jdbc.sql("""
                select s.id, s.state, e.student_id, e.course_id, e.course_title,
                       s.amount_eur, s.deadline
                from saga_instance s join enrollments e on e.id = s.id
                where s.id = ? for update of s""")
            .param(id).query(Saga.class).single();
    }

    private boolean expect(Saga s, SagaState state, SagaReply r) {
        if (s.state() == state) return true;
        log.info("saga {}: late {} ignored in {}", s.id(), r.type(), s.state());
        return false;
    }

    private void move(Saga s, SagaState to, String note) {
        jdbc.sql("""
                update saga_instance
                set state = ?, deadline = ?, updated_at = now()
                where id = ?""")
            .params(to.name(), deadline(), s.id()).update();
        log.info("saga {}: {} -> {}{}", s.id(), s.state(), to,
                note == null ? "" : " (" + note + ")");
    }

    private void compensate(Saga s, String reason) {
        move(s, COMPENSATING, reason);
        jdbc.sql("update enrollments set reason = ? where id = ?").params(reason, s.id()).update();
    }

    private void finish(Saga s, SagaState to, String reason) {
        move(s, to, reason);
        jdbc.sql("""
                update enrollments set status = ?, reason = coalesce(?, reason), updated_at = now()
                where id = ?""")
            .params(to.name(), reason, s.id()).update();
    }

    private OffsetDateTime deadline() {
        return OffsetDateTime.now().plus(stepTimeout);
    }
}
