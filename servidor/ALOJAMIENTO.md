# Alojamiento recomendado para la primera prueba: Render Free
No necesitás un dominio propio. Render proporciona una URL onrender.com y HTTPS/WSS.
La receta render.yaml crea un solo servicio web gratuito, sin base de datos. Las salas son temporales y se pierden si reinicia el servidor.

## Activación
1. Subí el paquete Lobo-Servidor-0.4.0 a un repositorio de tu cuenta GitHub.
2. Entrá a Render y conectá ese repositorio. Usá New > Blueprint con el render.yaml incluido, o New > Web Service, runtime Docker, Dockerfile servidor/Dockerfile, plan Free.
3. Esperá a que el registro diga LOBO_SERVER_READY.
4. Copiá la dirección HTTPS que Render asigne. Para el juego se convierte en wss://NOMBRE.onrender.com.
5. Configurá esa dirección en datos/online.json del proyecto Godot y exportá otra APK. Ese mismo archivo sirve para probar los clientes desde Godot.
6. Probá con dos teléfonos en redes distintas; verificá roles, acciones, desconexión y voz.

La infraestructura no fue creada: falta conectar la cuenta del propietario. No se contrató ni pagó ningún servicio.

El plan gratuito se suspende después de 15 minutos sin tráfico y puede tardar alrededor de un minuto en despertar. Los mensajes WebSocket mantienen activa la instancia durante la partida. Tiene límites de horas, tráfico y compilaciones; revisalos en tu cuenta.
Para sesiones más constantes, el servicio Starter parte de USD 7 al mes; la transferencia y otros consumos pueden añadir costos. La voz consume más tráfico que las acciones.
Esta entrega usa Free por defecto; no activa planes pagos.

Fuentes oficiales consultadas:
https://render.com/docs/your-first-deploy
https://render.com/changelog/free-web-services-now-remain-active-while-receiving-websocket-messages
https://render.com/docs/websocket
https://render.com/pricing

