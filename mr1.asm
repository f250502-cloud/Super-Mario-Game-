; ============================================================
;  SUPER MARIO ENGINE  -  EL2003 COAL Semester Project
;  Single File Division:
;    - PART 1 (Modules 1-8)  : [M.Bilal] ([25F-0502])
;    - PART 2 (Modules 9-15) : [Hassan Anjum] ([25F-0711])
;  Build : nasm -f bin mr2.asm -o mr2.com
;  Run   : DOSBox  ->  mr2.com
; ============================================================
org 100h
cpu 386                         ; enables 16-bit near conditional jumps

; ================= CONSTANTS (Appendix A) ===================
DISP_WIDTH          equ 320
DISP_HEIGHT         equ 200
VGA_SEGMENT         equ 0A000h
BACKBUF_PARAS       equ 0FA0h               ; 64000 bytes = 4000 paragraphs

CELL_PX             equ 16
GRID_COLS           equ 60
GRID_ROWS           equ 12
GRID_BYTES          equ GRID_COLS*GRID_ROWS ; 720 bytes
VIEW_COLS           equ 20
CAM_LIMIT_X         equ GRID_COLS*CELL_PX-DISP_WIDTH    ; 640
CAM_DEADZONE_X      equ 160
STAGE_END_X         equ GRID_COLS*CELL_PX-CELL_PX       ; 944

CELL_AIR            equ 0
CELL_FLOOR          equ 1
CELL_MASONRY        equ 2
CELL_PRIZE_COIN     equ 3
CELL_PRIZE_MUSH     equ 4
CELL_USED           equ 5
CELL_PICKUP_COIN    equ 11
CELL_GOAL_POLE      equ 12

PAL_BACKDROP        equ 9
PAL_BAR_BG          equ 0
PAL_HEADER_TXT      equ 14
PAL_NUM_TXT         equ 15
PAL_VITAL_ON        equ 12
PAL_VITAL_OFF       equ 8

GFX_FLIP_H          equ 1                   ; flags bit 0: flip horizontally
GFX_FLICKER         equ 2                   ; flags bit 1: draw half the pixels

; ---- scan codes (Appendix A.3) + debug keys ----
KEY_ESC_CODE        equ 01h
KEY_RET_CODE        equ 1Ch
KEY_PAUSE_CODE      equ 19h
KEY_SPRINT_CODE     equ 2Ah
KEY_LEAP_CODE       equ 39h
KEY_L_CODE          equ 4Bh
KEY_R_CODE          equ 4Dh
KEY_U_CODE          equ 48h
KEY_D_CODE          equ 50h
KEY_DBG_SIZE        equ 1Fh                 ; debug: Small/Super
KEY_DBG_RESET       equ 13h                 ; debug: reset level
KEY_DBG_COINS       equ 2Eh                 ; debug: coins = 99
KEY_DBG_TIME        equ 14h                 ; debug: time = 5 s

; ---- timer ----
IRQ0_RELOAD         equ 19886               ; 1193182 / 19886 = ~60 Hz
STEP_TICKS          equ 2                   ; 30 frames per second
HZ_RATE             equ 60
STAGE_SECONDS       equ 300

; ---- physics (8.8 fixed point, Appendix A.5) ----
RUN_ACCEL           equ 0020h
GROUND_DRAG         equ 0010h
CAP_WALK_VX         equ 0180h
CAP_SPRINT_VX       equ 0280h
FALL_ACCEL          equ 0040h
LEAP_IMPULSE        equ 0FA80h
LEAP_RELEASE_VY     equ 0FE00h
TERMINAL_VY         equ 0400h

BOX_PAD_L           equ 2                   ; hitbox left offset from plr_x
BOX_PAD_R           equ 13                  ; hitbox right offset (12 px wide)
BOX_MID_X           equ 8

; ---- enemies ----
FOE_SLOTS           equ 8
FOE_STRIDE          equ 16
FOE_KIND            equ 0
FOE_MODE            equ 1
FOE_POS_X           equ 2
FOE_SUB_X           equ 4
FOE_HEADING         equ 5
FOE_POS_Y           equ 6
FOE_SUB_Y           equ 8
FOE_CNT             equ 9
FOE_VEL_Y           equ 10
FOE_SAFE_T          equ 12
KIND_EMPTY          equ 0
KIND_WALKER         equ 1
KIND_TURTLE         equ 2
MODE_DORMANT        equ 0
MODE_PATROL         equ 1
MODE_SQUASHED       equ 2
MODE_CARAPACE       equ 3
MODE_SPINNING       equ 4
WALKER_VX           equ 0080h
TURTLE_VX           equ 00C0h
SPIN_VX             equ 0300h
BOUNCE_LOW_VY       equ 0FD00h
BOUNCE_HIGH_VY      equ 0FC00h
SQUASH_TICKS        equ 30
KICK_SAFE_TICKS     equ 8
MERCY_TICKS         equ 60

