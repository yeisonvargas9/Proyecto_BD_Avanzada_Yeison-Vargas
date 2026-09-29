-- =========================================================
-- 05_Triggers.sql
-- Proyecto: Base de Datos de un E-commerce
-- Descripción: Tabla de auditoría de precios + 20 triggers.
-- =========================================================

USE ecommerce_db;

-- ---------------------------------------------------------
-- Columnas adicionales requeridas por algunos triggers de negocio.
-- El esquema base (01_Esquema_y_Datos.sql) no las incluye porque no
-- eran obligatorias para las entidades originales; se agregan aquí
-- porque triggers específicos de este archivo las necesitan.
-- Requiere MySQL 8.0.29+ (soporta "ADD COLUMN IF NOT EXISTS").
-- ---------------------------------------------------------
-- Requiere que estas columnas no existan aún (primera ejecución del script).
-- Si necesitas volver a correr este archivo más de una vez, comenta estas
-- 4 líneas después de la primera ejecución exitosa.
ALTER TABLE clientes   ADD COLUMN total_gastado        DECIMAL(12,2) NOT NULL DEFAULT 0;
ALTER TABLE clientes   ADD COLUMN fecha_ultimo_pedido  DATETIME NULL;
ALTER TABLE productos  ADD COLUMN fecha_modificacion   DATETIME NULL;
ALTER TABLE categorias ADD COLUMN num_productos        INT NOT NULL DEFAULT 0;

