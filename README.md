# Snake ARM

Videojuego Snake escrito en ensamblador ARM (Thumb-2) para Arduino Due (AT91SAM3X8E, Cortex-M3). Proyecto del curso Arquitectura de Computadoras II.

El jugador controla la serpiente con un joystick analógico y la imagen se muestra en una pantalla OLED SSD1306 de 128 × 64 píxeles. Los periféricos se manejan por registros mapeados en memoria, sin la API de Arduino ni bibliotecas gráficas.

## Módulos

| Archivo | Responsabilidad |
|---|---|
| `main_arm.S` | Programa principal y máquina de estados (menú, juego, game over) |
| `game_arm.S` | Lógica del Snake: movimiento, comida, colisiones y puntaje |
| `video_arm.S` | Pantalla OLED por SPI, framebuffer de 1024 bytes y fuente 5 × 7 |
| `inputs_arm.S` | Joystick: ADC (ejes X/Y) y botón Z |
| `timer_arm.S` | Temporizadores por hardware (TC0) e interrupciones con NVIC |
| `control_arm.S` | Clasificación de la dirección del joystick |
| `SnakeARM.ino` | Archivo mínimo en C: solo llama a `asm_main` |

## Conexiones

| Módulo | Pin del módulo | Pin del Due | Pin del microcontrolador |
|---|---|---|---|
| OLED | SCK | 13 | PB27 |
| OLED | SDA | 11 | PD7 |
| OLED | CS | 10 | PC29 |
| OLED | DC | 9 | PC21 |
| OLED | RES | 8 | PC22 |
| Joystick | VRx | A0 | PA16 (ADC canal 7) |
| Joystick | VRy | A1 | PA24 (ADC canal 6) |
| Joystick | SW | 2 | PB25 |

Alimentación de ambos módulos: 3.3 V y GND.

## Cómo compilar y cargar

1. Descargar el repositorio en una carpeta llamada `SnakeARM`.
2. Abrir `SnakeARM.ino` con el Arduino IDE y elegir la placa Arduino Due (Programming Port).
3. Verificar y Subir. No se necesita ninguna biblioteca.

El IDE se usa solo para ensamblar y cargar el programa. Su código de inicio configura la tabla de vectores y el reloj de 84 MHz antes de entrar a `asm_main`.

## Tiempos

- Cuadros: 30 por segundo (TC0 canal 0, interrupción 27).
- Física del juego: un paso cada 150 ms (TC0 canal 1, interrupción 28).

## Documentación

El reporte técnico (`Reporte_Tecnico_SnakeARM.docx`) detalla el mapa de memoria, la máquina de estados, el esquema de conexión y el cálculo de tiempos de refresco.
