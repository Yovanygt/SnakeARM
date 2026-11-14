@ =====================================================================
@ main_arm.S - Programa principal y maquina de estados del juego
@ Arduino Due (AT91SAM3X8E, Cortex-M3)
@
@ Estados:
@   0 = MENU      pantalla con el nombre del juego, espera el boton Z
@   1 = JUGANDO   lee el joystick, avanza la fisica y dibuja
@   2 = GAME OVER muestra el puntaje, temporizador de fisicas detenido
@
@ El bucle principal no usa retardos: duerme con WFI y despierta con
@ la interrupcion del temporizador de cuadros (30 Hz).
@
@ Funciones publicas (AAPCS):
@   void asm_main(void)     -> punto de entrada, no retorna
@   void app_frame(void)    -> procesa y dibuja un cuadro
@ =====================================================================

.syntax unified
.cpu cortex-m3
.thumb

.equ ST_MENU,   0
.equ ST_PLAY,   1
.equ ST_OVER,   2
.equ OFFSET_Y,  12                @ el tablero empieza debajo del marcador

.section .bss
.align 2
.global app_state
app_state:  .space 4              @ estado actual
prev_btn:   .space 4              @ boton en el cuadro anterior

.section .rodata
str_title:  .asciz "SNAKE ARM"
str_press:  .asciz "PULSA Z"
str_pts:    .asciz "PTS:"
str_over:   .asciz "GAME OVER"
str_score:  .asciz "PUNTOS:"
str_back:   .asciz "Z = MENU"

.text
.align 2

@ =====================================================================
@ void asm_main(void)
@ =====================================================================
.global asm_main
.type asm_main, %function
asm_main:
    push    {r4, lr}
    bl      inputs_init
    bl      video_init
    bl      timer_init
    ldr     r0, =app_state          @ reinicio de registros de estado
    movs    r1, #ST_MENU
    str     r1, [r0]
    ldr     r0, =prev_btn
    str     r1, [r0]
.Lam_loop:
    ldr     r0, =frame_flag
    ldr     r1, [r0]
    cmp     r1, #0
    bne     .Lam_frame
    wfi                             @ dormir hasta la proxima interrupcion
    b       .Lam_loop
.Lam_frame:
    movs    r1, #0
    str     r1, [r0]
    bl      app_frame
    b       .Lam_loop
.size asm_main, .-asm_main
.ltorg

@ =====================================================================
@ void app_frame(void): un cuadro del juego (se ejecuta 30 veces/seg)
@   r4 = 1 si el boton Z se acaba de presionar (flanco)
@   r5 = direccion de app_state
@   r6 = estado con el que se dibuja este cuadro
@ =====================================================================
.global app_frame
.type app_frame, %function
app_frame:
    push    {r4, r5, r6, lr}
    bl      inputs_button
    ldr     r1, =prev_btn
    ldr     r2, [r1]
    str     r0, [r1]
    movs    r4, #0
    cmp     r0, #1
    bne     .Laf_state
    cmp     r2, #0
    bne     .Laf_state
    movs    r4, #1                  @ flanco: antes libre, ahora presionado
.Laf_state:
    ldr     r5, =app_state
    ldr     r6, [r5]
    cmp     r6, #ST_PLAY
    beq     .Laf_play
    cmp     r6, #ST_OVER
    beq     .Laf_over

    @ ---------------- MENU ----------------
    cmp     r4, #0
    beq     .Laf_draw
    bl      timer_get_counter       @ semilla: instante en que se pulso Z
    bl      game_set_seed
    bl      game_init
    bl      timer_physics_start
    movs    r6, #ST_PLAY
    str     r6, [r5]
    b       .Laf_draw

    @ ---------------- JUGANDO ----------------
.Laf_play:
    bl      inputs_read
    ldr     r0, =joy_x
    ldr     r0, [r0]
    ldr     r1, =joy_y
    ldr     r1, [r1]
    bl      clasificar_joystick
    bl      game_set_dir
    ldr     r0, =phys_flag
    ldr     r1, [r0]
    cmp     r1, #0
    beq     .Laf_draw               @ todavia no toca mover la serpiente
    movs    r1, #0
    str     r1, [r0]
    bl      game_step
    cmp     r0, #2
    bne     .Laf_draw
    bl      timer_physics_stop      @ game over: detener las fisicas
    movs    r6, #ST_OVER
    str     r6, [r5]
    b       .Laf_draw

    @ ---------------- GAME OVER ----------------
