-- =========================================================
-- 03_Funciones.sql
-- Proyecto: Base de Datos de un E-commerce
-- Descripción: 20 funciones definidas por el usuario (UDFs)
--              que encapsulan lógica de negocio reutilizable.
-- =========================================================

USE ecommerce_db;

DELIMITER $$

-- ---------------------------------------------------------
-- 1. fn_CalcularTotalVenta
--    Calcula el monto total de una venta a partir de su detalle.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta$$
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
    INTO v_total
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;
    RETURN v_total;
END$$

-- ---------------------------------------------------------
-- 2. fn_VerificarDisponibilidadStock
--    Valida si hay stock suficiente para vender cierta cantidad.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock$$
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    RETURN v_stock >= p_cantidad;
END$$

-- ---------------------------------------------------------
-- 3. fn_ObtenerPrecioProducto
--    Devuelve el precio actual de un producto.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto$$
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto;
    RETURN v_precio;
END$$

-- ---------------------------------------------------------
-- 4. fn_CalcularEdadCliente
--    Calcula la edad a partir de una fecha de nacimiento.
--    Nota: la tabla clientes no almacena fecha_nacimiento en este
--    esquema, por lo que la función la recibe como parámetro
--    (lista para usarse si se añade esa columna más adelante).
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente$$
CREATE FUNCTION fn_CalcularEdadCliente(p_fecha_nacimiento DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, CURDATE());
END$$

-- ---------------------------------------------------------
-- 5. fn_FormatearNombreCompleto
--    Devuelve nombre y apellido en formato estandarizado.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto$$
CREATE FUNCTION fn_FormatearNombreCompleto(p_nombre VARCHAR(100), p_apellido VARCHAR(100))
RETURNS VARCHAR(200)
DETERMINISTIC
BEGIN
    RETURN CONCAT(
        UPPER(LEFT(p_nombre, 1)), LOWER(SUBSTRING(p_nombre, 2)), ' ',
        UPPER(LEFT(p_apellido, 1)), LOWER(SUBSTRING(p_apellido, 2))
    );
END$$

-- ---------------------------------------------------------
-- 6. fn_EsClienteNuevo
--    TRUE si la primera compra del cliente fue en los últimos 30 días.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_EsClienteNuevo$$
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra
    FROM ventas
    WHERE id_cliente = p_id_cliente;

    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN v_primera_compra >= (NOW() - INTERVAL 30 DAY);
END$$