; ---- mushrooms ----
ITEM_SLOTS          equ 2
ITEM_STRIDE         equ 10
ITEM_ALIVE          equ 0
ITEM_HEADING        equ 1
ITEM_POS_X          equ 2
ITEM_SUB_X          equ 4
ITEM_SUB_Y          equ 5
ITEM_POS_Y          equ 6
ITEM_VEL_Y          equ 8
ITEM_VX             equ 0100h

; ---- game states ----
PHASE_MENU          equ 0
PHASE_ACTIVE        equ 1
PHASE_HOLD          equ 2
PHASE_FALLING       equ 3
PHASE_RETRY         equ 4
PHASE_CLEAR_ANIM    equ 5
PHASE_SUMMARY       equ 6
PHASE_DEFEAT        equ 7
PHASE_QUIT          equ 8
FALL_ANIM_TICKS     equ 45
RETRY_BANNER_TICKS  equ 60

; ---- death / win sequences ----
DEFEAT_BOUNCE_VY    equ 0FB1Ah              ; -4.9 px/frame: rises about 48 px
POLE_LOCK_X         equ 884
POLE_BOTTOM_Y       equ 144
FLOOR_BASE_Y        equ 160
POLE_DROP_VY        equ 3
VICTORY_STEP_VX     equ 2
VICTORY_MARCH_TICKS equ 30
KEEP_DOOR_X         equ 928


; ############################################################
;  PART 1 : CORE ENGINE, GRAPHICS, MAP & HARDWARE INTERRUPTS
;  Done by: [Partner 1 Name]
;  Covers : Main Loop, Double Buffering, Tile/Sprite Drawing,
;           INT 09h Keyboard Handler & INT 08h Timer Handler
; ############################################################

; ============================================================
; PROGRAM ENTRY  (Module 1)
; ============================================================
start:
    mov  ax, 0013h              ; VGA mode 13h (320x200, 256 colours)
    int  10h
    call InitMap
    call AllocFrameBuffer
    jc   near .nomem            ; jump if memory allocation failed

    mov  ax, [backbuf_seg]
    mov  [render_target_seg], ax ; all drawing goes to the off-screen buffer

    push word gfx_player        ; convert every sprite ONCE from ASCII hex to 0..15
    call ConvertSprite
    push word gfx_walker
    call ConvertSprite
    push word gfx_walker_flat
    call ConvertSprite
    push word gfx_turtle
    call ConvertSprite
    push word gfx_carapace
    call ConvertSprite
    push word gfx_powerup
    call ConvertSprite

    call InstallKeyboard
    call InstallTimer
    call NewGame
    mov  byte [curr_phase], PHASE_MENU

.frame:
    call WaitTick               ; frame step 1: wait for next 30 FPS tick
    xor  bx, bx
    mov  bl, [curr_phase]
    cmp  bl, PHASE_QUIT
    jae  near .exit
    shl  bx, 1                  ; multiply phase index by 2 (word table)
    call word [phase_handlers + bx]
    call Present                ; frame step 10: copy backbuffer to screen
    call SaveKeys               ; remember keys for edge detection
    jmp  .frame

.exit:
    call CleanExit              ; never returns
.nomem:
    mov  ax, 0003h              ; back to 80x25 text mode
    int  10h
    mov  dx, err_alloc_str
    mov  ah, 09h
    int  21h
    mov  ax, 4C01h
    int  21h

; ============================================================
; MODULE 2 : FillRect
; ============================================================
FillRect:
    push bp
    mov  bp, sp
    push ax
    push cx
    push dx
    push di
    push es
    pushf

    cld
    mov  es, [render_target_seg]
    mov  di, [bp+10]            ; y
    mov  dx, di
    shl  di, 8                  ; y * 256
    shl  dx, 6                  ; y * 64
    add  di, dx                 ; di = y * 320
    add  di, [bp+12]            ; di = y * 320 + x
    mov  al, [bp+4]             ; colour
    mov  dx, [bp+6]             ; rows left
    test dx, dx
    jz   near .done
