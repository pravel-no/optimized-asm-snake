; ==============================================================================
; Ultra-Optimized 16-bit Assembly Snake Game (MS-DOS .COM)
; Author: pravel-no (https://github.com/pravel-no)
; License: MIT
;
; Key Optimizations:
; - O(1) Circular Queue for snake body (no array shifting)
; - Packed X/Y coordinates (AH=Y, AL=X) with unsigned overflow boundary checks (no DIV)
; - Fast video offset math using bit shifts: Y * 160 -> (Y * 128) + (Y * 32) (no MUL)
; - Fast LCG pseudo-random number generator
; - Fixed-point scaling for apple spawning coordinates (no DIV)
; ==============================================================================

org 100h

section .text
start:
    ; 1. Set video mode 3 (80x25 text mode, 16 colors)
    mov ax, 3
    int 10h

    ; 2. Hide cursor (move it offscreen)
    mov ah, 1
    mov ch, 2bh
    mov cl, 0bh
    int 10h

    ; 3. ES points to video memory segment (0xB800)
    mov ax, 0B800h
    mov es, ax
    cld

    ; Initialize initial snake segments in circular buffer (AH = Y, AL = X)
    mov word [snake_buf + 0], 0C28h ; Head (Y:12, X:40)
    mov word [snake_buf + 2], 0C27h ; Body (Y:12, X:39)
    mov word [snake_buf + 4], 0C26h ; Tail (Y:12, X:38)

    ; Draw initial snake segments
    mov ax, [snake_buf + 0]
    call draw_char_at_coord
    mov ax, [snake_buf + 2]
    call draw_char_at_coord
    mov ax, [snake_buf + 4]
    call draw_char_at_coord

    call spawn_apple

game_loop:
    ; Frame delay using BIOS wait function (INT 15h, AH=86h)
    ; CX:DX = microseconds (~100ms)
    mov ah, 86h
    mov cx, 1
    mov dx, 86A0h
    int 15h

    ; Non-blocking keyboard check
    mov ah, 1
    int 16h
    jz .no_key

    ; Read keystroke
    mov ah, 0
    int 16h

    ; Process WASD keys
    cmp al, 'w'
    je .set_up
    cmp al, 's'
    je .set_down
    cmp al, 'a'
    je .set_left
    cmp al, 'd'
    je .set_right
    cmp al, 27          ; ESC key to exit
    je exit_game
    jmp .no_key

.set_up:
    cmp byte [dir_y], 1  ; Prevent instant self-reversal
    je .no_key
    mov byte [dir_y], -1
    mov byte [dir_x], 0
    jmp .no_key
.set_down:
    cmp byte [dir_y], -1
    je .no_key
    mov byte [dir_y], 1
    mov byte [dir_x], 0
    jmp .no_key
.set_left:
    cmp byte [dir_x], 1
    je .no_key
    mov byte [dir_x], -1
    mov byte [dir_y], 0
    jmp .no_key
.set_right:
    cmp byte [dir_x], -1
    je .no_key
    mov byte [dir_x], 1
    mov byte [dir_y], 0

.no_key:
    ; Get current head coordinates from the circular buffer
    mov si, [head_idx]
    mov ax, [snake_buf + si]

    ; Calculate new head coordinates (using byte addition to prevent carry bleed)
    add al, [dir_x]
    add ah, [dir_y]

    ; [OPTIMIZATION] Fast boundary check via unsigned comparison (handles negative coords)
    cmp al, 80
    jae game_over
    cmp ah, 25
    jae game_over

    ; Screen collision check
    call get_screen_offset
    mov dx, [es:di]
    cmp dl, 'o'            ; Collided with self?
    je game_over

    cmp dl, '*'            ; Eaten an apple?
    je .eat_apple

    ; --- Normal Move ---
    ; [OPTIMIZATION] Erase tail from screen using tail_idx without shifting arrays
    mov bx, [tail_idx]
    mov dx, [snake_buf + bx]
    
    push ax
    mov ax, dx
    call get_screen_offset
    mov word [es:di], 0020h ; Write black space
    pop ax

    ; Advance tail pointer (buffer size is 512 words, wrap at 1024 bytes)
    add bx, 2
    and bx, 1023
    mov [tail_idx], bx
    jmp .move_head

.eat_apple:
    ; If apple is eaten, we grow (skip tail pointer advancement)
    call spawn_apple

.move_head:
    ; Write new head to circular buffer
    mov bx, [head_idx]
    add bx, 2
    and bx, 1023
    mov [head_idx], bx
    mov [snake_buf + bx], ax

    ; Render head on screen
    call draw_char_at_coord
    jmp game_loop

game_over:
    ; Display Game Over message
    mov di, 1990
    mov si, msg_game_over
    mov cx, 10
.print_msg:
    lodsb
    mov ah, 0Ch         ; Light red text
    stosw
    loop .print_msg

    ; Wait for key press
    mov ah, 0
    int 16h

exit_game:
    ; Restore cursor and exit to DOS
    mov ah, 1
    mov ch, 06h
    mov cl, 07h
    int 10h
    mov ax, 4C00h
    int 21h

; --- Helper Functions ---

; [OPTIMIZATION] Fast conversion of coordinates (AH=Y, AL=X) into VRAM offset (DI)
; Uses shift-add math: Y * 160 -> (Y * 128) + (Y * 32)
get_screen_offset:
    push ax
    push bx
    push cx
    push dx

    xor bh, bh
    mov bl, al              ; BX = X
    
    mov cl, ah
    xor ch, ch              ; CX = Y

    mov dx, cx
    shl cx, 7
    shl dx, 5
    add cx, dx              ; CX = Y * 160

    shl bx, 1               ; BX = X * 2 (2 bytes per character cell)
    add cx, bx              ; CX = Total offset

    mov di, cx              ; Return in DI
    
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Draw snake character at coordinates in AX
draw_char_at_coord:
    call get_screen_offset
    mov word [es:di], 0A6Fh ; Green 'o'
    ret

; Spawn an apple randomly
spawn_apple:
.retry:
    ; LCG Pseudo-Random Number Generator
    mov ax, [rand_seed]
    imul ax, 25173
    add ax, 13849
    mov [rand_seed], ax

    ; [OPTIMIZATION] Fixed-point multiplication mapping to 0..1999 (No DIV)
    mov bx, 2000
    mul bx                  ; DX = (AX * 2000) >> 16
    
    shl dx, 1               ; Convert index to even byte offset
    mov di, dx

    ; Ensure it doesn't land on the snake
    mov ax, [es:di]
    cmp al, 'o'
    je .retry

    mov word [es:di], 0C2Ah ; Red '*'
    ret

section .data
    dir_x db 1              ; Move right initially
    dir_y db 0

    head_idx dw 0           ; Head pointer
    tail_idx dw 4           ; Tail pointer

    rand_seed dw 0ECECh     ; PRNG Seed
    msg_game_over db "GAME OVER!"

section .bss
    ; Circular buffer for snake body coordinates (512 words / 1024 bytes)
    snake_buf resw 512