-- ---------------------------------------------------------
-- 7. fn_CalcularCostoEnvio
--    Calcula el costo de envío según el peso total (en kg).
--    Tarifa base + tarifa por kilo (valores de ejemplo del negocio).
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio$$
CREATE FUNCTION fn_CalcularCostoEnvio(p_peso_total_kg DECIMAL(10,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE v_tarifa_base DECIMAL(10,2) DEFAULT 8000.00;
    DECLARE v_tarifa_por_kg DECIMAL(10,2) DEFAULT 2500.00;
    RETURN v_tarifa_base + (p_peso_total_kg * v_tarifa_por_kg);
END$$

-- ---------------------------------------------------------
-- 8. fn_AplicarDescuento
--    Aplica un porcentaje de descuento a un monto dado.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_AplicarDescuento$$
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(12,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN p_monto - (p_monto * (p_porcentaje / 100));
END$$

-- ---------------------------------------------------------
-- 9. fn_ObtenerUltimaFechaCompra
--    Devuelve la fecha de la última compra de un cliente.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra$$
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha
    FROM ventas
    WHERE id_cliente = p_id_cliente;
    RETURN v_fecha;
END$$

-- ---------------------------------------------------------
-- 10. fn_ValidarFormatoEmail
--     Verifica si una cadena tiene formato de correo válido.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail$$
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    RETURN p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
END$$

-- ---------------------------------------------------------
-- 11. fn_ObtenerNombreCategoria
--     Devuelve el nombre de la categoría de un producto.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria$$
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre_categoria VARCHAR(100);
    SELECT c.nombre INTO v_nombre_categoria
    FROM productos p
    JOIN categorias c ON p.id_categoria = c.id_categoria
    WHERE p.id_producto = p_id_producto;
    RETURN v_nombre_categoria;
END$$

-- ---------------------------------------------------------
-- 12. fn_ContarVentasCliente
--     Cuenta el número total de compras realizadas por un cliente.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ContarVentasCliente$$
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_conteo INT;
    SELECT COUNT(*) INTO v_conteo FROM ventas WHERE id_cliente = p_id_cliente;
    RETURN v_conteo;
END$$

-- ---------------------------------------------------------
-- 13. fn_CalcularDiasDesdeUltimaCompra
--     Días transcurridos desde la última compra de un cliente.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra$$
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ultima_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_ultima_fecha FROM ventas WHERE id_cliente = p_id_cliente;

    IF v_ultima_fecha IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN DATEDIFF(NOW(), v_ultima_fecha);
END$$

-- ---------------------------------------------------------
-- 14. fn_DeterminarEstadoLealtad
--     Asigna Bronce / Plata / Oro según gasto total histórico.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad$$
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_gasto_total DECIMAL(12,2);
    SELECT COALESCE(SUM(total), 0) INTO v_gasto_total
    FROM ventas
    WHERE id_cliente = p_id_cliente;

    IF v_gasto_total >= 1000000 THEN
        RETURN 'Oro';
    ELSEIF v_gasto_total >= 300000 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END$$

-- ---------------------------------------------------------
-- 15. fn_GenerarSKU
--     Genera un SKU único basado en nombre de producto y categoría.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_GenerarSKU$$
CREATE FUNCTION fn_GenerarSKU(p_nombre_producto VARCHAR(150), p_id_categoria INT)
RETURNS VARCHAR(50)
DETERMINISTIC
BEGIN
    RETURN CONCAT(
        'SKU-', p_id_categoria, '-',
        UPPER(LEFT(REPLACE(p_nombre_producto, ' ', ''), 5)), '-',
        FLOOR(RAND() * 9000 + 1000)
    );
END$$

-- ---------------------------------------------------------
-- 16. fn_CalcularIVA
--     Calcula el IVA (19%) sobre un monto.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularIVA$$
CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(12,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN ROUND(p_monto * 0.19, 2);
END$$

-- ---------------------------------------------------------
-- 17. fn_ObtenerStockTotalPorCategoria
--     Suma el stock de todos los productos de una categoría.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria$$
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock_total INT;
    SELECT COALESCE(SUM(stock), 0) INTO v_stock_total
    FROM productos
    WHERE id_categoria = p_id_categoria;
    RETURN v_stock_total;
END$$

-- ---------------------------------------------------------
-- 18. fn_EstimarFechaEntrega
--     Calcula la fecha estimada de entrega de un pedido.
--     Nota: el esquema no guarda ubicación/sucursal del cliente,
--     así que se usa un plazo fijo de 5 días hábiles como estimación
--     general (parámetro fácil de ajustar si se añade esa columna).
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega$$
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_venta INT)
RETURNS DATE
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha_venta DATETIME;
    SELECT fecha_venta INTO v_fecha_venta FROM ventas WHERE id_venta = p_id_venta;
    RETURN DATE_ADD(v_fecha_venta, INTERVAL 5 DAY);
END$$

-- ---------------------------------------------------------
-- 19. fn_ConvertirMoneda
--     Convierte un monto a otra moneda usando una tasa fija.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ConvertirMoneda$$
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(12,2), p_tasa_cambio DECIMAL(12,6))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN ROUND(p_monto * p_tasa_cambio, 2);
END$$

-- ---------------------------------------------------------
-- 20. fn_ValidarComplejidadContrasena
--     Verifica longitud mínima, mayúscula, minúscula, número y
--     carácter especial.
-- ---------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena$$
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF LENGTH(p_contrasena) < 8 THEN RETURN FALSE; END IF;
    IF p_contrasena NOT REGEXP '[A-Z]' THEN RETURN FALSE; END IF;
    IF p_contrasena NOT REGEXP '[a-z]' THEN RETURN FALSE; END IF;
    IF p_contrasena NOT REGEXP '[0-9]' THEN RETURN FALSE; END IF;
    IF p_contrasena NOT REGEXP '[^A-Za-z0-9]' THEN RETURN FALSE; END IF;
    RETURN TRUE;
END$$

DELIMITER ;