.row:
    mov  cx, [bp+8]             ; width
    push di
    rep  stosb                  ; fill one horizontal row
    pop  di
    add  di, DISP_WIDTH         ; move down to next row
    dec  dx
    jnz  near .row
.done:
    popf
    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  ax
    pop  bp
    ret  10

; ============================================================
; MODULE 3 : Level Map
; ============================================================
InitMap:
    push bx
    push cx
    mov  bx, base_grid_data
    mov  cx, GRID_BYTES
.conv:
    sub  byte [bx], '0'
    inc  bx
    loop .conv
    call ResetMap
    pop  cx
    pop  bx
    ret

ResetMap:
    pushf
    push cx
    push si
    push di
    push es
    push ds
    pop  es
    cld
    mov  si, base_grid_data
    mov  di, live_grid_data
    mov  cx, GRID_BYTES
    rep  movsb
    pop  es
    pop  di
    pop  si
    pop  cx
    popf
    ret

GetTile:
    push bp
    mov  bp, sp
    push bx
    push cx
    push si

    mov  cx, [bp+4]             ; py
    test cx, cx
    js   near .sky              ; above map -> sky
    shr  cx, 4                  ; row = py / 16
    cmp  cx, GRID_ROWS
    jae  near .sky              ; below map -> sky (pits are open)

    mov  bx, [bp+6]             ; px
    test bx, bx
    js   near .solid            ; left of map -> solid wall
    shr  bx, 4                  ; col = px / 16
    cmp  bx, GRID_COLS
    jae  near .solid            ; right of map -> solid wall

    mov  ax, cx
    shl  ax, 6                  ; row * 64
    shl  cx, 2                  ; row * 4
    sub  ax, cx                 ; row * 60
    add  ax, bx                 ; + col
    mov  si, ax
    mov  bx, live_grid_data
    xor  ax, ax
    mov  al, [bx+si]
    jmp  .done
.sky:
    xor  ax, ax
    jmp  .done
.solid:
    mov  ax, CELL_FLOOR
.done:
    pop  si
    pop  cx
    pop  bx
    pop  bp
    ret  4

DrawTile:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx

    mov  ax, [bp+8]             ; x
    mov  cx, CELL_PX            ; visible width = 16
    cmp  ax, 0
    jge  near .rightclip
    add  cx, ax                 ; partially off left edge: width = 16 + x
    jle  near .done             ; completely off left edge
    xor  ax, ax                 ; clamp x to 0
    jmp  .draw
.rightclip:
    mov  dx, DISP_WIDTH
    sub  dx, ax                 ; space left before right edge
    jle  near .done             ; completely off right edge
    cmp  cx, dx
    jbe  near .draw
    mov  cx, dx                 ; clamp width to remaining screen space
.draw:
    mov  bx, [bp+4]
    mov  dl, [bx+cell_pal_lut]  ; look up VGA colour for tile code
    xor  dh, dh
    push ax                     ; x
    push word [bp+6]            ; y
    push cx                     ; w
    push word CELL_PX           ; h
    push dx                     ; colour
    call FillRect
.done:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  6

DrawMap:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    xor  si, si                 ; SI = row (0..11)
.rowloop:
    xor  di, di                 ; DI = screen tile column (0..20)
.colloop:
    mov  bx, [bp+4]
    shr  bx, 4                  ; first visible map column = camera_x / 16
    add  bx, di                 ; BX = current map column
    cmp  bx, GRID_COLS
    jae  near .nextcol

    mov  ax, si
    mov  dx, ax
    shl  ax, 6                  ; row * 64
    shl  dx, 2                  ; row * 4
    sub  ax, dx                 ; row * 60
    add  ax, bx
    mov  bx, ax
    mov  al, [bx+live_grid_data]
    xor  ah, ah                 ; AX = tile code
    test ax, ax
    jz   near .nextcol          ; skip sky (already cleared)

    mov  cx, di
    shl  cx, 4                  ; di * 16
    mov  dx, [bp+4]
    and  dx, 15                 ; camera_x mod 16
    sub  cx, dx                 ; screen x
    mov  dx, si
    shl  dx, 4                  ; screen y = row * 16
    push cx
    push dx
    push ax
    call DrawTile
.nextcol:
    inc  di
    cmp  di, VIEW_COLS+1
    jb   near .colloop
    inc  si
    cmp  si, GRID_ROWS
    jb   near .rowloop

    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  2

