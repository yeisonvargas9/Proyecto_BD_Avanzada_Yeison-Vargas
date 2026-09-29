-- =========================================================
-- 01_Esquema_y_Datos.sql
-- Proyecto: Base de Datos de un E-commerce
-- Descripción: Creación del esquema completo (6 tablas) y
--              carga de datos de ejemplo.
-- =========================================================

CREATE DATABASE IF NOT EXISTS ecommerce_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE ecommerce_db;

-- ---------------------------------------------------------
-- Desactivamos temporalmente checks de FK para poder recrear
-- el esquema limpio si el script se ejecuta varias veces.
-- ---------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS detalle_ventas;
DROP TABLE IF EXISTS ventas;
DROP TABLE IF EXISTS productos;
DROP TABLE IF EXISTS categorias;
DROP TABLE IF EXISTS proveedores;
DROP TABLE IF EXISTS clientes;

SET FOREIGN_KEY_CHECKS = 1;

-- =========================================================
-- TABLA: categorias
-- =========================================================
CREATE TABLE categorias (
    id_categoria    INT AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL UNIQUE,
    descripcion     TEXT NULL
) ENGINE=InnoDB;

-- =========================================================
-- TABLA: proveedores
-- =========================================================
CREATE TABLE proveedores (
    id_proveedor        INT AUTO_INCREMENT PRIMARY KEY,
    nombre              VARCHAR(150) NOT NULL,
    email_contacto      VARCHAR(150) NULL UNIQUE,
    telefono_contacto   VARCHAR(30) NULL
) ENGINE=InnoDB;

