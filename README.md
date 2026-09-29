# Proyecto de Base de Datos para un E-commerce

## Descripción

Este proyecto implementa el núcleo de una base de datos relacional en MySQL para una tienda en línea. El sistema gestiona productos, categorías, proveedores, clientes y el ciclo completo de ventas, e incorpora lógica avanzada de negocio mediante funciones, triggers, eventos programados, procedimientos almacenados y un esquema de seguridad basado en roles.

## Integrantes

- Yeison Alberto Vargas Serrano

## Instrucciones de Ejecución

Los scripts deben ejecutarse **en orden estricto**, ya que cada uno depende de que el anterior haya finalizado correctamente. Se recomienda usar MySQL 8.0 o superior.

1. **`01_Esquema_y_Datos.sql`** — Crea la base de datos, las 6 tablas principales con sus restricciones, y carga los datos de ejemplo.
2. **`02_Consultas_Avanzadas.sql`** — Ejecuta las 20 consultas de análisis y reporteo (solo lectura).
3. **`03_Funciones.sql`** — Crea las 20 funciones definidas por el usuario (UDFs).
4. **`04_Seguridad.sql`** — Crea los roles, usuarios, una vista de datos básicos de clientes, y asigna los permisos correspondientes.
5. **`05_Triggers.sql`** — Agrega columnas y tablas de apoyo necesarias, y crea los 20 triggers de integridad y automatización. **Ejecutar una sola vez** (contiene sentencias `ALTER TABLE ADD COLUMN` que fallarán si se corre dos veces sobre la misma base).
6. **`06_Eventos.sql`** — Activa el `event_scheduler` de MySQL y crea los 20 eventos programados de mantenimiento y negocio.
7. **`07_Procedimientos_Almacenados.sql`** — Crea los 20 procedimientos almacenados para operaciones transaccionales complejas.

### Ejemplo de ejecución desde línea de comandos

```bash
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p < 02_Consultas_Avanzadas.sql
mysql -u root -p < 03_Funciones.sql
mysql -u root -p < 04_Seguridad.sql
mysql -u root -p < 05_Triggers.sql
mysql -u root -p < 06_Eventos.sql
mysql -u root -p < 07_Procedimientos_Almacenados.sql
```

En DBeaver: abrir cada archivo y ejecutar con **Alt+X** (Execute SQL Script), en el orden indicado.

### Reiniciar la base desde cero

Si necesitas volver a ejecutar todo el flujo (por ejemplo, para pruebas), primero elimina la base existente:

```sql
DROP DATABASE IF EXISTS ecommerce_db;
```

y luego vuelve a correr los 7 archivos en orden, del 1 al 7.

## Notas y Supuestos del Proyecto

El esquema de entidades definido en los requisitos originales no incluye ciertos datos que algunas consultas, funciones o eventos de negocio requerirían en un sistema real (por ejemplo: fecha de nacimiento del cliente, tabla de carritos de compra, tabla de promociones, o un campo de sucursal). En esos casos puntuales, la lógica se implementó de la forma más fiel posible al requerimiento y se documentó la limitación directamente como comentario en el archivo `.sql` correspondiente, en lugar de alterar el esquema base sin explicación.

## Estructura del Repositorio

```sql
├── 01_Esquema_y_Datos.sql
├── 02_Consultas_Avanzadas.sql
├── 03_Funciones.sql
├── 04_Seguridad.sql
├── 05_Triggers.sql
├── 06_Eventos.sql
├── 07_Procedimientos_Almacenados.sql
└── README.md
```
