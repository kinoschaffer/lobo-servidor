# Servidor de salas · versión 0.4.0
Implementado y probado con clientes locales. Todavía no está desplegado en Internet.

## Arranque local
Con Godot 4.7 instalado, desde la raíz:
godot --headless --path . res://servidor/salas.tscn

Escucha el puerto 9080 (variable PORT opcional). Para pruebas en esta computadora, datos/online.json puede contener {"server_url":"ws://127.0.0.1:9080"}. Ese valor no sirve para conectarse desde otros celulares.

## Despliegue público preparado
Se requiere un servidor Linux x86_64 con Docker Compose, un dominio apuntando a él y puertos 80/443 abiertos.
Desde servidor:
LOBO_DOMAIN=tu-dominio.example docker compose up -d --build

Caddy proporciona HTTPS/WSS y reenvía al servidor interno. No expongas 9080 directamente a Internet. En datos/online.json colocá {"server_url":"wss://tu-dominio.example"} y exportá el cliente.
No se creó ningún recurso pago ni se configuró un dominio. La receta Docker no se ejecutó en esta computadora (no tiene Docker); el mismo servidor GDScript sí pasó la prueba de conexiones real.

## Funciones y límites
- Código de sala de seis caracteres, 2–8 personas y bots hasta completar ocho.
- El servidor valida acciones y produce una vista distinta para cada jugador.
- Reconexión durante la sesión abierta usando un token aleatorio privado.
- Tiempo máximo por fase para evitar partidas bloqueadas por una desconexión.
- Salas temporales en memoria. Reiniciar el servidor elimina partidas activas.
- Voz tipo pulsar-para-hablar: PCM mono a 16 kHz, paquetes de 40 ms. Solo sala, debate y final; micrófono detenido al soltar, cambiar fase o ir a segundo plano.
- La voz se transmite por WebSocket/WSS: primera implementación para grupos pequeños. No tiene cancelación de eco ni Opus; con redes malas puede tener más retraso que WebRTC. Usar auriculares durante la prueba.
- Audio y mensajes no se guardan en disco. El servidor puede procesar el audio; no hay cifrado de extremo a extremo.
- Límites de tamaño, frecuencia, conexiones y salas. La prueba comprueba aislamiento entre salas y rechazo de suplantaciones.
- Pendiente: despliegue público, prueba de voz con micrófonos en dos dispositivos reales y medición de latencia en Internet.

Referencias técnicas:
https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html
https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html
https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html

