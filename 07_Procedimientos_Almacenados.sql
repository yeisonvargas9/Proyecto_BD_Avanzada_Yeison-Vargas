-- =========================================================
-- 07_Procedimientos_Almacenados.sql
-- Proyecto: Base de Datos de un E-commerce
-- Descripción: 20 procedimientos almacenados para operaciones
--              complejas y transaccionales.
-- =========================================================

USE ecommerce_db;

-- ---------------------------------------------------------
-- Tablas de apoyo que necesitan algunos procedimientos.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS ajustes_stock (
    id_ajuste    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    cantidad     INT NOT NULL,   -- puede ser negativo (salida) o positivo (entrada)
    motivo       VARCHAR(255) NOT NULL,
    fecha_ajuste DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS creditos_devolucion (
    id_credito   INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente   INT NOT NULL,
    monto        DECIMAL(12,2) NOT NULL,
    motivo       VARCHAR(255) NOT NULL,
    fecha_credito DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS resenas_producto (
    id_resena    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    id_cliente   INT NOT NULL,
    calificacion TINYINT NOT NULL,
    comentario   TEXT NULL,
    fecha_resena DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_calificacion_valida CHECK (calificacion BETWEEN 1 AND 5)
);

DELIMITER $$

-- ---------------------------------------------------------
-- 1. sp_RealizarNuevaVenta
--    Procesa una venta con uno o varios productos de forma
--    transaccional. p_items recibe un arreglo JSON, ej:
--    '[{"id_producto":1,"cantidad":2},{"id_producto":3,"cantidad":1}]'
--    El trigger trg_check_stock_before_insert_venta valida el stock
--    de cada línea; si alguna falla, se revierte toda la venta.
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta$$
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_items JSON
)
BEGIN
    DECLARE v_id_venta INT;
    DECLARE v_total_items INT;
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_precio DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO ventas (id_cliente, estado, total) VALUES (p_id_cliente, 'Pendiente de Pago', 0);
    SET v_id_venta = LAST_INSERT_ID();

    SET v_total_items = JSON_LENGTH(p_items);

    WHILE v_i < v_total_items DO
        SET v_id_producto = JSON_UNQUOTE(JSON_EXTRACT(p_items, CONCAT('$[', v_i, '].id_producto')));
        SET v_cantidad    = JSON_UNQUOTE(JSON_EXTRACT(p_items, CONCAT('$[', v_i, '].cantidad')));

        SELECT precio INTO v_precio FROM productos WHERE id_producto = v_id_producto;

        INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
        VALUES (v_id_venta, v_id_producto, v_cantidad, v_precio);
        -- Los triggers de detalle_ventas ya validan stock, lo descuentan
        -- y recalculan el total de la venta automáticamente.

        SET v_i = v_i + 1;
    END WHILE;

    COMMIT;

    SELECT v_id_venta AS id_venta_creada;
END$$

-- ---------------------------------------------------------
-- 2. sp_AgregarNuevoProducto
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto$$
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(150),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(10,2),
    IN p_costo DECIMAL(10,2),
    IN p_stock INT,
    IN p_sku VARCHAR(50),
    IN p_id_categoria INT,
    IN p_id_proveedor INT
)
BEGIN
    INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor)
    VALUES (p_nombre, p_descripcion, p_precio, p_costo, p_stock, p_sku, p_id_categoria, p_id_proveedor);

    SELECT LAST_INSERT_ID() AS id_producto_creado;
END$$

-- ---------------------------------------------------------
-- 3. sp_ActualizarDireccionCliente
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente$$
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_direccion_nueva VARCHAR(255)
)
BEGIN
    UPDATE clientes
    SET direccion_envio = p_direccion_nueva
    WHERE id_cliente = p_id_cliente;
END$$

