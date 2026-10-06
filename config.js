// Conexión con Supabase (registro con correo y datos en la nube).
// Estos dos valores son públicos por diseño: la seguridad la dan las reglas
// de schema.sql. Se copian de Supabase > Project Settings > API.
// Mientras estén vacíos, la app funciona en modo de prueba y guarda los datos
// solo en el dispositivo.
window.PLATICA_CONFIG = {
  supabaseUrl: "",
  supabaseKey: ""
};
