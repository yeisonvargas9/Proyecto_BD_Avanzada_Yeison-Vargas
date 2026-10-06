/* =====================================================================
   SEGMENTACIÓN DE CLIENTES RFM (Recencia, Frecuencia, Monetario)
   Motor: MySQL 8.0+ (usa CTEs y funciones de ventana como NTILE)
   Tablas: clientes, ventas

   Supuestos:
   - Solo cuentan las ventas realmente concretadas: se excluyen
     'Cancelado' y 'Pendiente de Pago'.
   - El valor monetario es la suma de ventas.total.
   - Los clientes sin compras válidas no aparecen (no tienen RFM).
   ===================================================================== */

-- PASO 1: métricas crudas por cliente
WITH metricas AS (
    SELECT
        c.id_cliente,
        CONCAT(c.nombre, ' ', c.apellido)       AS cliente,
        DATEDIFF(CURDATE(), MAX(v.fecha_venta)) AS recencia,   -- días desde la última compra
        COUNT(v.id_venta)                       AS frecuencia, -- número de compras
        SUM(v.total)                            AS monetario   -- gasto total histórico
    FROM clientes c
    INNER JOIN ventas v ON v.id_cliente = c.id_cliente
    WHERE v.estado IN ('Procesando', 'Enviado', 'Entregado')
    GROUP BY c.id_cliente, c.nombre, c.apellido
),

-- PASO 2: puntuación de 1 a 4 con NTILE(4) (reparte en 4 grupos iguales)
puntuaciones AS (
    SELECT
        id_cliente,
        cliente,
        recencia,
        frecuencia,
        monetario,
        -- Recencia: MENOS días es mejor, por eso el orden es DESCENDENTE
        -- (los más antiguos reciben 1, los más recientes reciben 4)
        NTILE(4) OVER (ORDER BY recencia   DESC) AS r_score,
        -- Frecuencia y monetario: MÁS es mejor, orden ASCENDENTE
        NTILE(4) OVER (ORDER BY frecuencia ASC)  AS f_score,
        NTILE(4) OVER (ORDER BY monetario  ASC)  AS m_score
    FROM metricas
)

-- PASO 3: segmento final con CASE (el orden de los WHEN importa:
-- se evalúa de arriba hacia abajo y gana la primera condición verdadera)
SELECT
    id_cliente,
    cliente,
    recencia,
    frecuencia,
    monetario,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, f_score, m_score) AS codigo_rfm,
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Campeones'          -- compran seguido, reciente y gastan mucho
        WHEN r_score >= 3 AND f_score >= 2                  THEN 'Leales'             -- compran reciente y con regularidad
        WHEN r_score = 4  AND f_score = 1                   THEN 'Nuevos'             -- primera compra muy reciente
        WHEN r_score <= 2 AND f_score >= 3                  THEN 'En Riesgo'          -- eran buenos clientes, pero llevan tiempo sin comprar
        WHEN r_score = 1  AND f_score <= 2                  THEN 'Perdidos'           -- poco frecuentes y sin comprar hace mucho
        ELSE 'Necesitan Atención'                                                     -- el resto
    END AS segmento
FROM puntuaciones
ORDER BY r_score DESC, f_score DESC, m_score DESC;
