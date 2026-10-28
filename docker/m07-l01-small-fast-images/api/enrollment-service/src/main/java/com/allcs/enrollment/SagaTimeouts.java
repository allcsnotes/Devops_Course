package com.allcs.enrollment;

import java.util.concurrent.TimeUnit;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
class SagaTimeouts {
    private final JdbcClient jdbc;
    private final EnrollmentSaga saga;

    SagaTimeouts(JdbcClient jdbc, EnrollmentSaga saga) {
        this.jdbc = jdbc;
        this.saga = saga;
    }

    @Scheduled(fixedDelay = 5, timeUnit = TimeUnit.SECONDS)
    @SchedulerLock(name = "saga-timeouts", lockAtMostFor = "1m")   // one instance at a time
    public void check() {
        var expired = jdbc.sql("""
                select id from saga_instance
                where state in ('STARTED', 'SEAT_RESERVED') and deadline < now()""")
            .query(Long.class).list();
        expired.forEach(saga::timeOut);
    }
}