-- =========================================================
-- TABLA: productos
-- =========================================================
CREATE TABLE productos (
    id_producto     INT AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(150) NOT NULL UNIQUE,
    descripcion     TEXT NULL,
    precio          DECIMAL(10,2) NOT NULL,
    costo           DECIMAL(10,2) NOT NULL,
    stock           INT NOT NULL DEFAULT 0,
    sku             VARCHAR(50) NOT NULL UNIQUE,
    fecha_creacion  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    id_categoria    INT NULL,
    id_proveedor    INT NULL,

    CONSTRAINT chk_precio_positivo CHECK (precio > 0),
    CONSTRAINT chk_costo_no_negativo CHECK (costo >= 0),
    CONSTRAINT chk_stock_no_negativo CHECK (stock >= 0),

    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT fk_producto_proveedor
        FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_productos_categoria ON productos(id_categoria);
CREATE INDEX idx_productos_proveedor ON productos(id_proveedor);

-- =========================================================
-- TABLA: clientes
-- =========================================================
CREATE TABLE clientes (
    id_cliente      INT AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    apellido        VARCHAR(100) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    contrasena      VARCHAR(255) NOT NULL,
    direccion_envio VARCHAR(255) NULL,
    fecha_registro  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- =========================================================
-- TABLA: ventas
-- =========================================================
CREATE TABLE ventas (
    id_venta        INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente      INT NOT NULL,
    fecha_venta     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado          ENUM('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado')
                    NOT NULL DEFAULT 'Pendiente de Pago',
    total           DECIMAL(12,2) NOT NULL DEFAULT 0.00,

    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_ventas_cliente ON ventas(id_cliente);
CREATE INDEX idx_ventas_fecha ON ventas(fecha_venta);

-- =========================================================
-- TABLA: detalle_ventas
-- =========================================================
CREATE TABLE detalle_ventas (
    id_detalle                  INT AUTO_INCREMENT PRIMARY KEY,
    id_venta                    INT NOT NULL,
    id_producto                 INT NOT NULL,
    cantidad                    INT NOT NULL,
    precio_unitario_congelado   DECIMAL(10,2) NOT NULL,

    CONSTRAINT chk_cantidad_positiva CHECK (cantidad > 0),

    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
        ON DELETE CASCADE ON UPDATE CASCADE,

    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_detalle_venta ON detalle_ventas(id_venta);
CREATE INDEX idx_detalle_producto ON detalle_ventas(id_producto);

-- =========================================================
-- DATOS DE EJEMPLO
-- =========================================================

-- Categorías
INSERT INTO categorias (nombre, descripcion) VALUES
('Electrónica', 'Dispositivos electrónicos y accesorios'),
('Ropa', 'Prendas de vestir para todas las edades'),
('Hogar', 'Artículos para el hogar y decoración'),
('Deportes', 'Equipamiento y ropa deportiva'),
('Libros', 'Libros físicos y material de lectura');

-- Proveedores
INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TechSupply S.A.', 'contacto@techsupply.com', '3001234567'),
('Moda Global Ltda.', 'ventas@modaglobal.com', '3009876543'),
('HogarMax', 'info@hogarmax.com', '3011122334'),
('DeporteYa', 'contacto@deporteya.com', '3022233445'),
('Editorial Andina', 'pedidos@editorialandina.com', '3033344556');

-- Productos
INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, activo, id_categoria, id_proveedor) VALUES
('Audífonos Bluetooth X100', 'Audífonos inalámbricos con cancelación de ruido', 149900.00, 90000.00, 50, 'SKU-ELEC-001', TRUE, 1, 1),
('Smartwatch Fit 2', 'Reloj inteligente con monitor de ritmo cardíaco', 259900.00, 160000.00, 30, 'SKU-ELEC-002', TRUE, 1, 1),
('Camiseta Casual Hombre', 'Camiseta de algodón 100%', 49900.00, 20000.00, 100, 'SKU-ROPA-001', TRUE, 2, 2),
('Chaqueta Impermeable', 'Chaqueta resistente al agua unisex', 129900.00, 70000.00, 40, 'SKU-ROPA-002', TRUE, 2, 2),
('Juego de Sábanas Queen', 'Juego de sábanas 100% algodón', 89900.00, 45000.00, 25, 'SKU-HOG-001', TRUE, 3, 3),
('Set de Ollas Antiadherentes', 'Juego de 5 ollas antiadherentes', 199900.00, 120000.00, 15, 'SKU-HOG-002', TRUE, 3, 3),
('Balón de Fútbol Pro', 'Balón oficial tamaño 5', 79900.00, 40000.00, 60, 'SKU-DEP-001', TRUE, 4, 4),
('Mancuernas 10kg (par)', 'Par de mancuernas de hierro fundido', 119900.00, 70000.00, 20, 'SKU-DEP-002', TRUE, 4, 4),
('Cien Años de Soledad', 'Edición conmemorativa', 59900.00, 30000.00, 35, 'SKU-LIB-001', TRUE, 5, 5),
('El Principito', 'Edición ilustrada', 39900.00, 18000.00, 45, 'SKU-LIB-002', TRUE, 5, 5);

-- Clientes
INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio) VALUES
('Laura', 'Gómez', 'laura.gomez@email.com', 'hash_pendiente_1', 'Calle 10 #5-20, Bucaramanga'),
('Carlos', 'Ramírez', 'carlos.ramirez@email.com', 'hash_pendiente_2', 'Carrera 15 #45-10, Bogotá'),
('Ana', 'Torres', 'ana.torres@email.com', 'hash_pendiente_3', 'Avenida 3N #20-30, Cali'),
('Jorge', 'Pérez', 'jorge.perez@email.com', 'hash_pendiente_4', 'Calle 50 #12-45, Medellín'),
('María', 'López', 'maria.lopez@email.com', 'hash_pendiente_5', 'Transversal 8 #33-12, Bucaramanga');

-- Ventas
-- (El campo total se calcula a partir de la suma de detalle_ventas;
--  aquí se precarga ya cuadrado con los INSERT de detalle de abajo.
--  Más adelante, el trigger trg_recalculate_total_venta_on_detalle_change
--  se encargará de mantenerlo actualizado automáticamente.)
INSERT INTO ventas (id_cliente, estado, total) VALUES
(1, 'Entregado', 199800.00),   -- venta 1: prod1 + prod3
(2, 'Enviado', 259900.00),     -- venta 2: prod2
(3, 'Procesando', 179800.00),  -- venta 3: prod4 + prod3
(1, 'Pendiente de Pago', 119900.00), -- venta 4: prod8
(4, 'Entregado', 99800.00);    -- venta 5: prod9 + prod10

-- Detalle de ventas
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
(1, 1, 1, 149900.00),
(1, 3, 1, 49900.00),
(2, 2, 1, 259900.00),
(3, 4, 1, 129900.00),
(3, 3, 1, 49900.00),
(4, 8, 1, 119900.00),
(5, 9, 1, 59900.00),
(5, 10, 1, 39900.00);