; ============================================================
; MODULE 4 : Sprites
; ============================================================
ConvertSprite:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    mov  bx, [bp+4]
    mov  cx, 256
.next:
    mov  al, [bx]
    sub  al, '0'
    cmp  al, 9
    jbe  near .store
    sub  al, 7                  ; 'A'..'F' -> 10..15
.store:
    mov  [bx], al
    inc  bx
    loop .next
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  2

DrawSprite:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov  es, [render_target_seg]
    mov  si, [bp+6]             ; SI = current sprite row pointer
    xor  dx, dx                 ; DX = row 0..15
.row:
    mov  ax, [bp+8]
    add  ax, dx                 ; AX = screen y
    cmp  ax, 0
    jl   near .nextrow
    cmp  ax, DISP_HEIGHT
    jge  near .nextrow

    mov  di, ax
    shl  di, 8                  ; y * 256
    shl  ax, 6                  ; y * 64
    add  di, ax                 ; DI = y * 320
    xor  cx, cx                 ; CX = col 0..15
.col:
    mov  bx, cx
    test word [bp+4], GFX_FLIP_H
    jz   near .read
    mov  bx, 15
    sub  bx, cx                 ; mirror horizontally
.read:
    mov  al, [si+bx]
    test al, al
    jz   near .nextcol          ; 0 = transparent pixel

    mov  bx, [bp+10]
    add  bx, cx                 ; BX = screen x
    cmp  bx, 0
    jl   near .nextcol
    cmp  bx, DISP_WIDTH
    jge  near .nextcol

    test word [bp+4], GFX_FLICKER
    jz   near .plot
    push ax
    mov  ax, bx
    add  ax, [bp+8]
    add  ax, dx
    test al, 1                  ; checkerboard flicker when invulnerable
    pop  ax
    jnz  near .nextcol
.plot:
    mov  [es:bx+di], al
.nextcol:
    inc  cx
    cmp  cx, 16
    jb   near .col
.nextrow:
    add  si, 16
    inc  dx
    cmp  dx, 16
    jb   near .row

    pop  es
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  8

; ============================================================
; MODULE 5 : Frame Buffer (Double Buffering)
; ============================================================
AllocFrameBuffer:
    push bx
    push es
    mov  ax, cs
    mov  es, ax                 ; ES = our program segment
    mov  bx, 1000h              ; shrink program memory to 64 KB
    mov  ah, 4Ah
    int  21h
    jc   near .fail

    mov  bx, BACKBUF_PARAS      ; allocate 64000 bytes (4000 paragraphs)
    mov  ah, 48h
    int  21h
    jc   near .fail

    mov  [backbuf_seg], ax
    clc
.fail:
    pop  es
    pop  bx
    ret

FreeFrameBuffer:
    push ax
    push es
    mov  ax, [backbuf_seg]
    test ax, ax
    jz   near .skip
    mov  es, ax
    mov  ah, 49h
    int  21h
.skip:
    pop  es
    pop  ax
    ret

ClearFrame:
    pushf
    push ax
    push cx
    push di
    push es
    mov  es, [backbuf_seg]
    xor  di, di
    mov  al, PAL_BACKDROP       ; put sky colour in both bytes of AX
    mov  ah, PAL_BACKDROP
    mov  cx, 32000              ; 32000 words = 64000 bytes
    cld
    rep  stosw
    pop  es
    pop  di
    pop  cx
    pop  ax
    popf
    ret

Present:
    pushf
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov  ax, VGA_SEGMENT
    mov  es, ax
    mov  ds, [backbuf_seg]
    xor  si, si
    xor  di, di
    mov  cx, 32000              ; copy 64000 bytes to VGA memory
    cld
    rep  movsw
    pop  es
    pop  ds
    pop  di
    pop  si
    pop  cx
    pop  ax
    popf
    ret

; ============================================================
; MODULE 7 : Keyboard Interrupt (INT 09h)
; ============================================================
InstallKeyboard:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    push ds
    pop  es
    cld
    mov  di, key_held_buf
    mov  cx, 128
    xor  al, al
    rep  stosb                  ; clear all key states

    mov  ax, 3509h              ; get original INT 09h handler
    int  21h
    mov  [prev_irq1_off], bx
    mov  [prev_irq1_seg], es

    mov  dx, KeyboardISR        ; install our keyboard handler
    mov  ax, 2509h
    int  21h

    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

