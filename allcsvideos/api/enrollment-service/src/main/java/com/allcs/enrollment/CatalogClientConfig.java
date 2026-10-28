package com.allcs.enrollment;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.support.RestClientHttpServiceGroupConfigurer;
import org.springframework.web.service.registry.ImportHttpServices;

// M19-L04: base URL lb://catalog-service, timeouts in config
@Configuration
@ImportHttpServices(group = "catalog-service", types = CatalogClient.class)
class CatalogClientConfig {

    @Bean
    RestClientHttpServiceGroupConfigurer catalogErrors() {
        return groups -> groups.filterByName("catalog-service")
                .forEachClient((group, builder) -> builder
                    .defaultStatusHandler(s -> s.value() == 404,
                        (req, res) -> {
                            throw new CourseNotFound(req.getURI());
                        }));
    }
}
