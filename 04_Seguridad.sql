-- =========================================================
-- 04_Seguridad.sql
-- Proyecto: Base de Datos de un E-commerce
-- Descripción: Roles, usuarios y permisos (GRANT/REVOKE).
-- =========================================================

USE ecommerce_db;

-- ---------------------------------------------------------
-- 1. Rol Administrador_Sistema: todos los privilegios
-- ---------------------------------------------------------
DROP ROLE IF EXISTS Administrador_Sistema;
CREATE ROLE Administrador_Sistema;
GRANT ALL PRIVILEGES ON ecommerce_db.* TO Administrador_Sistema;

-- ---------------------------------------------------------
-- 2. Rol Gerente_Marketing: solo lectura a ventas y clientes
-- ---------------------------------------------------------
DROP ROLE IF EXISTS Gerente_Marketing;
CREATE ROLE Gerente_Marketing;
GRANT SELECT ON ecommerce_db.ventas TO Gerente_Marketing;
GRANT SELECT ON ecommerce_db.clientes TO Gerente_Marketing;

-- ---------------------------------------------------------
-- 3. Rol Analista_Datos: solo lectura a todo excepto tablas de auditoría
-- ---------------------------------------------------------
DROP ROLE IF EXISTS Analista_Datos;
CREATE ROLE Analista_Datos;
GRANT SELECT ON ecommerce_db.productos TO Analista_Datos;
GRANT SELECT ON ecommerce_db.categorias TO Analista_Datos;
GRANT SELECT ON ecommerce_db.proveedores TO Analista_Datos;
GRANT SELECT ON ecommerce_db.clientes TO Analista_Datos;
GRANT SELECT ON ecommerce_db.ventas TO Analista_Datos;
GRANT SELECT ON ecommerce_db.detalle_ventas TO Analista_Datos;
-- (Las tablas de auditoría, creadas en 05_Triggers.sql, quedan
--  intencionalmente fuera de este rol)

-- ---------------------------------------------------------
-- 4. Rol Empleado_Inventario: solo modifica productos (stock)
-- ---------------------------------------------------------
DROP ROLE IF EXISTS Empleado_Inventario;
CREATE ROLE Empleado_Inventario;
GRANT SELECT, UPDATE ON ecommerce_db.productos TO Empleado_Inventario;

-- ---------------------------------------------------------
-- 5. Rol Atencion_Cliente: ve clientes y ventas, no modifica precios
-- ---------------------------------------------------------
DROP ROLE IF EXISTS Atencion_Cliente;
CREATE ROLE Atencion_Cliente;
GRANT SELECT ON ecommerce_db.clientes TO Atencion_Cliente;
GRANT SELECT, UPDATE ON ecommerce_db.ventas TO Atencion_Cliente;
-- No se otorga ningún privilegio sobre productos.precio

-- ---------------------------------------------------------
-- 6. Rol Auditor_Financiero: solo lectura a ventas, productos y logs de precios
-- ---------------------------------------------------------
DROP ROLE IF EXISTS Auditor_Financiero;
CREATE ROLE Auditor_Financiero;
GRANT SELECT ON ecommerce_db.ventas TO Auditor_Financiero;
GRANT SELECT ON ecommerce_db.productos TO Auditor_Financiero;
-- GRANT SELECT ON ecommerce_db.log_cambios_precio TO Auditor_Financiero;
-- (se activa en 05_Triggers.sql, una vez existe esa tabla)

-- ---------------------------------------------------------
-- 7-10. Creación de usuarios y asignación de roles
-- ---------------------------------------------------------
DROP USER IF EXISTS 'admin_user'@'localhost';
CREATE USER 'admin_user'@'localhost' IDENTIFIED BY 'CambiarEsta123!';
GRANT Administrador_Sistema TO 'admin_user'@'localhost';
SET DEFAULT ROLE Administrador_Sistema TO 'admin_user'@'localhost';

DROP USER IF EXISTS 'marketing_user'@'localhost';
CREATE USER 'marketing_user'@'localhost' IDENTIFIED BY 'CambiarEsta123!';
GRANT Gerente_Marketing TO 'marketing_user'@'localhost';
SET DEFAULT ROLE Gerente_Marketing TO 'marketing_user'@'localhost';

DROP USER IF EXISTS 'inventory_user'@'localhost';
CREATE USER 'inventory_user'@'localhost' IDENTIFIED BY 'CambiarEsta123!';
GRANT Empleado_Inventario TO 'inventory_user'@'localhost';
SET DEFAULT ROLE Empleado_Inventario TO 'inventory_user'@'localhost';

DROP USER IF EXISTS 'support_user'@'localhost';
CREATE USER 'support_user'@'localhost' IDENTIFIED BY 'CambiarEsta123!';
GRANT Atencion_Cliente TO 'support_user'@'localhost';
SET DEFAULT ROLE Atencion_Cliente TO 'support_user'@'localhost';

