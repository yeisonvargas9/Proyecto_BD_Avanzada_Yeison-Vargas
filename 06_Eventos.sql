-- =========================================================
-- 06_Eventos.sql
-- Proyecto: Base de Datos de un E-commerce
-- Descripción: Tabla de reportes semanales + 20 eventos programados
--              + activación del event_scheduler.
-- =========================================================

USE ecommerce_db;

-- ---------------------------------------------------------
-- Activar el programador de eventos de MySQL (obligatorio, si no
-- está en ON los CREATE EVENT existen pero nunca se ejecutan).
-- ---------------------------------------------------------
SET GLOBAL event_scheduler = ON;

-- ---------------------------------------------------------
-- Tabla requerida explícitamente por la rúbrica
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte      INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio   DATE NOT NULL,
    semana_fin      DATE NOT NULL,
    numero_ventas   INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL,
    fecha_generado  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------
-- Tablas de apoyo adicionales que necesitan los demás eventos.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS lista_reabastecimiento (
    id_item      INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    stock_actual INT NOT NULL,
    fecha_generado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ranking_productos (
    id_producto        INT PRIMARY KEY,
    unidades_vendidas  INT NOT NULL DEFAULT 0,
    fecha_actualizado  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS resumen_ventas_diarias (
    fecha           DATE PRIMARY KEY,
    numero_ventas   INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS kpis_mensuales (
    id_kpi           INT AUTO_INCREMENT PRIMARY KEY,
    anio_mes         VARCHAR(7) NOT NULL,
    total_ventas     DECIMAL(14,2) NOT NULL,
    numero_ordenes   INT NOT NULL,
    nuevos_clientes  INT NOT NULL,
    ticket_promedio  DECIMAL(12,2) NOT NULL,
    fecha_generado   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_tamano_bd (
    id_log       INT AUTO_INCREMENT PRIMARY KEY,
    tamano_mb    DECIMAL(12,2) NOT NULL,
    fecha_log    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alertas_fraude (
    id_alerta    INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente   INT NOT NULL,
    motivo       VARCHAR(255) NOT NULL,
    fecha_alerta DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reporte_proveedores_mensual (
    id_reporte      INT AUTO_INCREMENT PRIMARY KEY,
    anio_mes        VARCHAR(7) NOT NULL,
    id_proveedor    INT NOT NULL,
    unidades_vendidas INT NOT NULL,
    ingresos_generados DECIMAL(14,2) NOT NULL,
    fecha_generado  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS inconsistencias_datos (
    id_incidencia   INT AUTO_INCREMENT PRIMARY KEY,
    descripcion     VARCHAR(255) NOT NULL,
    id_referencia   INT NULL,
    fecha_detectado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS backup_log (
    id_backup     INT AUTO_INCREMENT PRIMARY KEY,
    tabla         VARCHAR(100) NOT NULL,
    filas_respaldadas INT NOT NULL,
    fecha_backup  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

-- ---------------------------------------------------------
-- 1. evt_generate_weekly_sales_report
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_weekly_sales_report$$
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL (8 - WEEKDAY(CURRENT_DATE)) DAY)
DO
BEGIN
    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, numero_ventas, total_vendido)
    SELECT
        CURDATE() - INTERVAL 7 DAY,
        CURDATE() - INTERVAL 1 DAY,
        COUNT(*),
        COALESCE(SUM(total), 0)
    FROM ventas
    WHERE fecha_venta BETWEEN (CURDATE() - INTERVAL 7 DAY) AND (CURDATE() - INTERVAL 1 SECOND);
END$$

-- ---------------------------------------------------------
-- 2. evt_cleanup_temp_tables_daily
--    Nota: este proyecto no genera tablas temporales persistentes
--    (TEMPORARY TABLE de MySQL se auto-eliminan al cerrar la sesión).
--    Se deja el evento como plantilla para limpiar tablas de trabajo
--    con prefijo 'tmp_' si en el futuro se crean.
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily$$
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO
BEGIN
    -- Ejemplo de uso futuro:
    -- DROP TEMPORARY TABLE IF EXISTS tmp_reporte_diario;
    INSERT INTO inconsistencias_datos (descripcion)
    VALUES ('evt_cleanup_temp_tables_daily ejecutado (sin tablas temporales que limpiar)');
END$$

-- ---------------------------------------------------------
-- 3. evt_archive_old_logs_monthly
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_archive_old_logs_monthly$$
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    DELETE FROM log_cambio_estado_pedido WHERE fecha_cambio < NOW() - INTERVAL 6 MONTH;
    DELETE FROM log_cambios_precio        WHERE fecha_cambio < NOW() - INTERVAL 6 MONTH;
    DELETE FROM log_clientes_nuevos       WHERE fecha_log    < NOW() - INTERVAL 6 MONTH;
END$$

-- ---------------------------------------------------------
-- 4. evt_deactivate_expired_promotions_hourly
--    Nota: el esquema no incluye tabla de promociones/códigos de
--    descuento (no estaba en los requisitos de entidades del punto 2).
--    Se deja el evento documentado; se activaría al crear esa tabla.
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly$$
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    -- UPDATE promociones SET activa = FALSE WHERE fecha_fin < NOW() AND activa = TRUE;
    INSERT INTO inconsistencias_datos (descripcion)
    VALUES ('evt_deactivate_expired_promotions_hourly: no existe tabla promociones en el esquema base');
END$$

-- ---------------------------------------------------------
-- 5. evt_recalculate_customer_loyalty_tiers_nightly
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly$$
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO
BEGIN
    UPDATE clientes
    SET total_gastado = (
        SELECT COALESCE(SUM(v.total), 0) FROM ventas v WHERE v.id_cliente = clientes.id_cliente
    );
END$$

-- ---------------------------------------------------------
-- 6. evt_generate_reorder_list_daily (umbral: 20 unidades)
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_reorder_list_daily$$
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR)
DO
BEGIN
    INSERT INTO lista_reabastecimiento (id_producto, stock_actual)
    SELECT id_producto, stock FROM productos WHERE stock < 20 AND activo = TRUE;
END$$

-- ---------------------------------------------------------
-- 7. evt_rebuild_indexes_weekly
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly$$
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL (8 - WEEKDAY(CURRENT_DATE)) DAY + INTERVAL 4 HOUR)
DO
BEGIN
    ANALYZE TABLE productos, ventas, detalle_ventas, clientes;
END$$

-- ---------------------------------------------------------
-- 8. evt_suspend_inactive_accounts_quarterly
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly$$
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO inconsistencias_datos (descripcion, id_referencia)
    SELECT CONCAT('Cliente sin actividad hace más de 1 año: ', c.id_cliente), c.id_cliente
    FROM clientes c
    WHERE c.fecha_ultimo_pedido IS NOT NULL
      AND c.fecha_ultimo_pedido < NOW() - INTERVAL 1 YEAR;
    -- En un esquema con columna 'cuenta_activa' en clientes, aquí se
    -- haría el UPDATE que la desactiva; se deja registrado en el log
    -- porque esa columna no forma parte del esquema base.
END$$

-- ---------------------------------------------------------
-- 9. evt_aggregate_daily_sales_data
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data$$
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 30 MINUTE)
DO
BEGIN
    INSERT INTO resumen_ventas_diarias (fecha, numero_ventas, total_vendido)
    SELECT CURDATE() - INTERVAL 1 DAY, COUNT(*), COALESCE(SUM(total), 0)
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE() - INTERVAL 1 DAY
    ON DUPLICATE KEY UPDATE
        numero_ventas = VALUES(numero_ventas),
        total_vendido = VALUES(total_vendido);
END$$

-- ---------------------------------------------------------
-- 10. evt_check_data_consistency_nightly
--     (ejemplo: ventas sin ningún detalle asociado)
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_check_data_consistency_nightly$$
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO
BEGIN
    INSERT INTO inconsistencias_datos (descripcion, id_referencia)
    SELECT CONCAT('Venta sin detalle: id_venta='), v.id_venta
    FROM ventas v
    LEFT JOIN detalle_ventas d ON v.id_venta = d.id_venta
    WHERE d.id_detalle IS NULL;
END$$

-- ---------------------------------------------------------
-- 11. evt_send_birthday_greetings_daily
--     Nota: clientes no almacena fecha de nacimiento en el esquema
--     base (no era un atributo requerido). El evento queda listo
--     para activarse si se agrega esa columna en el futuro.
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_send_birthday_greetings_daily$$
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 6 HOUR)
DO
BEGIN
    -- SELECT id_cliente, nombre, email FROM clientes
    -- WHERE MONTH(fecha_nacimiento) = MONTH(CURDATE())
    --   AND DAY(fecha_nacimiento) = DAY(CURDATE());
    INSERT INTO inconsistencias_datos (descripcion)
    VALUES ('evt_send_birthday_greetings_daily: falta columna fecha_nacimiento en clientes');
END$$

-- ---------------------------------------------------------
-- 12. evt_update_product_rankings_hourly
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_update_product_rankings_hourly$$
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    REPLACE INTO ranking_productos (id_producto, unidades_vendidas)
    SELECT id_producto, SUM(cantidad)
    FROM detalle_ventas
    GROUP BY id_producto;
END$$

-- ---------------------------------------------------------
-- 13. evt_backup_critical_tables_daily
--     Nota: MySQL no puede ejecutar mysqldump desde un EVENT (eso
--     corre a nivel de sistema operativo, no de motor de BD). Como
--     aproximación dentro del motor, se guarda un conteo de filas por
--     tabla crítica como comprobación de integridad diaria.
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_backup_critical_tables_daily$$
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO
BEGIN
    INSERT INTO backup_log (tabla, filas_respaldadas)
    SELECT 'productos', COUNT(*) FROM productos
    UNION ALL SELECT 'clientes', COUNT(*) FROM clientes
    UNION ALL SELECT 'ventas', COUNT(*) FROM ventas
    UNION ALL SELECT 'detalle_ventas', COUNT(*) FROM detalle_ventas;
END$$

-- ---------------------------------------------------------
-- 14. evt_clear_abandoned_carts_daily
--     Nota: no existe tabla de carritos en el esquema base (ver
--     supuesto de la consulta #10 en 02_Consultas_Avanzadas.sql).
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_clear_abandoned_carts_daily$$
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 4 HOUR)
DO
BEGIN
    -- DELETE FROM carritos WHERE fecha_actualizacion < NOW() - INTERVAL 72 HOUR;
    INSERT INTO inconsistencias_datos (descripcion)
    VALUES ('evt_clear_abandoned_carts_daily: no existe tabla de carritos en el esquema base');
END$$

-- ---------------------------------------------------------
-- 15. evt_calculate_monthly_kpis
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_calculate_monthly_kpis$$
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO kpis_mensuales (anio_mes, total_ventas, numero_ordenes, nuevos_clientes, ticket_promedio)
    SELECT
        DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m'),
        COALESCE((SELECT SUM(total) FROM ventas WHERE DATE_FORMAT(fecha_venta, '%Y-%m') = DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m')), 0),
        (SELECT COUNT(*) FROM ventas WHERE DATE_FORMAT(fecha_venta, '%Y-%m') = DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m')),
        (SELECT COUNT(*) FROM clientes WHERE DATE_FORMAT(fecha_registro, '%Y-%m') = DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m')),
        COALESCE((SELECT AVG(total) FROM ventas WHERE DATE_FORMAT(fecha_venta, '%Y-%m') = DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m')), 0);
END$$

-- ---------------------------------------------------------
-- 16. evt_refresh_materialized_views_nightly
--     Nota: MySQL no tiene vistas materializadas nativas (a diferencia
--     de PostgreSQL). Se simula "refrescando" la tabla resumen_ventas_diarias,
--     que cumple ese mismo propósito de acelerar reportes.
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_refresh_materialized_views_nightly$$
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 5 HOUR)
DO
BEGIN
    REPLACE INTO ranking_productos (id_producto, unidades_vendidas)
    SELECT id_producto, SUM(cantidad) FROM detalle_ventas GROUP BY id_producto;
END$$

-- ---------------------------------------------------------
-- 17. evt_log_database_size_weekly
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_log_database_size_weekly$$
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL (8 - WEEKDAY(CURRENT_DATE)) DAY)
DO
BEGIN
    INSERT INTO log_tamano_bd (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.tables
    WHERE table_schema = 'ecommerce_db';
END$$

-- ---------------------------------------------------------
-- 18. evt_detect_fraudulent_activity_hourly
--     Regla simple: más de 3 ventas 'Cancelado' del mismo cliente
--     en la última hora se marca como sospechoso.
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_detect_fraudulent_activity_hourly$$
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO alertas_fraude (id_cliente, motivo)
    SELECT id_cliente, 'Más de 3 pedidos cancelados en la última hora'
    FROM ventas
    WHERE estado = 'Cancelado' AND fecha_venta >= NOW() - INTERVAL 1 HOUR
    GROUP BY id_cliente
    HAVING COUNT(*) > 3;
END$$

-- ---------------------------------------------------------
-- 19. evt_generate_supplier_performance_report_monthly
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_supplier_performance_report_monthly$$
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO reporte_proveedores_mensual (anio_mes, id_proveedor, unidades_vendidas, ingresos_generados)
    SELECT
        DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m'),
        pr.id_proveedor,
        COALESCE(SUM(d.cantidad), 0),
        COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0)
    FROM proveedores pr
    LEFT JOIN productos p ON pr.id_proveedor = p.id_proveedor
    LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
    LEFT JOIN ventas v ON d.id_venta = v.id_venta
        AND DATE_FORMAT(v.fecha_venta, '%Y-%m') = DATE_FORMAT(NOW() - INTERVAL 1 MONTH, '%Y-%m')
    GROUP BY pr.id_proveedor;
END$$

-- ---------------------------------------------------------
-- 20. evt_purge_soft_deleted_records_weekly
--     Nota: el esquema base no implementa borrado lógico (columna
--     tipo 'eliminado_en'); el único campo similar es productos.activo,
--     que indica "descontinuado", no "eliminado". Se deja documentado
--     el patrón que se activaría si se agrega esa columna.
-- ---------------------------------------------------------
DROP EVENT IF EXISTS evt_purge_soft_deleted_records_weekly$$
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL (8 - WEEKDAY(CURRENT_DATE)) DAY)
DO
BEGIN
    -- DELETE FROM productos WHERE activo = FALSE AND fecha_eliminacion < NOW() - INTERVAL 30 DAY;
    INSERT INTO inconsistencias_datos (descripcion)
    VALUES ('evt_purge_soft_deleted_records_weekly: no existe columna de fecha de eliminación en el esquema base');
END$$

DELIMITER ;