RestoreKeyboard:
    push ax
    push dx
    push ds
    mov  dx, [prev_irq1_off]
    mov  ds, [prev_irq1_seg]
    mov  ax, 2509h
    int  21h
    pop  ds
    pop  dx
    pop  ax
    ret

KeyboardISR:
    push ax
    push bx

    in   al, 60h                ; read scan code from keyboard port
    cmp  al, 0E0h
    je   near .eoi              ; ignore extended prefix byte

    mov  ah, al                 ; save original byte (bit 7 = 1 means key released)
    xor  bh, bh
    mov  bl, al
    and  bl, 7Fh                ; mask out release bit to get index 0..127
    mov  al, 1                  ; 1 = pressed
    test ah, 80h
    jz   near .store
    xor  al, al                 ; 0 = released
.store:
    mov  [cs:key_held_buf + bx], al

.eoi:
    mov  al, 20h
    out  20h, al                ; acknowledge interrupt to PIC

    pop  bx
    pop  ax
    iret

IsKeyDown:
    push bp
    mov  bp, sp
    push bx
    mov  bx, [bp+4]
    and  bx, 7Fh
    mov  al, [key_held_buf + bx]
    pop  bx
    pop  bp
    ret  2

KeyPressed:
    push bp
    mov  bp, sp
    push bx
    mov  bx, [bp+4]
    and  bx, 7Fh
    xor  al, al
    cmp  byte [key_held_buf + bx], 0
    je   near .done             ; not held now
    cmp  byte [key_last_buf + bx], 0
    jne  near .done             ; was already held last frame
    mov  al, 1
.done:
    pop  bx
    pop  bp
    ret  2

SaveKeys:
    pushf
    push cx
    push si
    push di
    push es
    push ds
    pop  es
    cld
    mov  si, key_held_buf
    mov  di, key_last_buf
    mov  cx, 128
    rep  movsb
    pop  es
    pop  di
    pop  si
    pop  cx
    popf
    ret

; ============================================================
; MODULE 8 : Timer Interrupt (INT 08h) and Game Clock
; ============================================================
InstallTimer:
    push ax
    push bx
    push dx
    push es

    mov  ax, 3508h              ; get original INT 08h handler
    int  21h
    mov  [prev_irq0_off], bx
    mov  [prev_irq0_seg], es

    cli
    mov  dx, TimerISR
    mov  ax, 2508h
    int  21h

    mov  al, 36h                ; set PIT channel 0 to ~60 Hz
    out  43h, al
    mov  al, IRQ0_RELOAD & 0FFh
    out  40h, al
    mov  al, IRQ0_RELOAD >> 8
    out  40h, al
    mov  ax, [sys_ticks]
    mov  [prev_frame_tick], ax
    sti

    pop  es
    pop  dx
    pop  bx
    pop  ax
    ret

RestoreTimer:
    push ax
    push dx
    push ds
    cli
    mov  al, 36h                ; restore default 18.2 Hz PIT rate
    out  43h, al
    xor  al, al
    out  40h, al
    out  40h, al
    mov  dx, [prev_irq0_off]
    mov  ds, [prev_irq0_seg]
    mov  ax, 2508h
    int  21h
    sti
    pop  ds
    pop  dx
    pop  ax
    ret

TimerISR:
    push ax
    inc  word [cs:sys_ticks]
    mov  ax, IRQ0_RELOAD
    add  [cs:pit_chain_acc], ax
    jc   near .chain            ; call original BIOS timer every ~18.2 Hz
    mov  al, 20h
    out  20h, al
    pop  ax
    iret
.chain:
    pop  ax
    jmp  far [cs:prev_irq0_off]

WaitTick:
    push ax
.wait:
    hlt                         ; sleep CPU until next timer interrupt
    mov  ax, [sys_ticks]
    sub  ax, [prev_frame_tick]
    cmp  ax, STEP_TICKS
    jb   near .wait
    mov  ax, [sys_ticks]
    mov  [prev_frame_tick], ax
    pop  ax
    ret

UpdateClock:
    cmp  byte [clock_halted], 0
    jne  near .done
    add  word [sec_tick_acc], STEP_TICKS
    cmp  word [sec_tick_acc], HZ_RATE
    jb   near .done
    sub  word [sec_tick_acc], HZ_RATE
    cmp  word [stage_clock], 0
    je   near .done
    dec  word [stage_clock]
.done:
    ret
