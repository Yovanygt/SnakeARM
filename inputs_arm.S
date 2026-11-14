@ =====================================================================
@ inputs_arm.S - Lectura del joystick por registros
@ Arduino Due (AT91SAM3X8E, Cortex-M3)
@
@   Eje X  -> A0 = PA16 = canal 7 del ADC
@   Eje Y  -> A1 = PA24 = canal 6 del ADC
@   Boton Z -> pin 2 = PB25 (entrada con pull-up, presionado = 0)
@
@ Funciones publicas (AAPCS):
@   void inputs_init(void)
@   void inputs_read(void)       -> actualiza joy_x y joy_y (0..4095)
@   int  inputs_button(void)     -> 1 = presionado, 0 = libre
@ =====================================================================

.syntax unified
.cpu cortex-m3
.thumb

.equ PMC_PCER0,   0x400E0610      @ reloj de perifericos 0..31
.equ PMC_PCER1,   0x400E0700      @ reloj de perifericos 32..63
.equ PIOA,        0x400E0E00
.equ PIOB,        0x400E1000
.equ ADC,         0x400C0000

.equ PIO_PER,     0x00            @ el PIO controla el pin
.equ PIO_ODR,     0x14            @ pin como entrada
.equ PIO_PDSR,    0x3C            @ nivel real del pin
.equ PIO_PUDR,    0x60            @ quitar pull-up
.equ PIO_PUER,    0x64            @ poner pull-up

.equ ADC_CR,      0x00            @ control: START = bit 1
.equ ADC_MR,      0x04            @ modo
.equ ADC_CHER,    0x10            @ habilitar canales
.equ ADC_CHDR,    0x14            @ deshabilitar canales
.equ ADC_ISR,     0x30            @ fin de conversion por canal
.equ ADC_CDR6,    0x68            @ dato del canal 6
.equ ADC_CDR7,    0x6C            @ dato del canal 7

.equ PIO_CLK_MASK, 0x00007800     @ ID 11..14 = PIOA, PIOB, PIOC, PIOD
.equ ADC_CLK_MASK, 0x00000020     @ ID 37 = ADC (bit 5 de PCER1)
.equ BTN_MASK,     0x02000000     @ PB25
.equ AN_MASK,      0x01010000     @ PA24 y PA16
.equ ADC_MODE,     0x2F080200     @ PRESCAL=2, STARTUP=8, TRACKTIM=15, TRANSFER=2
.equ ADC_CH_MASK,  0x000000C0     @ canales 6 y 7
.equ ADC_TIMEOUT,  20000

.section .bss
.align 2
.global joy_x
.global joy_y
joy_x:  .space 4
joy_y:  .space 4

.text
.align 2

@ =====================================================================
@ void inputs_init(void)
@ =====================================================================
.global inputs_init
.type inputs_init, %function
inputs_init:
    ldr     r0, =PMC_PCER0
    ldr     r1, =PIO_CLK_MASK
    str     r1, [r0]                @ reloj a los puertos PIO
    ldr     r0, =PMC_PCER1
    movs    r1, #ADC_CLK_MASK
    str     r1, [r0]                @ reloj al ADC

    ldr     r0, =PIOB               @ boton: entrada con pull-up
    ldr     r1, =BTN_MASK
    str     r1, [r0, #PIO_PER]
    str     r1, [r0, #PIO_ODR]
    str     r1, [r0, #PIO_PUER]

    ldr     r0, =PIOA               @ pines analogicos sin pull-up
    ldr     r1, =AN_MASK
    str     r1, [r0, #PIO_PUDR]

    ldr     r0, =ADC
    ldr     r1, =ADC_MODE
    str     r1, [r0, #ADC_MR]
    ldr     r1, =0xFFFF
    str     r1, [r0, #ADC_CHDR]     @ apagar todos los canales
    movs    r1, #ADC_CH_MASK
    str     r1, [r0, #ADC_CHER]     @ encender canales 6 y 7
    bx      lr
.size inputs_init, .-inputs_init
.ltorg

@ =====================================================================
@ void inputs_read(void)
@ Lanza una conversion, espera el fin de los dos canales (con limite
@ de espera para no bloquear) y guarda los resultados de 12 bits.
@ =====================================================================
.global inputs_read
.type inputs_read, %function
inputs_read:
    ldr     r0, =ADC
    movs    r1, #2                  @ START
    str     r1, [r0, #ADC_CR]
    ldr     r2, =ADC_TIMEOUT
.Lir_wait:
    ldr     r1, [r0, #ADC_ISR]
    ands    r1, r1, #ADC_CH_MASK
    cmp     r1, #ADC_CH_MASK
    beq     .Lir_done
    subs    r2, r2, #1
    bne     .Lir_wait
.Lir_done:
    ldr     r1, [r0, #ADC_CDR7]
    ubfx    r1, r1, #0, #12
    ldr     r2, =joy_x
    str     r1, [r2]
    ldr     r1, [r0, #ADC_CDR6]
    ubfx    r1, r1, #0, #12
    ldr     r2, =joy_y
    str     r1, [r2]
    bx      lr
.size inputs_read, .-inputs_read
.ltorg

@ =====================================================================
@ int inputs_button(void) -> 1 si el boton Z esta presionado
@ =====================================================================
.global inputs_button
.type inputs_button, %function
inputs_button:
    ldr     r0, =PIOB
    ldr     r1, [r0, #PIO_PDSR]
    lsrs    r1, r1, #25
    ands    r1, r1, #1
    eor     r0, r1, #1              @ el boton conecta a tierra
    bx      lr
.size inputs_button, .-inputs_button
.ltorg
