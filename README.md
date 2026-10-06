# Pa que rinda la platica

App web para llevar las finanzas por quincena, por cuenta propia o en pareja:
obligaciones fijas, gastos extra, ingresos, meta de ahorro y cuentas a mitades.

- Se entra con **correo y contraseña**, desde cualquier celular o computador.
- Los datos se guardan en la nube y se ven igual en todos los dispositivos.
- En pareja, cada uno entra con su correo y comparten los mismos datos con un código.
- Se puede agregar a la pantalla de inicio del celular y queda como una app.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La app completa (diseño y funcionamiento). |
| `config.js` | Los dos datos de conexión con Supabase. |
| `schema.sql` | Crea las tablas y las reglas de seguridad. Se ejecuta una vez. |
| `manifest.webmanifest` y los 4 archivos `.png` | Nombre e ícono para instalarla en el celular. |

## Puesta en marcha

### 1. Base de datos y registro con correo (Supabase)

1. Crea una cuenta gratis en https://supabase.com y un proyecto nuevo.
2. Abre **SQL Editor**, crea una consulta nueva, pega todo el contenido de
   `schema.sql` y ejecútalo.
3. En la configuración del proyecto, sección de **API**, copia dos datos:
   la **URL del proyecto** y la **clave pública** (aparece como `anon` o `publishable`).
   Nunca uses la clave `service_role` ni la `secret`.
4. Pega los dos datos en `config.js`:

   ```js
   window.PLATICA_CONFIG = {
     supabaseUrl: "https://xxxxxxxx.supabase.co",
     supabaseKey: "la-clave-publica"
   };
   ```

Mientras `config.js` esté vacío, la app abre en modo de prueba y guarda los
datos solo en ese dispositivo.

### 2. Código en GitHub

Sube esta carpeta completa a un repositorio de GitHub (puede ser privado).

### 3. Publicación en Vercel

1. Entra a https://vercel.com con tu cuenta de GitHub.
2. Crea un proyecto nuevo e importa el repositorio.
3. No hay que configurar nada: es un sitio estático. Publica.
4. Vercel te da una dirección, por ejemplo `https://pa-que-rinda-la-platica.vercel.app`.

Cada vez que se cambie algo en GitHub, Vercel vuelve a publicar solo.

### 4. Decirle a Supabase cuál es la dirección de la app

En Supabase, en **Authentication**, configuración de URL, pon la dirección de
Vercel como **Site URL**. Así los correos de confirmación y de cambio de
contraseña llevan de vuelta a la app.

## Uso en pareja

1. La primera persona crea su cuenta y elige "Empezar mi propio espacio".
2. En **Ajustes** aparece un **código de 6 caracteres**.
3. La pareja crea su cuenta con su propio correo, elige "Unirme" y escribe el código.

Desde ahí los dos ven y anotan sobre los mismos datos. Un espacio admite dos personas.

## Notas

- Al crear una cuenta, Supabase envía un correo de confirmación. El servicio de
  correo incluido en el plan gratuito permite pocos envíos por hora; para uso
  personal alcanza.
- La seguridad está en las reglas de `schema.sql`: cada cuenta solo
  puede leer y escribir los datos de su propio espacio.
