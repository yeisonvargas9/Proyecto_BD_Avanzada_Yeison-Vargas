-- =========================================================
-- 02_Consultas_Avanzadas.sql
-- Proyecto: Base de Datos de un E-commerce
-- Descripción: 20 consultas SQL de análisis y reporteo.
-- =========================================================

USE ecommerce_db;

-- ---------------------------------------------------------
-- 1. Top 10 Productos Más Vendidos (por ingresos generados)
-- ---------------------------------------------------------
SELECT p.id_producto,
       p.nombre,
       SUM(d.cantidad)                              AS unidades_vendidas,
       SUM(d.cantidad * d.precio_unitario_congelado) AS ingresos_totales
FROM productos p
JOIN detalle_ventas d ON p.id_producto = d.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_totales DESC
LIMIT 10;

-- ---------------------------------------------------------
-- 2. Productos con Bajas Ventas (10% inferior por unidades vendidas)
-- ---------------------------------------------------------
WITH ventas_por_producto AS (
    SELECT p.id_producto, p.nombre,
           COALESCE(SUM(d.cantidad), 0) AS unidades_vendidas,
           NTILE(10) OVER (ORDER BY COALESCE(SUM(d.cantidad), 0)) AS decil
    FROM productos p
    LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
    GROUP BY p.id_producto, p.nombre
)
SELECT id_producto, nombre, unidades_vendidas
FROM ventas_por_producto
WHERE decil = 1
ORDER BY unidades_vendidas ASC;

-- ---------------------------------------------------------
-- 3. Clientes VIP: Top 5 por valor de vida (LTV = gasto histórico total)
-- ---------------------------------------------------------
SELECT c.id_cliente, c.nombre, c.apellido,
       SUM(v.total) AS gasto_total_historico
FROM clientes c
JOIN ventas v ON c.id_cliente = v.id_cliente
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY gasto_total_historico DESC
LIMIT 5;

-- ---------------------------------------------------------
-- 4. Análisis de Ventas Mensuales (total agrupado por año-mes)
-- ---------------------------------------------------------
SELECT DATE_FORMAT(fecha_venta, '%Y-%m') AS anio_mes,
       COUNT(*)     AS numero_ventas,
       SUM(total)   AS total_vendido
FROM ventas
GROUP BY anio_mes
ORDER BY anio_mes;

-- ---------------------------------------------------------
-- 5. Crecimiento de Clientes: nuevos clientes registrados por trimestre
-- ---------------------------------------------------------
SELECT CONCAT(YEAR(fecha_registro), '-Q', QUARTER(fecha_registro)) AS trimestre,
       COUNT(*) AS nuevos_clientes
FROM clientes
GROUP BY trimestre
ORDER BY trimestre;

-- ---------------------------------------------------------
-- 6. Tasa de Compra Repetida (% de clientes con más de una venta)
-- ---------------------------------------------------------
SELECT
    ROUND(
        100.0 * SUM(CASE WHEN num_ventas > 1 THEN 1 ELSE 0 END) / COUNT(*)
    , 2) AS porcentaje_clientes_recurrentes
FROM (
    SELECT id_cliente, COUNT(*) AS num_ventas
    FROM ventas
    GROUP BY id_cliente
) AS resumen;

-- ---------------------------------------------------------
-- 7. Productos Comprados Juntos Frecuentemente (pares en la misma venta)
-- ---------------------------------------------------------
SELECT d1.id_producto AS producto_a,
       d2.id_producto AS producto_b,
       COUNT(*) AS veces_comprados_juntos
FROM detalle_ventas d1
JOIN detalle_ventas d2
    ON d1.id_venta = d2.id_venta
   AND d1.id_producto < d2.id_producto   -- evita duplicados (A,B) y (B,A)
GROUP BY d1.id_producto, d2.id_producto
ORDER BY veces_comprados_juntos DESC
LIMIT 10;

-- ---------------------------------------------------------
-- 8. Rotación de Inventario por Categoría
--    (unidades vendidas / stock actual promedio, como aproximación
--     ya que no se almacena histórico de inventario)
-- ---------------------------------------------------------
SELECT c.nombre AS categoria,
       COALESCE(SUM(d.cantidad), 0)      AS unidades_vendidas,
       AVG(p.stock)                      AS stock_promedio_actual,
       ROUND(COALESCE(SUM(d.cantidad), 0) / NULLIF(AVG(p.stock), 0), 2) AS tasa_rotacion
FROM categorias c
JOIN productos p ON c.id_categoria = p.id_categoria
LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
GROUP BY c.id_categoria, c.nombre;