-- ---------------------------------------------------------
-- 4. sp_ProcesarDevolucion
--    Reduce (o elimina) la cantidad de una línea de detalle,
--    repone el stock y genera un crédito a favor del cliente.
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion$$
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_detalle INT,
    IN p_cantidad_devuelta INT
)
BEGIN
    DECLARE v_id_venta INT;
    DECLARE v_id_producto INT;
    DECLARE v_id_cliente INT;
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_cantidad_actual INT;
    DECLARE v_monto_credito DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT id_venta, id_producto, precio_unitario_congelado, cantidad
    INTO v_id_venta, v_id_producto, v_precio, v_cantidad_actual
    FROM detalle_ventas WHERE id_detalle = p_id_detalle;

    SELECT id_cliente INTO v_id_cliente FROM ventas WHERE id_venta = v_id_venta;

    SET v_monto_credito = v_precio * p_cantidad_devuelta;

    IF p_cantidad_devuelta >= v_cantidad_actual THEN
        DELETE FROM detalle_ventas WHERE id_detalle = p_id_detalle;
    ELSE
        UPDATE detalle_ventas
        SET cantidad = cantidad - p_cantidad_devuelta
        WHERE id_detalle = p_id_detalle;
    END IF;
    -- Los triggers ya recalculan el total de la venta al modificar detalle_ventas.

    UPDATE productos SET stock = stock + p_cantidad_devuelta WHERE id_producto = v_id_producto;

    INSERT INTO creditos_devolucion (id_cliente, monto, motivo)
    VALUES (v_id_cliente, v_monto_credito, CONCAT('Devolución parcial/total del detalle #', p_id_detalle));

    COMMIT;
END$$

-- ---------------------------------------------------------
-- 5. sp_ObtenerHistorialComprasCliente
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente$$
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT v.id_venta, v.fecha_venta, v.estado, v.total,
           p.nombre AS producto, d.cantidad, d.precio_unitario_congelado
    FROM ventas v
    JOIN detalle_ventas d ON v.id_venta = d.id_venta
    JOIN productos p ON d.id_producto = p.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END$$

-- ---------------------------------------------------------
-- 6. sp_AjustarNivelStock
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock$$
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_cantidad_ajuste INT,   -- positivo = entrada, negativo = salida
    IN p_motivo VARCHAR(255)
)
BEGIN
    UPDATE productos SET stock = stock + p_cantidad_ajuste WHERE id_producto = p_id_producto;

    INSERT INTO ajustes_stock (id_producto, cantidad, motivo)
    VALUES (p_id_producto, p_cantidad_ajuste, p_motivo);
END$$

-- ---------------------------------------------------------
-- 7. sp_EliminarClienteDeFormaSegura
--    Anonimiza en vez de borrar, para conservar integridad referencial
--    con las ventas históricas.
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura$$
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
    SET nombre = 'Cliente',
        apellido = 'Eliminado',
        email = CONCAT('eliminado_', p_id_cliente, '@anonimo.com'),
        contrasena = 'ANONIMIZADO',
        direccion_envio = NULL
    WHERE id_cliente = p_id_cliente;
END$$

-- ---------------------------------------------------------
-- 8. sp_AplicarDescuentoPorCategoria
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria$$
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje DECIMAL(5,2)
)
BEGIN
    UPDATE productos
    SET precio = fn_AplicarDescuento(precio, p_porcentaje)
    WHERE id_categoria = p_id_categoria;
END$$

-- ---------------------------------------------------------
-- 9. sp_GenerarReporteMensualVentas
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas$$
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_anio INT,
    IN p_mes INT
)
BEGIN
    SELECT
        COUNT(*)               AS numero_ventas,
        COALESCE(SUM(total),0) AS total_vendido,
        COALESCE(AVG(total),0) AS ticket_promedio
    FROM ventas
    WHERE YEAR(fecha_venta) = p_anio AND MONTH(fecha_venta) = p_mes;
END$$

-- ---------------------------------------------------------
-- 10. sp_CambiarEstadoPedido
--     (el trigger trg_log_order_status_change ya audita el cambio)
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido$$
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(30)
)
BEGIN
    UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;
END$$

-- ---------------------------------------------------------
-- 11. sp_RegistrarNuevoCliente
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente$$
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(100),
    IN p_apellido VARCHAR(100),
    IN p_email VARCHAR(150),
    IN p_contrasena VARCHAR(255),
    IN p_direccion VARCHAR(255)
)
BEGIN
    IF EXISTS (SELECT 1 FROM clientes WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ya existe un cliente registrado con ese correo electrónico.';
    ELSE
        INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
        VALUES (p_nombre, p_apellido, p_email, p_contrasena, p_direccion);
        SELECT LAST_INSERT_ID() AS id_cliente_creado;
    END IF;
END$$

-- ---------------------------------------------------------
-- 12. sp_ObtenerDetallesProductoCompleto
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto$$
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT p.*, c.nombre AS nombre_categoria,
           pr.nombre AS nombre_proveedor, pr.email_contacto, pr.telefono_contacto
    FROM productos p
    LEFT JOIN categorias c ON p.id_categoria = c.id_categoria
    LEFT JOIN proveedores pr ON p.id_proveedor = pr.id_proveedor
    WHERE p.id_producto = p_id_producto;
END$$

-- ---------------------------------------------------------
-- 13. sp_FusionarCuentasCliente
--     Mueve todas las ventas de la cuenta duplicada a la principal
--     y anonimiza la duplicada (reutiliza el procedimiento 7).
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente$$
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_principal INT,
    IN p_id_cliente_duplicado INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE ventas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;

    UPDATE clientes
    SET total_gastado = (SELECT COALESCE(SUM(total),0) FROM ventas WHERE id_cliente = p_id_cliente_principal)
    WHERE id_cliente = p_id_cliente_principal;

    CALL sp_EliminarClienteDeFormaSegura(p_id_cliente_duplicado);

    COMMIT;
END$$

-- ---------------------------------------------------------
-- 14. sp_AsignarProductoAProveedor
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor$$
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_proveedor INT
)
BEGIN
    UPDATE productos SET id_proveedor = p_id_proveedor WHERE id_producto = p_id_producto;
