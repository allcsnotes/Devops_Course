package com.allcs.payment;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.*;

// internal only: no gateway route points here
@RestController
class WalletController {
    private final JdbcClient jdbc;

    WalletController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    record Wallet(String studentId, int balanceEur) {}

    @GetMapping("/wallets/{studentId}")
    Wallet wallet(@PathVariable String studentId) {
        return jdbc.sql("select * from wallets where student_id = ?")
            .param(studentId).query(Wallet.class).single();
    }
}