-- ---------------------------------------------------------
-- 9. Productos que Necesitan Reabastecimiento (stock por debajo del umbral)
--    Umbral definido en 20 unidades.
-- ---------------------------------------------------------
SELECT id_producto, nombre, stock
FROM productos
WHERE stock < 20 AND activo = TRUE
ORDER BY stock ASC;

-- ---------------------------------------------------------
-- 10. Análisis de Carrito Abandonado (SIMULADO)
--     Supuesto: el esquema no incluye tabla de carritos, por lo que se
--     aproxima como "clientes registrados hace más de 7 días que nunca
--     completaron una venta" (posible interés sin conversión).
-- ---------------------------------------------------------
SELECT c.id_cliente, c.nombre, c.apellido, c.fecha_registro
FROM clientes c
LEFT JOIN ventas v ON c.id_cliente = v.id_cliente
WHERE v.id_venta IS NULL
  AND c.fecha_registro < NOW() - INTERVAL 7 DAY;

-- ---------------------------------------------------------
-- 11. Rendimiento de Proveedores (por volumen de ventas de sus productos)
-- ---------------------------------------------------------
SELECT pr.id_proveedor, pr.nombre,
       COALESCE(SUM(d.cantidad), 0)                              AS unidades_vendidas,
       COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0) AS ingresos_generados
FROM proveedores pr
LEFT JOIN productos p ON pr.id_proveedor = p.id_proveedor
LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
GROUP BY pr.id_proveedor, pr.nombre
ORDER BY ingresos_generados DESC;

-- ---------------------------------------------------------
-- 12. Análisis Geográfico de Ventas (agrupado por ciudad)
--     Supuesto: direccion_envio guarda la ciudad como último segmento
--     separado por coma (ej. "Calle 10 #5-20, Bucaramanga").
-- ---------------------------------------------------------
SELECT TRIM(
           SUBSTRING_INDEX(c.direccion_envio, ',', -1)
       ) AS ciudad,
       COUNT(v.id_venta) AS numero_ventas,
       SUM(v.total)      AS total_vendido
FROM clientes c
JOIN ventas v ON c.id_cliente = v.id_cliente
GROUP BY ciudad
ORDER BY total_vendido DESC;

-- ---------------------------------------------------------
-- 13. Ventas por Hora del Día (para identificar horas pico)
-- ---------------------------------------------------------
SELECT HOUR(fecha_venta) AS hora_del_dia,
       COUNT(*)          AS numero_ventas,
       SUM(total)        AS total_vendido
FROM ventas
GROUP BY hora_del_dia
ORDER BY numero_ventas DESC;

-- ---------------------------------------------------------
-- 14. Impacto de Promociones (antes / durante / después de una fecha)
--     Supuesto: no existe tabla de promociones; se compara el
--     comportamiento de ventas de UN producto en 3 ventanas de tiempo
--     definidas manualmente (ejemplo: promo del 2026-06-01 al 2026-06-15).
-- ---------------------------------------------------------
SELECT
    CASE
        WHEN v.fecha_venta < '2026-06-01' THEN 'Antes'
        WHEN v.fecha_venta BETWEEN '2026-06-01' AND '2026-06-15' THEN 'Durante'
        ELSE 'Después'
    END AS periodo,
    SUM(d.cantidad) AS unidades_vendidas
FROM detalle_ventas d
JOIN ventas v ON d.id_venta = v.id_venta
WHERE d.id_producto = 1   -- reemplazar por el producto en promoción
GROUP BY periodo;

-- ---------------------------------------------------------
-- 15. Análisis de Cohort (retención mes a mes desde la primera compra)
-- ---------------------------------------------------------
WITH primera_compra AS (
    SELECT id_cliente, MIN(DATE_FORMAT(fecha_venta, '%Y-%m-01')) AS mes_cohorte
    FROM ventas
    GROUP BY id_cliente
),
actividad AS (
    SELECT v.id_cliente,
           pc.mes_cohorte,
           DATE_FORMAT(v.fecha_venta, '%Y-%m-01') AS mes_actividad,
           PERIOD_DIFF(
               DATE_FORMAT(v.fecha_venta, '%Y%m'),
               DATE_FORMAT(pc.mes_cohorte, '%Y%m')
           ) AS meses_desde_cohorte
    FROM ventas v
    JOIN primera_compra pc ON v.id_cliente = pc.id_cliente
)
SELECT mes_cohorte, meses_desde_cohorte,
       COUNT(DISTINCT id_cliente) AS clientes_activos
