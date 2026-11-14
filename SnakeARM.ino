// =====================================================================
// SnakeARM.ino - Archivo minimo en C permitido por el enunciado.
//
// Solo entrega el control al programa en ensamblador. No usa ninguna
// funcion de Arduino ni bibliotecas: toda la logica del juego, el
// dibujo, la lectura del joystick y los temporizadores estan en los
// archivos .S de esta carpeta.
// =====================================================================

extern "C" void asm_main(void);

void setup() {
    asm_main();     // no retorna
}

void loop() {
}
