@ =====================================================================
@ video_arm.S - Pantalla OLED SSD1306 128x64 por SPI (bit-banging)
@ Arduino Due (AT91SAM3X8E, Cortex-M3) - acceso directo a registros PIO
@
@   SCK  -> pin 13 = PB27        CS  -> pin 10 = PC29
@   MOSI -> pin 11 = PD7         DC  -> pin 9  = PC21
@                                RES -> pin 8  = PC22
@
@ Framebuffer: 1024 bytes en RAM (128 x 64 / 8). Todo se dibuja en el
@ buffer y video_flush lo envia completo a la pantalla (sin parpadeo).
@ Organizacion: byte = (y / 8) * 128 + x, bit = y % 8.
@
@ Funciones publicas (AAPCS):
@   void video_init(void)
@   void video_clear(void)
@   void video_flush(void)
@   void video_pixel(int x, int y)
@   void video_fill_rect(int x, int y, int w, int h)
@   void video_frame_rect(int x, int y, int w, int h)
@   void video_char(int x, int y, int caracter)
@   void video_text(int x, int y, const char *texto)
@   void video_number(int x, int y, unsigned int n)
@ =====================================================================

.syntax unified
.cpu cortex-m3
.thumb

.equ PIOB,        0x400E1000
.equ PIOC,        0x400E1200
.equ PIOD,        0x400E1400

.equ PIO_PER,     0x00            @ el PIO controla el pin
.equ PIO_OER,     0x10            @ pin como salida
.equ PIO_SODR,    0x30            @ poner el pin en 1
.equ PIO_CODR,    0x34            @ poner el pin en 0

.equ SCK_MASK,    0x08000000      @ PB27
.equ MOSI_MASK,   0x00000080      @ PD7
.equ CS_MASK,     0x20000000      @ PC29
.equ DC_MASK,     0x00200000      @ PC21
.equ RES_MASK,    0x00400000      @ PC22
.equ PIOC_MASK,   0x20600000      @ CS | DC | RES
.equ CS_RES_MASK, 0x20400000      @ CS | RES

.equ FB_SIZE,     1024
.equ FB_WORDS,    256
.equ RESET_WAIT,  100000          @ espera corta solo en el arranque
.equ SSD_INIT_LEN, 25

@ ---------------------------------------------------------------------
@ Framebuffer en RAM
@ ---------------------------------------------------------------------
.section .bss
.align 2
.global fb
fb:     .space FB_SIZE

@ ---------------------------------------------------------------------
@ Secuencia de inicializacion del SSD1306 y fuente de 5x7 pixeles
@ ---------------------------------------------------------------------
.section .rodata
ssd_init_seq:
    .byte 0xAE                    @ pantalla apagada
    .byte 0xD5, 0x80              @ divisor de reloj
    .byte 0xA8, 0x3F              @ 64 lineas
    .byte 0xD3, 0x00              @ sin desplazamiento
    .byte 0x40                    @ linea inicial 0
    .byte 0x8D, 0x14              @ bomba de carga encendida
    .byte 0x20, 0x00              @ direccionamiento horizontal
    .byte 0xA1                    @ remapeo de columnas
    .byte 0xC8                    @ barrido de filas invertido
    .byte 0xDA, 0x12              @ configuracion de pines COM
    .byte 0x81, 0xCF              @ contraste
    .byte 0xD9, 0xF1              @ precarga
    .byte 0xDB, 0x40              @ nivel VCOMH
    .byte 0xA4                    @ mostrar contenido de la RAM
    .byte 0xA6                    @ pantalla normal (no invertida)
    .byte 0xAF                    @ pantalla encendida

