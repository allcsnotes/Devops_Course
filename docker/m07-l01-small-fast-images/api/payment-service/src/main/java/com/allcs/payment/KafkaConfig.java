package com.allcs.payment;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.KafkaAdmin;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.support.converter.RecordMessageConverter;
import org.springframework.kafka.support.converter.StringJacksonJsonMessageConverter;
import org.springframework.util.backoff.FixedBackOff;

@Configuration
class KafkaConfig {

    @Bean   // JSON value -> the listener's parameter type
    RecordMessageConverter converter() {
        return new StringJacksonJsonMessageConverter();
    }

    @Bean   // module 17, lesson 3: 3 retries, 1 second apart, then <topic>-dlt
    DefaultErrorHandler errorHandler(KafkaTemplate<String, String> template) {
        return new DefaultErrorHandler(new DeadLetterPublishingRecoverer(template),
                new FixedBackOff(1_000, 3));
    }

    @Bean   // each service creates the topics it consumes
    KafkaAdmin.NewTopics topics() {
        return new KafkaAdmin.NewTopics(
            TopicBuilder.name("payment.commands").partitions(3).build(),
            TopicBuilder.name("payment.commands-dlt").partitions(3).build());
    }
}
