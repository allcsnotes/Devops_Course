package com.allcs.payment;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

// payment's local steps; always called inside the listener's transaction
@Service
class Charges {
    private final JdbcClient jdbc;

    Charges(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    SagaReply charge(long sagaId, String studentId, int amountEur) {
        var before = jdbc.sql("select status from payments where saga_id = ?")
            .param(sagaId).query(String.class).optional();
        if (before.isPresent()) {                     // seen this saga before: same answer
            return before.get().equals("CHARGED")
                ? SagaReply.of(sagaId, "PAYMENT_COMPLETED", amountEur, null)
                : SagaReply.of(sagaId, "PAYMENT_DECLINED", amountEur, "already " + before.get());
        }
        int paid = jdbc.sql("""
                update wallets set balance_eur = balance_eur - ?
                where student_id = ? and balance_eur >= ?""")
            .params(amountEur, studentId, amountEur).update();
        String status = paid == 1 ? "CHARGED" : "DECLINED";
        String reason = paid == 1 ? null : "insufficient funds";
        jdbc.sql("""
                insert into payments (saga_id, student_id, amount_eur, status, reason)
                values (?, ?, ?, ?, ?)""")
            .params(sagaId, studentId, amountEur, status, reason).update();
        return SagaReply.of(sagaId,
                paid == 1 ? "PAYMENT_COMPLETED" : "PAYMENT_DECLINED",
                amountEur, reason);
    }

    SagaReply refund(long sagaId, String studentId) {
        var amount = jdbc.sql("""
                update payments set status = 'REFUNDED'
                where saga_id = ? and status = 'CHARGED'
                returning amount_eur""")
            .param(sagaId).query(Integer.class).optional();
        if (amount.isEmpty()) {                       // nothing charged: a no-op, but remember it
            jdbc.sql("""
                    insert into payments (saga_id, student_id, amount_eur, status)
                    values (?, ?, 0, 'CANCELLED') on conflict (saga_id) do nothing""")
                .params(sagaId, studentId).update();
            return SagaReply.of(sagaId, "PAYMENT_REFUNDED", 0, "nothing to refund");
        }
        jdbc.sql("update wallets set balance_eur = balance_eur + ? where student_id = ?")
            .params(amount.get(), studentId).update();
        return SagaReply.of(sagaId, "PAYMENT_REFUNDED", amount.get(), null);
    }
}