@ Mapa de caracteres: 5 columnas por caracter, bit 0 = fila superior.
@ Indices: 0 espacio, 1-10 digitos, 11-36 letras A-Z, 37 ':', 38 '=', 39 '-'
font5x7:
    .byte 0x00, 0x00, 0x00, 0x00, 0x00    @ espacio
    .byte 0x3E, 0x51, 0x49, 0x45, 0x3E    @ 0
    .byte 0x00, 0x42, 0x7F, 0x40, 0x00    @ 1
    .byte 0x42, 0x61, 0x51, 0x49, 0x46    @ 2
    .byte 0x21, 0x41, 0x45, 0x4B, 0x31    @ 3
    .byte 0x18, 0x14, 0x12, 0x7F, 0x10    @ 4
    .byte 0x27, 0x45, 0x45, 0x45, 0x39    @ 5
    .byte 0x3C, 0x4A, 0x49, 0x49, 0x30    @ 6
    .byte 0x01, 0x71, 0x09, 0x05, 0x03    @ 7
    .byte 0x36, 0x49, 0x49, 0x49, 0x36    @ 8
    .byte 0x06, 0x49, 0x49, 0x29, 0x1E    @ 9
    .byte 0x7E, 0x11, 0x11, 0x11, 0x7E    @ A
    .byte 0x7F, 0x49, 0x49, 0x49, 0x36    @ B
    .byte 0x3E, 0x41, 0x41, 0x41, 0x22    @ C
    .byte 0x7F, 0x41, 0x41, 0x22, 0x1C    @ D
    .byte 0x7F, 0x49, 0x49, 0x49, 0x41    @ E
    .byte 0x7F, 0x09, 0x09, 0x09, 0x01    @ F
    .byte 0x3E, 0x41, 0x49, 0x49, 0x7A    @ G
    .byte 0x7F, 0x08, 0x08, 0x08, 0x7F    @ H
    .byte 0x00, 0x41, 0x7F, 0x41, 0x00    @ I
    .byte 0x20, 0x40, 0x41, 0x3F, 0x01    @ J
    .byte 0x7F, 0x08, 0x14, 0x22, 0x41    @ K
    .byte 0x7F, 0x40, 0x40, 0x40, 0x40    @ L
    .byte 0x7F, 0x02, 0x0C, 0x02, 0x7F    @ M
    .byte 0x7F, 0x04, 0x08, 0x10, 0x7F    @ N
    .byte 0x3E, 0x41, 0x41, 0x41, 0x3E    @ O
    .byte 0x7F, 0x09, 0x09, 0x09, 0x06    @ P
    .byte 0x3E, 0x41, 0x51, 0x21, 0x5E    @ Q
    .byte 0x7F, 0x09, 0x19, 0x29, 0x46    @ R
    .byte 0x46, 0x49, 0x49, 0x49, 0x31    @ S
    .byte 0x01, 0x01, 0x7F, 0x01, 0x01    @ T
    .byte 0x3F, 0x40, 0x40, 0x40, 0x3F    @ U
    .byte 0x1F, 0x20, 0x40, 0x20, 0x1F    @ V
    .byte 0x3F, 0x40, 0x38, 0x40, 0x3F    @ W
    .byte 0x63, 0x14, 0x08, 0x14, 0x63    @ X
    .byte 0x07, 0x08, 0x70, 0x08, 0x07    @ Y
    .byte 0x61, 0x51, 0x49, 0x45, 0x43    @ Z
    .byte 0x00, 0x36, 0x36, 0x00, 0x00    @ dos puntos
    .byte 0x14, 0x14, 0x14, 0x14, 0x14    @ igual
    .byte 0x08, 0x08, 0x08, 0x08, 0x08    @ guion

.text
.align 2

@ =====================================================================
@ static delay_loop(r0 = vueltas): espera corta, solo para el pulso de
@ reset de la pantalla durante el arranque (no se usa en el juego).
@ =====================================================================
.type delay_loop, %function
delay_loop:
.Ldl_loop:
    subs    r0, r0, #1
    bne     .Ldl_loop
    bx      lr
.size delay_loop, .-delay_loop

@ =====================================================================
@ static spi_write_byte(r0 = byte): envia 8 bits, primero el mas alto.
@ El dato se coloca con SCK en bajo y la pantalla lo lee en el flanco
@ de subida (modo SPI 0).
@ =====================================================================
.type spi_write_byte, %function
spi_write_byte:
    push    {r4, r5, r6, lr}
    ldr     r1, =PIOD
    ldr     r2, =PIOB
    ldr     r4, =MOSI_MASK
    ldr     r5, =SCK_MASK
    movs    r6, #8
