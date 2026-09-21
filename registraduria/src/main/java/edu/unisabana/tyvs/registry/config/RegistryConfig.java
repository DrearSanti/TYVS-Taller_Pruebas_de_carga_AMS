package edu.unisabana.tyvs.registry.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import edu.unisabana.tyvs.registry.application.port.out.RegistryRepositoryPort;
import edu.unisabana.tyvs.registry.application.usecase.Registry;
import edu.unisabana.tyvs.registry.infrastructure.persistence.RegistryRepository;
import javax.sql.DataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Cableado de la aplicacion (composition root).
 *
 * La URL JDBC se lee de una propiedad, con un valor por defecto, en vez de
 * estar escrita en el codigo. No es cosmetico: permite que cada prueba de
 * integracion use su propia base en memoria y no contamine a las demas, y
 * evita tener que declarar beans alternativos en la prueba.
 *
 * Ese ultimo punto tiene una trampa que costo un build en rojo: si una prueba
 * declara un @TestConfiguration con un @Bean llamado igual que uno de aqui
 * (el nombre del bean es el nombre del METODO), Spring aborta el arranque con
 * BeanDefinitionOverrideException. Parametrizar la URL hace innecesarios esos
 * beans duplicados.
 *
 * El DataSource usa HikariCP. Antes cada operacion abria una conexion nueva
 * con DriverManager, y registerVoter hace dos operaciones por peticion, de modo
 * que con 600 usuarios virtuales se creaban y destruian miles de conexiones por
 * segundo. Ese era el cuello de botella del taller de carga.
 */
@Configuration
public class RegistryConfig {

    @Bean
    public DataSource dataSource(
            @Value("${registry.jdbc-url:jdbc:h2:mem:regdb;DB_CLOSE_DELAY=-1}") String jdbcUrl) {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(jdbcUrl);
        config.setMaximumPoolSize(20);
        config.setPoolName("registry-pool");
        return new HikariDataSource(config);
    }

    @Bean
    public RegistryRepositoryPort registryRepositoryPort(DataSource dataSource) throws Exception {
        RegistryRepository repo = new RegistryRepository(dataSource);
        repo.initSchema();
        return repo;
    }

    @Bean
    public Registry registry(RegistryRepositoryPort port) {
        return new Registry(port);
    }
}