FROM actividad
GROUP BY mes_cohorte, meses_desde_cohorte
ORDER BY mes_cohorte, meses_desde_cohorte;

-- ---------------------------------------------------------
-- 16. Margen de Beneficio por Producto
-- ---------------------------------------------------------
SELECT id_producto, nombre, precio, costo,
       (precio - costo)                         AS margen_absoluto,
       ROUND(100 * (precio - costo) / precio, 2) AS margen_porcentual
FROM productos
ORDER BY margen_porcentual DESC;

-- ---------------------------------------------------------
-- 17. Tiempo Promedio Entre Compras (por cliente, y promedio general)
-- ---------------------------------------------------------
WITH compras_ordenadas AS (
    SELECT id_cliente, fecha_venta,
           LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS compra_anterior
    FROM ventas
),
diferencias AS (
    SELECT id_cliente,
           DATEDIFF(fecha_venta, compra_anterior) AS dias_entre_compras
    FROM compras_ordenadas
    WHERE compra_anterior IS NOT NULL
)
SELECT id_cliente, ROUND(AVG(dias_entre_compras), 1) AS promedio_dias_entre_compras
FROM diferencias
GROUP BY id_cliente

UNION ALL

SELECT NULL AS id_cliente, ROUND(AVG(dias_entre_compras), 1) AS promedio_dias_entre_compras
FROM diferencias;

-- ---------------------------------------------------------
-- 18. Productos Más Vistos vs. Comprados
--     Supuesto: el esquema no registra "vistas" de producto (requeriría
--     una tabla adicional, ej. vistas_producto, alimentada desde la app).
--     Esta consulta deja el ranking de comprados listo para compararse
--     contra esa tabla cuando exista.
-- ---------------------------------------------------------
SELECT p.id_producto, p.nombre,
       COALESCE(SUM(d.cantidad), 0) AS unidades_compradas
       -- , vp.total_vistas  -- se uniría aquí si existiera vistas_producto
FROM productos p
LEFT JOIN detalle_ventas d ON p.id_producto = d.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY unidades_compradas DESC;

-- ---------------------------------------------------------
-- 19. Segmentación de Clientes (RFM: Recencia, Frecuencia, Monetario)
-- ---------------------------------------------------------
WITH rfm_base AS (
    SELECT c.id_cliente,
           DATEDIFF(NOW(), MAX(v.fecha_venta)) AS recencia_dias,
           COUNT(v.id_venta)                   AS frecuencia,
           SUM(v.total)                        AS monetario
    FROM clientes c
    JOIN ventas v ON c.id_cliente = v.id_cliente
    GROUP BY c.id_cliente
),
rfm_scores AS (
    SELECT id_cliente, recencia_dias, frecuencia, monetario,
           NTILE(5) OVER (ORDER BY recencia_dias DESC) AS r_score,
           NTILE(5) OVER (ORDER BY frecuencia ASC)     AS f_score,
           NTILE(5) OVER (ORDER BY monetario ASC)      AS m_score
    FROM rfm_base
)
SELECT id_cliente, recencia_dias, frecuencia, monetario,
       r_score, f_score, m_score,
       CASE
           WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champion'
           WHEN r_score >= 3 AND f_score >= 3 THEN 'Cliente Leal'
           WHEN r_score <= 2 AND f_score <= 2 THEN 'En Riesgo'
           ELSE 'Regular'
       END AS segmento
FROM rfm_scores;

-- ---------------------------------------------------------
-- 20. Predicción de Demanda Simple
--     Promedio móvil de los últimos 3 meses de ventas por categoría,
--     usado como proyección simple para el próximo mes.
-- ---------------------------------------------------------
WITH ventas_mensuales_categoria AS (
    SELECT cat.id_categoria, cat.nombre,
           DATE_FORMAT(v.fecha_venta, '%Y-%m') AS anio_mes,
           SUM(d.cantidad) AS unidades_vendidas
    FROM categorias cat
    JOIN productos p ON cat.id_categoria = p.id_categoria
    JOIN detalle_ventas d ON p.id_producto = d.id_producto
    JOIN ventas v ON d.id_venta = v.id_venta
    GROUP BY cat.id_categoria, cat.nombre, anio_mes
)
SELECT id_categoria, nombre,
       ROUND(AVG(unidades_vendidas), 1) AS proyeccion_proximo_mes
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id_categoria ORDER BY anio_mes DESC) AS rn
    FROM ventas_mensuales_categoria
) recientes
WHERE rn <= 3
GROUP BY id_categoria, nombre;