-- ---------------------------------------------------------
-- Tablas de apoyo que los triggers necesitan (auditoría, alertas, etc.)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_producto     INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo    DECIMAL(10,2) NOT NULL,
    fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_clientes_nuevos (
    id_log      INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    fecha_log   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_cambio_estado_pedido (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_venta        INT NOT NULL,
    estado_anterior VARCHAR(30) NOT NULL,
    estado_nuevo    VARCHAR(30) NOT NULL,
    fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alertas_stock (
    id_alerta    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    stock_actual INT NOT NULL,
    fecha_alerta DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ventas_archivadas (
    id_venta        INT NOT NULL,
    id_cliente      INT NOT NULL,
    fecha_venta     DATETIME NOT NULL,
    estado          VARCHAR(30) NOT NULL,
    total           DECIMAL(12,2) NOT NULL,
    fecha_archivado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Tabla mínima de referidos, solo para poder implementar el trigger 17.
CREATE TABLE IF NOT EXISTS referidos (
    id_referido         INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente          INT NOT NULL,
    id_cliente_referido INT NOT NULL
);

-- Tabla de log de permisos (ver nota en el trigger 18 más abajo).
CREATE TABLE IF NOT EXISTS log_cambios_permisos (
    id_log      INT AUTO_INCREMENT PRIMARY KEY,
    descripcion VARCHAR(255) NOT NULL,
    fecha_log   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

-- ---------------------------------------------------------
-- 1. trg_audit_precio_producto_after_update
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update$$
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo)
        VALUES (OLD.id_producto, OLD.precio, NEW.precio);
    END IF;
END$$

-- ---------------------------------------------------------
-- 2. trg_check_stock_before_insert_venta
--    (se aplica sobre detalle_ventas, que es donde realmente
--     se conoce el producto y la cantidad a vender)
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta$$
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock_disponible INT;
    SELECT stock INTO v_stock_disponible FROM productos WHERE id_producto = NEW.id_producto;

    IF v_stock_disponible < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta de este producto.';
    END IF;
END$$

-- ---------------------------------------------------------
-- 3. trg_update_stock_after_insert_venta
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta$$
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
    SET stock = stock - NEW.cantidad
    WHERE id_producto = NEW.id_producto;
END$$

-- ---------------------------------------------------------
-- 4. trg_prevent_delete_categoria_with_products
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products$$
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_cantidad INT;
    SELECT COUNT(*) INTO v_cantidad FROM productos WHERE id_categoria = OLD.id_categoria;

    IF v_cantidad > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar una categoría que tiene productos asociados.';
    END IF;
END$$

-- ---------------------------------------------------------
-- 5. trg_log_new_customer_after_insert
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert$$
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_clientes_nuevos (id_cliente) VALUES (NEW.id_cliente);
END$$

-- ---------------------------------------------------------
-- 6. trg_update_total_gastado_cliente
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente$$
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
    SET total_gastado = total_gastado + NEW.total
    WHERE id_cliente = NEW.id_cliente;
END$$

-- ---------------------------------------------------------
-- 7. trg_set_fecha_modificacion_producto
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto$$
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = NOW();
END$$

-- ---------------------------------------------------------
-- 8. trg_prevent_negative_stock
--    (refuerza a nivel de trigger la regla ya cubierta por el
--     CHECK del archivo 01, dando un mensaje de error más claro)
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_negative_stock$$
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El stock de un producto no puede quedar en un valor negativo.';
    END IF;
END$$

-- ---------------------------------------------------------
-- 9. trg_capitalize_nombre_cliente
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente$$
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre, 1)), LOWER(SUBSTRING(NEW.nombre, 2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
END$$

-- ---------------------------------------------------------
-- 10. trg_recalculate_total_venta_on_detalle_change
--     Se implementa con 3 triggers (INSERT/UPDATE/DELETE) porque
--     MySQL no permite un solo trigger para varios eventos.
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_recalc_total_venta_after_insert_detalle$$
CREATE TRIGGER trg_recalc_total_venta_after_insert_detalle
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas SET total = fn_CalcularTotalVenta(NEW.id_venta) WHERE id_venta = NEW.id_venta;
END$$

DROP TRIGGER IF EXISTS trg_recalc_total_venta_after_update_detalle$$
CREATE TRIGGER trg_recalc_total_venta_after_update_detalle
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas SET total = fn_CalcularTotalVenta(NEW.id_venta) WHERE id_venta = NEW.id_venta;
END$$

DROP TRIGGER IF EXISTS trg_recalc_total_venta_after_delete_detalle$$
CREATE TRIGGER trg_recalc_total_venta_after_delete_detalle
AFTER DELETE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas SET total = fn_CalcularTotalVenta(OLD.id_venta) WHERE id_venta = OLD.id_venta;
END$$

-- ---------------------------------------------------------
-- 11. trg_log_order_status_change
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_order_status_change$$
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado THEN
        INSERT INTO log_cambio_estado_pedido (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END$$

-- ---------------------------------------------------------
-- 12. trg_prevent_price_zero_or_less
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less$$
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El precio de un producto debe ser mayor que cero.';
    END IF;
END$$

-- ---------------------------------------------------------
-- 13. trg_send_stock_alert_on_low_stock (umbral: 20 unidades)
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock$$
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 20 AND OLD.stock >= 20 THEN
        INSERT INTO alertas_stock (id_producto, stock_actual)
        VALUES (NEW.id_producto, NEW.stock);
    END IF;
END$$

-- ---------------------------------------------------------
-- 14. trg_archive_deleted_venta
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_archive_deleted_venta$$
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, fecha_venta, estado, total)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.estado, OLD.total);
END$$

-- ---------------------------------------------------------
-- 15. trg_validate_email_format_on_customer
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer$$
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El formato del correo electrónico no es válido.';
    END IF;
END$$

-- ---------------------------------------------------------
-- 16. trg_update_last_order_date_customer
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer$$
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
    SET fecha_ultimo_pedido = NEW.fecha_venta
    WHERE id_cliente = NEW.id_cliente;
END$$

-- ---------------------------------------------------------
-- 17. trg_prevent_self_referral
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_self_referral$$
CREATE TRIGGER trg_prevent_self_referral
BEFORE INSERT ON referidos
FOR EACH ROW
BEGIN
    IF NEW.id_cliente = NEW.id_cliente_referido THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un cliente no puede referirse a sí mismo.';
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------
-- 18. trg_log_permission_changes  — LIMITACIÓN DOCUMENTADA
--     MySQL no permite crear triggers sobre sentencias DDL como
--     GRANT o REVOKE (solo existen triggers para INSERT/UPDATE/DELETE
--     sobre tablas). Por lo tanto este requerimiento no puede
--     implementarse como un trigger real en MySQL.
--     La alternativa estándar en producción es activar el plugin
--     de servidor 'audit_log', o registrar manualmente cada cambio
--     de permisos en la tabla log_cambios_permisos creada arriba,
--     por ejemplo:
--     INSERT INTO log_cambios_permisos (descripcion)
--     VALUES ('Se otorgó SELECT a Gerente_Marketing sobre ventas');
-- ---------------------------------------------------------

DELIMITER $$

-- ---------------------------------------------------------
-- 19. trg_assign_default_category_on_null
--     Requiere que exista una categoría llamada 'General'.
-- ---------------------------------------------------------
INSERT INTO categorias (nombre, descripcion)
SELECT 'General', 'Categoría asignada automáticamente cuando no se especifica una'
WHERE NOT EXISTS (SELECT 1 FROM categorias WHERE nombre = 'General')$$

DROP TRIGGER IF EXISTS trg_assign_default_category_on_null$$
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    DECLARE v_id_general INT;
    IF NEW.id_categoria IS NULL THEN
        SELECT id_categoria INTO v_id_general FROM categorias WHERE nombre = 'General' LIMIT 1;
        SET NEW.id_categoria = v_id_general;
    END IF;
END$$

-- ---------------------------------------------------------
-- 20. trg_update_producto_count_in_categoria
--     Se implementa con 3 triggers: alta, baja y cambio de categoría.
-- ---------------------------------------------------------
DROP TRIGGER IF EXISTS trg_categoria_count_after_insert_producto$$
CREATE TRIGGER trg_categoria_count_after_insert_producto
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias SET num_productos = num_productos + 1 WHERE id_categoria = NEW.id_categoria;
END$$

DROP TRIGGER IF EXISTS trg_categoria_count_after_delete_producto$$
CREATE TRIGGER trg_categoria_count_after_delete_producto
AFTER DELETE ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias SET num_productos = num_productos - 1 WHERE id_categoria = OLD.id_categoria;
END$$

DROP TRIGGER IF EXISTS trg_categoria_count_after_update_producto$$
CREATE TRIGGER trg_categoria_count_after_update_producto
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.id_categoria <> NEW.id_categoria THEN
        UPDATE categorias SET num_productos = num_productos - 1 WHERE id_categoria = OLD.id_categoria;
        UPDATE categorias SET num_productos = num_productos + 1 WHERE id_categoria = NEW.id_categoria;
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------
-- Sincronizar num_productos y total_gastado con los datos que ya
-- existían antes de crear estos triggers (los triggers solo capturan
-- cambios futuros, no recalculan el pasado).
-- ---------------------------------------------------------
UPDATE categorias c
SET num_productos = (SELECT COUNT(*) FROM productos p WHERE p.id_categoria = c.id_categoria);

UPDATE clientes cl
SET total_gastado = (SELECT COALESCE(SUM(v.total), 0) FROM ventas v WHERE v.id_cliente = cl.id_cliente),
    fecha_ultimo_pedido = (SELECT MAX(v.fecha_venta) FROM ventas v WHERE v.id_cliente = cl.id_cliente);