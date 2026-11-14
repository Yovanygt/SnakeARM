@ =====================================================================
@ game_arm.S - Logica del juego Snake en ensamblador ARM (Cortex-M3)
@ Arduino Due (AT91SAM3X8E)
@
@ Tablero logico: 32 columnas x 13 filas (celdas de 4x4 pixeles).
@ Este archivo NO dibuja nada: solo calcula el estado del juego.
@
@ Direcciones (mismas que devuelve clasificar_joystick):
@   0 = centro, 1 = izquierda, 2 = derecha, 3 = arriba, 4 = abajo
@
@ Funciones publicas (convencion AAPCS, llamables desde C):
@   void game_init(void)
@   void game_set_seed(unsigned int semilla)
@   void game_set_dir(int dir)
@   int  game_step(void)      -> 0 = se movio, 1 = comio, 2 = game over
@
@ Variables publicas (se leen desde C para dibujar):
@   game_len, game_score, game_state (0 = jugando, 1 = game over)
@   food_x, food_y, snake_x[], snake_y[]  (indice 0 = cabeza)
@ =====================================================================

.syntax unified
.cpu cortex-m3
.thumb

.equ GRID_W,  32            @ debe ser potencia de 2 (se usa AND 31)
.equ GRID_H,  13
.equ MAX_LEN, 416           @ GRID_W * GRID_H

@ ---------------------------------------------------------------------
@ Datos en RAM (se inicializan en cero al arrancar)
@ ---------------------------------------------------------------------
.section .bss
.align 2
.global game_len
.global game_dir
.global game_next
.global game_score
.global game_state
.global game_seed
.global food_x
.global food_y
.global snake_x
.global snake_y

game_len:    .space 4
game_dir:    .space 4       @ direccion usada en el ultimo paso
game_next:   .space 4       @ direccion pedida para el proximo paso
game_score:  .space 4
game_state:  .space 4
game_seed:   .space 4
food_x:      .space 4
food_y:      .space 4
snake_x:     .space MAX_LEN
snake_y:     .space MAX_LEN

@ ---------------------------------------------------------------------
@ Tablas de desplazamiento por direccion (indice 0 sin uso)
@ ---------------------------------------------------------------------
.section .rodata
dir_dx:      .byte 0, -1, 1, 0, 0
dir_dy:      .byte 0, 0, 0, -1, 1

.text
.align 2

@ =====================================================================
@ void game_set_seed(unsigned int semilla)
@ =====================================================================
.global game_set_seed
.type game_set_seed, %function
game_set_seed:
    ldr     r1, =game_seed
    str     r0, [r1]
    bx      lr
.size game_set_seed, .-game_set_seed
.ltorg

@ =====================================================================
@ void game_set_dir(int dir)
@ Ignora 0 y valores fuera de 1..4. Ignora el giro de 180 grados
@ respecto a la direccion del ultimo paso (la serpiente no se da vuelta).
@ =====================================================================
.global game_set_dir
.type game_set_dir, %function
game_set_dir:
    cmp     r0, #1
    blt     .Lsd_fin
    cmp     r0, #4
    bgt     .Lsd_fin
    ldr     r1, =game_dir
    ldr     r1, [r1]            @ r1 = direccion actual
    subs    r2, r0, #1
    eor     r2, r2, #1
    adds    r2, r2, #1          @ r2 = opuesta de dir (1<->2, 3<->4)
    cmp     r2, r1
    beq     .Lsd_fin
    ldr     r1, =game_next
    str     r0, [r1]
.Lsd_fin:
    bx      lr
.size game_set_dir, .-game_set_dir
.ltorg

@ =====================================================================
@ static spawn_food: coloca la comida en una celda libre (generador LCG)
@ seed = seed * 1664525 + 1013904223
@ Usa r0-r3 y preserva r4-r8.
@ =====================================================================
.type spawn_food, %function
spawn_food:
    push    {r4-r8, lr}
.Lsf_retry:
    ldr     r4, =game_seed
    ldr     r0, [r4]
    ldr     r1, =1664525
    mul     r0, r0, r1
    ldr     r1, =1013904223
    adds    r0, r0, r1
    str     r0, [r4]
    lsrs    r5, r0, #16
    ands    r5, r5, #31         @ x = 0..31
    lsrs    r6, r0, #8
    ands    r6, r6, #255
    movs    r1, #GRID_H
    udiv    r2, r6, r1
    mls     r6, r2, r1, r6      @ y = (bits 8..15) mod GRID_H
    ldr     r7, =game_len
    ldr     r7, [r7]
    ldr     r2, =snake_x
    ldr     r3, =snake_y
.Lsf_chk:
    cbz     r7, .Lsf_ok
    subs    r7, r7, #1
    ldrb    r0, [r2, r7]
    cmp     r0, r5
    bne     .Lsf_chk
    ldrb    r0, [r3, r7]
    cmp     r0, r6
    bne     .Lsf_chk
    b       .Lsf_retry          @ la celda esta sobre la serpiente
