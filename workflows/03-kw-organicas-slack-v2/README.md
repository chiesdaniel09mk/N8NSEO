# 03 - KW Organicas Slack V2

## Que hace
Compara cambios de keywords organicas por cliente y publica resumen/alertas en Slack.

## Disparador
Manual Trigger (recomendado cambiar a Schedule en produccion).

## Entradas
- Google Sheets `MASTER_SEO_CLIENTES`
- Google Sheets cliente `CAMBIOS_KW_ORGANICAS`
- Variables de entorno Slack

## Salidas
- Mensaje de resumen al canal central
- Mensaje de urgentes al canal del cliente
- Actualizacion de `slack_canal_cliente_id` y `hora_generado` en MASTER

## Credenciales necesarias (sin secretos)
- Google Sheets OAuth2
- `SLACK_BOT_TOKEN` en entorno
- `SLACK_CENTRAL_CHANNEL_ID` en entorno

## Notas por nodos/puntos delicados
- El flujo usa `splitInBatches` para procesar 1 cliente cada vez.
- Si no existe canal de cliente, intenta resolver por nombre y crearlo.
- Evita mensajes vacios cuando no hay urgentes/top10.

## Como probar
1. Ejecutar manualmente en n8n.
2. Verificar que publica resumen en el canal central.
3. Verificar que publica urgentes en canal cliente cuando aplica.
4. Confirmar que actualiza `hora_generado` en MASTER.
