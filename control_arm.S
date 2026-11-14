
.syntax unified
.cpu cortex-m3
.thumb

.text
.align 2

.global clasificar_joystick
.type clasificar_joystick, %function

clasificar_joystick:

    // Comprobar movimiento hacia la izquierda
    ldr r2, =1000
    cmp r0, r2
    blt izquierda

    // Comprobar movimiento hacia la derecha
    ldr r2, =3000
    cmp r0, r2
    bgt derecha

    // Comprobar movimiento hacia arriba
    ldr r2, =1000
    cmp r1, r2
    blt arriba

    // Comprobar movimiento hacia abajo
    ldr r2, =3000
    cmp r1, r2
    bgt abajo

    // Si no hay movimiento, retornar centro
    movs r0, #0
    bx lr

izquierda:
    movs r0, #1
    bx lr

derecha:
    movs r0, #2
    bx lr

arriba:
    movs r0, #3
    bx lr

abajo:
    movs r0, #4
    bx lr

.size clasificar_joystick, .-clasificar_joystick