.Laf_over:
    cmp     r4, #0
    beq     .Laf_draw
    movs    r6, #ST_MENU
    str     r6, [r5]

    @ ---------------- DIBUJO ----------------
.Laf_draw:
    cmp     r6, #ST_PLAY
    beq     .Laf_dgame
    cmp     r6, #ST_OVER
    beq     .Laf_dover
    bl      draw_menu
    b       .Laf_flush
.Laf_dgame:
    bl      draw_game
    b       .Laf_flush
.Laf_dover:
    bl      draw_over
.Laf_flush:
    bl      video_flush
    pop     {r4, r5, r6, pc}
.size app_frame, .-app_frame
.ltorg

@ =====================================================================
@ static draw_menu: pantalla inicial con el nombre del juego
@ =====================================================================
.type draw_menu, %function
draw_menu:
    push    {r4, lr}
    bl      video_clear
    movs    r0, #0
    movs    r1, #0
    movs    r2, #128
    movs    r3, #64
    bl      video_frame_rect
    movs    r0, #37
    movs    r1, #20
    ldr     r2, =str_title
    bl      video_text
    movs    r0, #43
    movs    r1, #40
    ldr     r2, =str_press
    bl      video_text
    pop     {r4, pc}
.size draw_menu, .-draw_menu
.ltorg

@ =====================================================================
@ static draw_game: marcador (HUD), serpiente y comida
@ Cada celda del tablero mide 4x4 pixeles y se dibuja de 3x3.
@ =====================================================================
.type draw_game, %function
draw_game:
    push    {r4, r5, r6, lr}
    bl      video_clear
    movs    r0, #0
    movs    r1, #1
    ldr     r2, =str_pts
    bl      video_text
    movs    r0, #26
    movs    r1, #1
    ldr     r2, =game_score
    ldr     r2, [r2]
    bl      video_number
    movs    r0, #0                  @ linea que separa el marcador
    movs    r1, #10
    movs    r2, #128
    movs    r3, #1
    bl      video_fill_rect

    ldr     r4, =game_len
    ldr     r4, [r4]                @ cantidad de segmentos
    movs    r5, #0                  @ indice
.Ldg_loop:
    cmp     r5, r4
    bhs     .Ldg_food
    ldr     r0, =snake_x
    ldrb    r0, [r0, r5]
    lsls    r0, r0, #2              @ x * 4
    ldr     r1, =snake_y
    ldrb    r1, [r1, r5]
    lsls    r1, r1, #2              @ y * 4
    adds    r1, r1, #OFFSET_Y
    movs    r2, #3
    movs    r3, #3
    bl      video_fill_rect
    adds    r5, r5, #1
    b       .Ldg_loop
.Ldg_food:
    ldr     r0, =food_x
    ldr     r0, [r0]
    lsls    r0, r0, #2
    ldr     r1, =food_y
    ldr     r1, [r1]
    lsls    r1, r1, #2
    adds    r1, r1, #OFFSET_Y
    movs    r2, #3
    movs    r3, #3
    bl      video_frame_rect
    pop     {r4, r5, r6, pc}
.size draw_game, .-draw_game
.ltorg

@ =====================================================================
@ static draw_over: pantalla de fin de partida con el puntaje
@ =====================================================================
.type draw_over, %function
draw_over:
    push    {r4, lr}
    bl      video_clear
    movs    r0, #0
    movs    r1, #0
    movs    r2, #128
    movs    r3, #64
    bl      video_frame_rect
    movs    r0, #37
    movs    r1, #14
    ldr     r2, =str_over
    bl      video_text
    movs    r0, #28
    movs    r1, #30
    ldr     r2, =str_score
    bl      video_text
    movs    r0, #74
    movs    r1, #30
    ldr     r2, =game_score
    ldr     r2, [r2]
    bl      video_number
    movs    r0, #40
    movs    r1, #48
    ldr     r2, =str_back
    bl      video_text
    pop     {r4, pc}
.size draw_over, .-draw_over
.ltorg