END$$

-- ---------------------------------------------------------
-- 15. sp_BuscarProductos
--     Todos los filtros son opcionales: pasar NULL para ignorarlos.
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_BuscarProductos$$
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre VARCHAR(150),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(10,2),
    IN p_precio_max DECIMAL(10,2)
)
BEGIN
    SELECT p.*, c.nombre AS categoria
    FROM productos p
    LEFT JOIN categorias c ON p.id_categoria = c.id_categoria
    WHERE (p_nombre IS NULL OR p.nombre LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR p.precio >= p_precio_min)
      AND (p_precio_max IS NULL OR p.precio <= p_precio_max)
      AND p.activo = TRUE;
END$$

-- ---------------------------------------------------------
-- 16. sp_ObtenerDashboardAdmin
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin$$
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM ventas WHERE DATE(fecha_venta) = CURDATE())        AS ventas_hoy,
        (SELECT COALESCE(SUM(total),0) FROM ventas WHERE DATE(fecha_venta) = CURDATE()) AS ingresos_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE())   AS nuevos_clientes_hoy,
        (SELECT COUNT(*) FROM productos WHERE stock < 20 AND activo = TRUE)     AS productos_bajo_stock;
END$$

-- ---------------------------------------------------------
-- 17. sp_ProcesarPago
--     Nota: el ENUM de 'estado' en ventas (definido en 01_Esquema_y_Datos.sql)
--     no incluye un valor "Pagado" explícito; se usa 'Procesando' como el
--     estado más cercano una vez el pago se confirma. Si se requiere un
--     estado de pago independiente del estado de envío, se recomienda
--     separar esa lógica en una columna nueva (estado_pago) en un futuro
--     ajuste de esquema.
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarPago$$
CREATE PROCEDURE sp_ProcesarPago(IN p_id_venta INT)
BEGIN
    UPDATE ventas SET estado = 'Procesando' WHERE id_venta = p_id_venta AND estado = 'Pendiente de Pago';
END$$

-- ---------------------------------------------------------
-- 18. sp_AñadirReseñaProducto
--     Solo permite reseñar productos que el cliente realmente compró.
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AnadirResenaProducto$$
CREATE PROCEDURE sp_AnadirResenaProducto(
    IN p_id_producto INT,
    IN p_id_cliente INT,
    IN p_calificacion TINYINT,
    IN p_comentario TEXT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM detalle_ventas d
        JOIN ventas v ON d.id_venta = v.id_venta
        WHERE v.id_cliente = p_id_cliente AND d.id_producto = p_id_producto
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El cliente no puede reseñar un producto que no ha comprado.';
    ELSE
        INSERT INTO resenas_producto (id_producto, id_cliente, calificacion, comentario)
        VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);
    END IF;
END$$

-- ---------------------------------------------------------
-- 19. sp_ObtenerProductosRelacionados
--     Productos comprados junto al producto dado, en otras ventas.
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados$$
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT p.id_producto, p.nombre, COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas d1
    JOIN detalle_ventas d2 ON d1.id_venta = d2.id_venta AND d1.id_producto <> d2.id_producto
    JOIN productos p ON d2.id_producto = p.id_producto
    WHERE d1.id_producto = p_id_producto
    GROUP BY p.id_producto, p.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 5;
END$$

-- ---------------------------------------------------------
-- 20. sp_MoverProductosEntreCategorias
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias$$
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_id_categoria_origen INT,
    IN p_id_categoria_destino INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM categorias WHERE id_categoria = p_id_categoria_destino) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La categoría destino no existe.';
    ELSE
        UPDATE productos
        SET id_categoria = p_id_categoria_destino
        WHERE id_categoria = p_id_categoria_origen;
    END IF;
END$$

DELIMITER ;