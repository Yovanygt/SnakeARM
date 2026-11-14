@ =====================================================================
@ timer_arm.S - Temporizadores por hardware e interrupciones (NVIC)
@ Arduino Due (AT91SAM3X8E, Cortex-M3) - acceso directo a registros
@
@ Se usan dos canales del periferico TC0 (Timer Counter):
@   Canal 0 (ID 27): reloj de cuadros, 30 Hz  -> bandera frame_flag
@   Canal 1 (ID 28): reloj de fisicas, 150 ms -> bandera phys_flag
@
@ Reloj de conteo: MCK/128 = 84 MHz / 128 = 656250 Hz
@   RC cuadros = 656250 / 30      = 21875
@   RC fisicas = 656250 * 0.150 s = 98438
@
@ Funciones publicas (AAPCS):
@   void timer_init(void)
@   void timer_physics_start(void)
@   void timer_physics_stop(void)
@   unsigned int timer_get_counter(void)
@ Manejadores de interrupcion: TC0_Handler, TC1_Handler
@ =====================================================================

.syntax unified
.cpu cortex-m3
.thumb

.equ PMC_PCER0,    0x400E0610     @ habilita reloj de perifericos 0..31
.equ TC0_CH0,      0x40080000     @ TC0 canal 0
.equ TC0_CH1,      0x40080040     @ TC0 canal 1
.equ NVIC_ISER0,   0xE000E100     @ habilitar interrupciones 0..31
.equ NVIC_ICPR0,   0xE000E280     @ limpiar interrupciones pendientes

.equ TC_CCR,       0x00           @ control: CLKEN=1, CLKDIS=2, SWTRG=4
.equ TC_CMR,       0x04           @ modo
.equ TC_CV,        0x10           @ valor del contador
.equ TC_RC,        0x1C           @ registro de comparacion C
.equ TC_SR,        0x20           @ estado (leerlo limpia las banderas)
.equ TC_IER,       0x24           @ habilitar interrupcion
.equ TC_IDR,       0x28           @ deshabilitar interrupcion

.equ TC_MODE,      0x0000C003     @ WAVE | WAVSEL=UP_RC | TIMER_CLOCK4
.equ TC_CPCS,      0x10           @ bit 4: comparacion con RC
.equ RC_FRAME,     21875          @ 30 Hz
.equ RC_PHYS,      98438          @ 150 ms
.equ TC_IDS_MASK,  0x18000000     @ bits 27 y 28 (ID_TC0, ID_TC1)
.equ TC1_ID_MASK,  0x10000000     @ bit 28

.section .bss
.align 2
.global frame_flag
.global phys_flag
frame_flag:  .space 4             @ 1 = toca dibujar un cuadro
phys_flag:   .space 4             @ 1 = toca avanzar la fisica

.text
.align 2

@ =====================================================================
@ void timer_init(void)
@ Configura los dos canales, habilita sus interrupciones en el NVIC y
@ arranca el canal de cuadros. El de fisicas queda detenido.
@ =====================================================================
.global timer_init
.type timer_init, %function
timer_init:
    ldr     r0, =PMC_PCER0
    ldr     r1, =TC_IDS_MASK
    str     r1, [r0]                @ reloj a TC0 canal 0 y canal 1

    ldr     r0, =TC0_CH0
    ldr     r1, =TC_MODE
    str     r1, [r0, #TC_CMR]
    ldr     r1, =RC_FRAME
    str     r1, [r0, #TC_RC]
    movs    r1, #TC_CPCS
    str     r1, [r0, #TC_IER]       @ interrupcion al llegar a RC

    ldr     r0, =TC0_CH1
    ldr     r1, =TC_MODE
    str     r1, [r0, #TC_CMR]
    ldr     r1, =RC_PHYS
    str     r1, [r0, #TC_RC]

    ldr     r0, =NVIC_ISER0
    ldr     r1, =TC_IDS_MASK
    str     r1, [r0]                @ NVIC: habilitar IRQ 27 y 28

    ldr     r0, =TC0_CH0
    movs    r1, #5                  @ CLKEN | SWTRG
    str     r1, [r0, #TC_CCR]
    bx      lr
.size timer_init, .-timer_init
.ltorg

@ =====================================================================
@ void timer_physics_start(void) - arranca el temporizador de fisicas
@ =====================================================================
.global timer_physics_start
.type timer_physics_start, %function
timer_physics_start:
    ldr     r0, =phys_flag
    movs    r1, #0
    str     r1, [r0]
    ldr     r0, =TC0_CH1
    movs    r1, #TC_CPCS
    str     r1, [r0, #TC_IER]
    movs    r1, #5                  @ CLKEN | SWTRG
    str     r1, [r0, #TC_CCR]
    bx      lr
.size timer_physics_start, .-timer_physics_start
.ltorg

@ =====================================================================
@ void timer_physics_stop(void) - detencion total del temporizador de
@ fisicas (se usa en Game Over)
@ =====================================================================
.global timer_physics_stop
.type timer_physics_stop, %function
timer_physics_stop:
    ldr     r0, =TC0_CH1
    movs    r1, #TC_CPCS
    str     r1, [r0, #TC_IDR]       @ sin interrupcion
    movs    r1, #2                  @ CLKDIS: detiene el contador
    str     r1, [r0, #TC_CCR]
    ldr     r1, [r0, #TC_SR]        @ limpia banderas del canal
    ldr     r0, =NVIC_ICPR0
    ldr     r1, =TC1_ID_MASK
    str     r1, [r0]                @ limpia interrupcion pendiente
    ldr     r0, =phys_flag
    movs    r1, #0
    str     r1, [r0]
    bx      lr
.size timer_physics_stop, .-timer_physics_stop
.ltorg

@ =====================================================================
@ unsigned int timer_get_counter(void) - contador libre (semilla)
@ =====================================================================
.global timer_get_counter
.type timer_get_counter, %function
timer_get_counter:
    ldr     r0, =TC0_CH0
    ldr     r0, [r0, #TC_CV]
    bx      lr
.size timer_get_counter, .-timer_get_counter
.ltorg

@ =====================================================================
@ Interrupcion del canal 0: marca que toca un cuadro nuevo.
@ El procesador guarda r0-r3, r12, lr, pc y xPSR automaticamente.
@ =====================================================================
.global TC0_Handler
.type TC0_Handler, %function
TC0_Handler:
    ldr     r0, =TC0_CH0
    ldr     r1, [r0, #TC_SR]        @ leer el estado limpia la peticion
    ldr     r0, =frame_flag
    movs    r1, #1
    str     r1, [r0]
    bx      lr
.size TC0_Handler, .-TC0_Handler
.ltorg

@ =====================================================================
@ Interrupcion del canal 1: marca que toca un paso de fisica.
@ =====================================================================
.global TC1_Handler
.type TC1_Handler, %function
TC1_Handler:
    ldr     r0, =TC0_CH1
    ldr     r1, [r0, #TC_SR]
    ldr     r0, =phys_flag
    movs    r1, #1
    str     r1, [r0]
    bx      lr
.size TC1_Handler, .-TC1_Handler
.ltorg