.Lsf_ok:
    ldr     r0, =food_x
    str     r5, [r0]
    ldr     r0, =food_y
    str     r6, [r0]
    pop     {r4-r8, pc}
.size spawn_food, .-spawn_food
.ltorg

@ =====================================================================
@ void game_init(void)
@ Reinicia el estado: serpiente de 3 segmentos al centro, mirando a la
@ derecha, puntaje 0, juego activo y primera comida.
@ =====================================================================
.global game_init
.type game_init, %function
game_init:
    push    {r4, lr}
    movs    r1, #3
    ldr     r0, =game_len
    str     r1, [r0]
    movs    r1, #2
    ldr     r0, =game_dir
    str     r1, [r0]
    ldr     r0, =game_next
    str     r1, [r0]
    movs    r1, #0
    ldr     r0, =game_score
    str     r1, [r0]
    ldr     r0, =game_state
    str     r1, [r0]
    ldr     r0, =snake_x
    movs    r1, #10
    strb    r1, [r0, #0]
    movs    r1, #9
    strb    r1, [r0, #1]
    movs    r1, #8
    strb    r1, [r0, #2]
    ldr     r0, =snake_y
    movs    r1, #6
    strb    r1, [r0, #0]
    strb    r1, [r0, #1]
    strb    r1, [r0, #2]
    bl      spawn_food
    pop     {r4, pc}
.size game_init, .-game_init
.ltorg

@ =====================================================================
@ int game_step(void)
@ Avanza la serpiente una celda.
@ Retorna: 0 = se movio, 1 = comio, 2 = game over
@ =====================================================================
.global game_step
.type game_step, %function
game_step:
    push    {r4-r8, lr}
    ldr     r4, =game_state
    ldr     r0, [r4]
    cmp     r0, #0
    bne     .Lgs_over_ret       @ ya habia terminado

    ldr     r1, =game_next
    ldr     r5, [r1]            @ r5 = direccion de este paso
    ldr     r1, =game_dir
    str     r5, [r1]

    ldr     r2, =snake_x
    ldr     r3, =snake_y
    ldrb    r6, [r2]            @ r6 = x de la cabeza
    ldrb    r7, [r3]            @ r7 = y de la cabeza
    ldr     r0, =dir_dx
    ldrsb   r1, [r0, r5]
    adds    r6, r6, r1          @ nueva x
    ldr     r0, =dir_dy
    ldrsb   r1, [r0, r5]
    adds    r7, r7, r1          @ nueva y

    cmp     r6, #GRID_W         @ comparacion sin signo: negativos = enormes
    bhs     .Lgs_over
    cmp     r7, #GRID_H
    bhs     .Lgs_over

    ldr     r8, =game_len
    ldr     r8, [r8]
.Lgs_self:
    cmp     r8, #0
    beq     .Lgs_free
    subs    r8, r8, #1
    ldrb    r0, [r2, r8]
    cmp     r0, r6
    bne     .Lgs_self
    ldrb    r0, [r3, r8]
    cmp     r0, r7
    bne     .Lgs_self
    b       .Lgs_over           @ choco con su propio cuerpo
.Lgs_free:

    movs    r4, #0              @ r4 = bandera "comio"
    ldr     r0, =food_x
    ldr     r0, [r0]
    ldr     r1, =food_y
    ldr     r1, [r1]
    cmp     r0, r6
    bne     .Lgs_shift
    cmp     r1, r7
    bne     .Lgs_shift
    movs    r4, #1
    ldr     r0, =game_len       @ crece un segmento
    ldr     r1, [r0]
    adds    r1, r1, #1
    str     r1, [r0]

.Lgs_shift:
    ldr     r8, =game_len
    ldr     r8, [r8]
.Lgs_sh:
    subs    r8, r8, #1
    beq     .Lgs_head
    subs    r0, r8, #1
    ldrb    r1, [r2, r0]
    strb    r1, [r2, r8]
    ldrb    r1, [r3, r0]
    strb    r1, [r3, r8]
    b       .Lgs_sh

.Lgs_head:
    strb    r6, [r2]
    strb    r7, [r3]
    cmp     r4, #0
    beq     .Lgs_moved
    ldr     r0, =game_score
    ldr     r1, [r0]
    adds    r1, r1, #1
    str     r1, [r0]
    bl      spawn_food
    movs    r0, #1
    b       .Lgs_ret
.Lgs_moved:
    movs    r0, #0
    b       .Lgs_ret

.Lgs_over:
    movs    r1, #1
    ldr     r0, =game_state
    str     r1, [r0]
.Lgs_over_ret:
    movs    r0, #2
.Lgs_ret:
    pop     {r4-r8, pc}
.size game_step, .-game_step
.ltorg