-- ---------------------------------------------------------
-- 11. Impedir que Analista_Datos ejecute DELETE o TRUNCATE
--     (no se le otorgan esos privilegios; se deja explícito con REVOKE
--     por si en el futuro se le llegara a asignar por error)
-- ---------------------------------------------------------
-- (Sin acción adicional: el rol Analista_Datos solo tiene SELECT,
--  ver sección 3 más arriba.)

-- ---------------------------------------------------------
-- 12. Permiso a Gerente_Marketing para ejecutar procedimientos
--     almacenados de reportes de marketing
--     (el procedimiento se crea en 07_Procedimientos_Almacenados.sql;
--      aquí se deja preparado el GRANT sobre el procedimiento específico)
-- ---------------------------------------------------------
-- GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_GenerarReporteMensualVentas TO Gerente_Marketing;
-- (Se activa después de crear el procedimiento en el archivo 07)

-- ---------------------------------------------------------
-- 13. Vista v_info_clientes_basica (oculta info sensible) + acceso
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT id_cliente, nombre, apellido, direccion_envio
FROM clientes;
-- (se excluyen email y contrasena de esta vista)

GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO Atencion_Cliente;

-- ---------------------------------------------------------
-- 14. Revocar UPDATE sobre productos.precio al rol Empleado_Inventario
--     MySQL no permite REVOKE a nivel de columna directamente sobre un
--     GRANT de tabla completa, así que se ajusta el privilegio de tabla
--     y se otorga UPDATE columna por columna (excluyendo precio).
-- ---------------------------------------------------------
REVOKE UPDATE ON ecommerce_db.productos FROM Empleado_Inventario;
GRANT UPDATE (stock, activo, descripcion) ON ecommerce_db.productos TO Empleado_Inventario;

-- ---------------------------------------------------------
-- 15. Política de contraseñas seguras para todos los usuarios
-- ---------------------------------------------------------
ALTER USER 'admin_user'@'localhost'      PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'marketing_user'@'localhost'  PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'inventory_user'@'localhost'  PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'support_user'@'localhost'    PASSWORD EXPIRE INTERVAL 90 DAY;
-- Adicionalmente se recomienda activar el plugin validate_password
-- a nivel de servidor: INSTALL COMPONENT 'file://component_validate_password';

-- ---------------------------------------------------------
-- 16. Asegurar que root no pueda conectarse remotamente
-- ---------------------------------------------------------
DROP USER IF EXISTS 'root'@'%';
-- Con esto solo queda 'root'@'localhost', bloqueando el acceso remoto.

-- ---------------------------------------------------------
-- 17. Rol Visitante: solo puede ver la tabla productos
-- ---------------------------------------------------------
DROP ROLE IF EXISTS Visitante;
CREATE ROLE Visitante;
GRANT SELECT ON ecommerce_db.productos TO Visitante;

-- ---------------------------------------------------------
-- 18. Limitar consultas por hora para Analista_Datos
--     (MAX_QUERIES_PER_HOUR se define a nivel de usuario, no de rol,
--      por lo que se aplicará sobre cualquier usuario que use este rol)
-- ---------------------------------------------------------
DROP USER IF EXISTS 'analista_user'@'localhost';
CREATE USER 'analista_user'@'localhost'
    IDENTIFIED BY 'CambiarEsta123!'
    WITH MAX_QUERIES_PER_HOUR 500;
GRANT Analista_Datos TO 'analista_user'@'localhost';
SET DEFAULT ROLE Analista_Datos TO 'analista_user'@'localhost';

-- ---------------------------------------------------------
-- 19. Ventas visibles solo por sucursal (requiere id_sucursal)
--     Nota: el esquema base del proyecto no incluye sucursales.
--     Se deja preparado el cambio estructural necesario, comentado,
--     para no romper el esquema entregado en 01_Esquema_y_Datos.sql.
-- ---------------------------------------------------------
-- ALTER TABLE ventas ADD COLUMN id_sucursal INT NULL;
-- CREATE VIEW v_ventas_por_sucursal AS
--     SELECT * FROM ventas WHERE id_sucursal = @sucursal_usuario_actual;
-- (En un escenario real esto se resolvería con Row-Level Security
--  vía vistas parametrizadas o lógica en la capa de aplicación,
--  ya que MySQL no tiene RLS nativo como Postgres.)

-- ---------------------------------------------------------
-- 20. Auditar intentos de inicio de sesión fallidos
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_intentos_login (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    usuario_intento VARCHAR(100),
    host_origen     VARCHAR(100),
    fecha_intento   DATETIME DEFAULT CURRENT_TIMESTAMP,
    exitoso         BOOLEAN
);
-- Nota: MySQL no dispara un evento nativo capturable por trigger para
-- login fallido; en producción esto se audita activando el plugin
-- 'audit_log' del servidor, o registrando desde la capa de aplicación
-- cada intento contra esta tabla.

FLUSH PRIVILEGES;