.Lsw_bit:
    str     r5, [r2, #PIO_CODR]     @ SCK = 0
    tst     r0, #0x80
    ite     ne
    strne   r4, [r1, #PIO_SODR]     @ MOSI = 1
    streq   r4, [r1, #PIO_CODR]     @ MOSI = 0
    nop
    nop
    str     r5, [r2, #PIO_SODR]     @ SCK = 1 (la pantalla lee el bit)
    lsls    r0, r0, #1
    subs    r6, r6, #1
    bne     .Lsw_bit
    str     r5, [r2, #PIO_CODR]     @ SCK queda en 0
    pop     {r4, r5, r6, pc}
.size spi_write_byte, .-spi_write_byte
.ltorg

@ =====================================================================
@ static video_cmd(r0 = comando): envia un byte de comando (DC = 0)
@ =====================================================================
.type video_cmd, %function
video_cmd:
    push    {r4, lr}
    mov     r4, r0
    ldr     r1, =PIOC
    ldr     r2, =DC_MASK
    str     r2, [r1, #PIO_CODR]     @ DC = 0 (comando)
    ldr     r2, =CS_MASK
    str     r2, [r1, #PIO_CODR]     @ CS = 0 (seleccionar pantalla)
    mov     r0, r4
    bl      spi_write_byte
    ldr     r1, =PIOC
    ldr     r2, =CS_MASK
    str     r2, [r1, #PIO_SODR]     @ CS = 1
    pop     {r4, pc}
.size video_cmd, .-video_cmd
.ltorg

@ =====================================================================
@ void video_init(void)
@ Configura los 5 pines como salida, da el pulso de reset y envia la
@ secuencia de inicializacion del SSD1306.
@ =====================================================================
.global video_init
.type video_init, %function
video_init:
    push    {r4, r5, r6, lr}
    ldr     r0, =PIOB
    ldr     r1, =SCK_MASK
    str     r1, [r0, #PIO_PER]
    str     r1, [r0, #PIO_OER]
    str     r1, [r0, #PIO_CODR]     @ SCK en reposo = 0
    ldr     r0, =PIOD
    ldr     r1, =MOSI_MASK
    str     r1, [r0, #PIO_PER]
    str     r1, [r0, #PIO_OER]
    ldr     r0, =PIOC
    ldr     r1, =PIOC_MASK
    str     r1, [r0, #PIO_PER]
    str     r1, [r0, #PIO_OER]
    ldr     r1, =CS_RES_MASK
    str     r1, [r0, #PIO_SODR]     @ CS = 1, RES = 1

    ldr     r1, =RES_MASK           @ pulso de reset: bajo y luego alto
    str     r1, [r0, #PIO_CODR]
    ldr     r0, =RESET_WAIT
    bl      delay_loop
    ldr     r0, =PIOC
    ldr     r1, =RES_MASK
    str     r1, [r0, #PIO_SODR]
    ldr     r0, =RESET_WAIT
    bl      delay_loop

    ldr     r4, =ssd_init_seq
    movs    r5, #SSD_INIT_LEN
.Lvi_cmd:
    ldrb    r0, [r4], #1
    bl      video_cmd
    subs    r5, r5, #1
    bne     .Lvi_cmd

    bl      video_clear
    bl      video_flush
    pop     {r4, r5, r6, pc}
.size video_init, .-video_init
.ltorg

@ =====================================================================
@ void video_clear(void): pone en cero los 1024 bytes del framebuffer
@ =====================================================================
.global video_clear
.type video_clear, %function
video_clear:
    ldr     r0, =fb
    movs    r1, #0
    mov     r2, #FB_WORDS
.Lvc_loop:
    str     r1, [r0], #4
    subs    r2, r2, #1
    bne     .Lvc_loop
    bx      lr
.size video_clear, .-video_clear
.ltorg

@ =====================================================================
@ void video_flush(void): envia el framebuffer completo a la pantalla
@ =====================================================================
.global video_flush
.type video_flush, %function
video_flush:
    push    {r4, r5, r6, lr}
    movs    r0, #0x21               @ rango de columnas 0..127
    bl      video_cmd
    movs    r0, #0
    bl      video_cmd
    movs    r0, #127
    bl      video_cmd
    movs    r0, #0x22               @ rango de paginas 0..7
    bl      video_cmd
    movs    r0, #0
    bl      video_cmd
    movs    r0, #7
    bl      video_cmd

    ldr     r1, =PIOC
    ldr     r2, =DC_MASK
    str     r2, [r1, #PIO_SODR]     @ DC = 1 (datos)
    ldr     r2, =CS_MASK
    str     r2, [r1, #PIO_CODR]     @ CS = 0
    ldr     r4, =fb
    ldr     r5, =FB_SIZE
.Lvf_loop:
    ldrb    r0, [r4], #1
    bl      spi_write_byte
    subs    r5, r5, #1
    bne     .Lvf_loop
    ldr     r1, =PIOC
    ldr     r2, =CS_MASK
    str     r2, [r1, #PIO_SODR]     @ CS = 1
    pop     {r4, r5, r6, pc}
.size video_flush, .-video_flush
.ltorg

@ =====================================================================
@ void video_pixel(int x, int y): enciende un pixel del framebuffer.
@ Ignora coordenadas fuera de la pantalla.
@ =====================================================================
.global video_pixel
.type video_pixel, %function
video_pixel:
    cmp     r0, #128
    bhs     .Lvp_fin
    cmp     r1, #64
    bhs     .Lvp_fin
    lsrs    r2, r1, #3              @ pagina = y / 8
    lsls    r2, r2, #7              @ pagina * 128
    adds    r2, r2, r0              @ indice del byte
    ands    r1, r1, #7              @ bit = y % 8
    movs    r0, #1
    lsls    r0, r0, r1              @ mascara
    ldr     r3, =fb
    ldrb    r1, [r3, r2]
    orrs    r1, r1, r0
    strb    r1, [r3, r2]
.Lvp_fin:
    bx      lr
.size video_pixel, .-video_pixel
.ltorg

@ =====================================================================
@ void video_fill_rect(int x, int y, int w, int h): rectangulo relleno
@ =====================================================================
.global video_fill_rect
.type video_fill_rect, %function
video_fill_rect:
    push    {r4-r8, lr}
    mov     r4, r0                  @ x
    mov     r5, r1                  @ y de la fila actual
    mov     r6, r2                  @ ancho
    mov     r7, r3                  @ filas restantes
.Lfr_row:
    cmp     r7, #0
    beq     .Lfr_fin
    mov     r8, #0                  @ columna
.Lfr_col:
    cmp     r8, r6
    bhs     .Lfr_next
    add     r0, r4, r8
    mov     r1, r5
    bl      video_pixel
    add     r8, r8, #1
    b       .Lfr_col
.Lfr_next:
    adds    r5, r5, #1
    subs    r7, r7, #1
    b       .Lfr_row
.Lfr_fin:
    pop     {r4-r8, pc}
.size video_fill_rect, .-video_fill_rect

@ =====================================================================
@ void video_frame_rect(int x, int y, int w, int h): solo el contorno
@ =====================================================================
.global video_frame_rect
.type video_frame_rect, %function
video_frame_rect:
    push    {r4-r8, lr}
    mov     r4, r0
    mov     r5, r1
    mov     r6, r2
    mov     r7, r3
    mov     r0, r4                  @ borde superior
    mov     r1, r5
    mov     r2, r6
    movs    r3, #1
    bl      video_fill_rect
    mov     r0, r4                  @ borde inferior
    adds    r1, r5, r7
    subs    r1, r1, #1
    mov     r2, r6
    movs    r3, #1
    bl      video_fill_rect
    mov     r0, r4                  @ borde izquierdo
    mov     r1, r5
    movs    r2, #1
    mov     r3, r7
    bl      video_fill_rect
    adds    r0, r4, r6              @ borde derecho
    subs    r0, r0, #1
    mov     r1, r5
    movs    r2, #1
    mov     r3, r7
    bl      video_fill_rect
    pop     {r4-r8, pc}
.size video_frame_rect, .-video_frame_rect

@ =====================================================================
@ static glyph_ptr(r0 = codigo ASCII) -> r0 = direccion de sus 5 bytes
@ Convierte minusculas a mayusculas. Lo desconocido se dibuja vacio.
@ =====================================================================
.type glyph_ptr, %function
glyph_ptr:
    subs    r1, r0, #0x61           @ es minuscula (a..z)?
    cmp     r1, #25
    bhi     .Lg_upper
    subs    r0, r0, #32
.Lg_upper:
    movs    r1, #0                  @ indice 0 = espacio
    subs    r2, r0, #0x30           @ es digito (0..9)?
    cmp     r2, #9
    bhi     .Lg_letter
    adds    r1, r2, #1
    b       .Lg_idx
.Lg_letter:
    subs    r2, r0, #0x41           @ es letra (A..Z)?
    cmp     r2, #25
    bhi     .Lg_colon
    adds    r1, r2, #11
    b       .Lg_idx
.Lg_colon:
    cmp     r0, #0x3A               @ dos puntos
    bne     .Lg_equal
    movs    r1, #37
    b       .Lg_idx
.Lg_equal:
    cmp     r0, #0x3D               @ igual
    bne     .Lg_dash
    movs    r1, #38
    b       .Lg_idx
.Lg_dash:
    cmp     r0, #0x2D               @ guion
    bne     .Lg_idx
    movs    r1, #39
.Lg_idx:
    movs    r2, #5
    muls    r1, r2, r1              @ 5 bytes por caracter
    ldr     r0, =font5x7
    adds    r0, r0, r1
    bx      lr
.size glyph_ptr, .-glyph_ptr
.ltorg

@ =====================================================================
@ void video_char(int x, int y, int caracter): dibuja un caracter 5x7
@ =====================================================================
.global video_char
.type video_char, %function
video_char:
    push    {r4-r10, lr}
    mov     r4, r0                  @ x
    mov     r5, r1                  @ y
    mov     r0, r2
    bl      glyph_ptr
    mov     r6, r0                  @ puntero a las 5 columnas
    movs    r7, #0                  @ columna
.Lch_col:
    cmp     r7, #5
    bhs     .Lch_fin
    ldrb    r8, [r6, r7]            @ bits de la columna
    mov     r9, #0                  @ fila
.Lch_row:
    cmp     r9, #7
    bhs     .Lch_next
    tst     r8, #1
    beq     .Lch_skip
    add     r0, r4, r7
    add     r1, r5, r9
    bl      video_pixel
.Lch_skip:
    lsr     r8, r8, #1
    add     r9, r9, #1
    b       .Lch_row
.Lch_next:
    adds    r7, r7, #1
    b       .Lch_col
.Lch_fin:
    pop     {r4-r10, pc}
.size video_char, .-video_char

@ =====================================================================
@ void video_text(int x, int y, const char *texto): cadena terminada
@ en cero, 6 pixeles de avance por caracter.
@ =====================================================================
.global video_text
.type video_text, %function
video_text:
    push    {r4, r5, r6, lr}
    mov     r4, r0
    mov     r5, r1
    mov     r6, r2
.Lvt_loop:
    ldrb    r2, [r6], #1
    cbz     r2, .Lvt_fin
    mov     r0, r4
    mov     r1, r5
    bl      video_char
    adds    r4, r4, #6
    b       .Lvt_loop
.Lvt_fin:
    pop     {r4, r5, r6, pc}
.size video_text, .-video_text

@ =====================================================================
@ void video_number(int x, int y, unsigned int n): numero en decimal.
@ Los digitos se guardan en la pila (salen al reves) y se dibujan en
@ orden correcto.
@ =====================================================================
.global video_number
.type video_number, %function
video_number:
    push    {r4-r8, lr}
    sub     sp, sp, #16             @ espacio local para los digitos
    mov     r4, r0                  @ x
    mov     r5, r1                  @ y
    mov     r6, r2                  @ numero
    movs    r7, #0                  @ cantidad de digitos
.Lvn_div:
    movs    r3, #10
    udiv    r0, r6, r3              @ cociente
    mls     r1, r0, r3, r6          @ residuo = n - cociente * 10
    adds    r1, r1, #0x30           @ a codigo ASCII
    strb    r1, [sp, r7]
    adds    r7, r7, #1
    mov     r6, r0
    cmp     r6, #0
    bne     .Lvn_div
.Lvn_out:
    subs    r7, r7, #1
    ldrb    r2, [sp, r7]
    mov     r0, r4
    mov     r1, r5
    bl      video_char
    adds    r4, r4, #6
    cmp     r7, #0
    bne     .Lvn_out
    add     sp, sp, #16
    pop     {r4-r8, pc}
.size video_number, .-video_number
