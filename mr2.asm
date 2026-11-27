; ============================================================
;  SUPER MARIO ENGINE  -  EL2003 COAL Semester Project
;  Single file: modules 1 to 15
;  Build : nasm -f bin mario.asm -o MARIO.COM
;  Run   : DOSBox  ->  MARIO.COM
; ============================================================
org 100h

; ================= CONSTANTS (Appendix A) ===================
DISP_WIDTH        equ 320
DISP_HEIGHT        equ 200
VGA_SEGMENT       equ 0A000h
BACKBUF_PARAS        equ 0FA0h               ; 64000 bytes = 4000 paragraphs

CELL_PX       equ 16
GRID_COLS        equ 60
GRID_ROWS        equ 12
GRID_BYTES        equ GRID_COLS*GRID_ROWS   ; 720 bytes
VIEW_COLS    equ 20
CAM_LIMIT_X         equ GRID_COLS*CELL_PX-DISP_WIDTH        ; 640
CAM_DEADZONE_X      equ 160
STAGE_END_X     equ GRID_COLS*CELL_PX-CELL_PX       ; 944

CELL_AIR        equ 0
CELL_FLOOR     equ 1
CELL_MASONRY      equ 2
CELL_PRIZE_COIN      equ 3
CELL_PRIZE_MUSH      equ 4
CELL_USED      equ 5
CELL_PICKUP_COIN       equ 11
CELL_GOAL_POLE       equ 12

PAL_BACKDROP         equ 9
PAL_BAR_BG      equ 0
PAL_HEADER_TXT       equ 14
PAL_NUM_TXT       equ 15
PAL_VITAL_ON       equ 12
PAL_VITAL_OFF       equ 8

GFX_FLIP_H      equ 1                   ; flags bit 0: flip horizontally
GFX_FLICKER       equ 2                   ; flags bit 1: draw half the pixels

; ---- scan codes (Appendix A.3) + debug keys ----
KEY_ESC_CODE          equ 01h
KEY_RET_CODE        equ 1Ch
KEY_PAUSE_CODE            equ 19h
KEY_SPRINT_CODE       equ 2Ah
KEY_LEAP_CODE        equ 39h
KEY_L_CODE         equ 4Bh
KEY_R_CODE        equ 4Dh
KEY_U_CODE           equ 48h
KEY_D_CODE         equ 50h
KEY_DBG_SIZE            equ 1Fh                 ; debug: Small/Super
KEY_DBG_RESET            equ 13h                 ; debug: reset level
KEY_DBG_COINS            equ 2Eh                 ; debug: coins = 99
KEY_DBG_TIME            equ 14h                 ; debug: time = 5 s

; ---- timer ----
IRQ0_RELOAD     equ 19886               ; 1193182 / 19886 = ~60 Hz
STEP_TICKS equ 2                   ; 30 frames per second
HZ_RATE equ 60
STAGE_SECONDS      equ 300

; ---- physics (8.8 fixed point, Appendix A.5) ----
RUN_ACCEL           equ 0020h
GROUND_DRAG        equ 0010h
CAP_WALK_VX        equ 0180h
CAP_SPRINT_VX         equ 0280h
FALL_ACCEL         equ 0040h
LEAP_IMPULSE          equ 0FA80h
LEAP_RELEASE_VY        equ 0FE00h
TERMINAL_VY        equ 0400h

BOX_PAD_L         equ 2                   ; hitbox left offset from hero_x
BOX_PAD_R        equ 13                  ; hitbox right offset (12 px wide)
BOX_MID_X       equ 8

; ---- enemies ----
FOE_SLOTS     equ 8
FOE_STRIDE      equ 16
FOE_KIND          equ 0
FOE_MODE         equ 1
FOE_POS_X             equ 2
FOE_SUB_X            equ 4
FOE_HEADING           equ 5
FOE_POS_Y             equ 6
FOE_SUB_Y            equ 8
FOE_CNT         equ 9
FOE_VEL_Y            equ 10
FOE_SAFE_T         equ 12
KIND_EMPTY          equ 0
KIND_WALKER        equ 1
KIND_TURTLE         equ 2
MODE_DORMANT         equ 0
MODE_PATROL         equ 1
MODE_SQUASHED         equ 2
MODE_CARAPACE        equ 3
MODE_SPINNING        equ 4
WALKER_VX    equ 0080h
TURTLE_VX     equ 00C0h
SPIN_VX     equ 0300h
BOUNCE_LOW_VY    equ 0FD00h
BOUNCE_HIGH_VY equ 0FC00h
SQUASH_TICKS     equ 30
KICK_SAFE_TICKS      equ 8
MERCY_TICKS   equ 60

; ---- mushrooms ----
ITEM_SLOTS        equ 2
ITEM_STRIDE       equ 10
ITEM_ALIVE           equ 0
ITEM_HEADING           equ 1
ITEM_POS_X             equ 2
ITEM_SUB_X            equ 4
ITEM_SUB_Y            equ 5
ITEM_POS_Y             equ 6
ITEM_VEL_Y            equ 8
ITEM_VX      equ 0100h

; ---- game states ----
PHASE_MENU        equ 0
PHASE_ACTIVE      equ 1
PHASE_HOLD       equ 2
PHASE_FALLING        equ 3
PHASE_RETRY     equ 4
PHASE_CLEAR_ANIM          equ 5
PHASE_SUMMARY     equ 6
PHASE_DEFEAT     equ 7
PHASE_QUIT         equ 8
FALL_ANIM_TICKS    equ 45
RETRY_BANNER_TICKS equ 60

; ---- death / win sequences ----
DEFEAT_BOUNCE_VY       equ 0FB1Ah              ; -4.9 px/frame: rises about 48 px
POLE_LOCK_X     equ 884
POLE_BOTTOM_Y     equ 144
FLOOR_BASE_Y   equ 160
POLE_DROP_VY     equ 3
VICTORY_STEP_VX      equ 2
VICTORY_MARCH_TICKS     equ 30
KEEP_DOOR_X        equ 928

; ============================================================
; PROGRAM ENTRY  (Modules 1, 14, 15)
; ============================================================
start:
    mov  ax, 0013h              ; VGA mode 13h
    int  10h
    call InitMap
    call AllocFrameBuffer
    jnc $+5
    jmp near .nomem
    mov  ax, [backbuf_seg]
    mov  [render_target_seg], ax         ; all drawing goes to the frame buffer

    push word gfx_player      ; convert every sprite ONCE
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
    push word gfx_coin
    call ConvertSprite

    call InstallKeyboard
    call InstallTimer
    call NewGame
    mov  byte [curr_phase], PHASE_MENU

.frame:
    call WaitTick               ; frame step 1
    xor  bx, bx
    mov  bl, [curr_phase]
    cmp  bl, PHASE_QUIT
    jb $+5
    jmp near .exit
    shl  bx, 1
    call word [phase_handlers + bx]    ; indexed jump table
    call Present                ; frame step 10
    call SaveKeys               ; remember keys for KeyPressed
    jmp  .frame

.exit:
    call CleanExit              ; never returns
.nomem:
    mov  ax, 0003h
    int  10h
    mov  dx, err_alloc_str
    mov  ah, 09h
    int  21h
    mov  ax, 4C01h
    int  21h

; ============================================================
; MODULE 2 : FillRect
; ============================================================
; ------------------------------------------------------------
; FillRect(x, y, w, h, colour)  -- parameters on the stack
; Purpose: filled rectangle into the segment in draw_seg
; Inputs : [bp+12]=x [bp+10]=y [bp+8]=w [bp+6]=h [bp+4]=colour
; Output : rectangle drawn (no clipping: caller stays on screen)
; Changes: none (AX,CX,DX,DI,ES,flags preserved); callee pops 10
; ------------------------------------------------------------
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
    shl  di, 8                  ; y*256
    shl  dx, 6                  ; y*64
    add  di, dx                 ; y*320
    add  di, [bp+12]            ; + x
    mov  al, [bp+4]             ; colour
    mov  dx, [bp+6]             ; rows left
    test dx, dx
    jnz $+5
    jmp near .done
.row:
    mov  cx, [bp+8]             ; width
    push di
    rep  stosb                  ; fill one row
    pop  di
    add  di, DISP_WIDTH           ; next row
    dec  dx
    jz $+5
    jmp near .row
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
; MODULE 3 : level map
; ============================================================
; ------------------------------------------------------------
; InitMap
; Purpose: orig_map ASCII -> tile codes (subtract '0'), then copy
;          original -> working map. Call ONCE at startup.
; Inputs : none     Outputs: orig_map, work_map ready
; Changes: none (BX, CX preserved)
; ------------------------------------------------------------
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

; ------------------------------------------------------------
; ResetMap
; Purpose: work_map = orig_map with ONE REP MOVSB
; Inputs : none     Outputs: work_map restored
; Changes: none (flags, CX, SI, DI, ES preserved)
; ------------------------------------------------------------
ResetMap:
    pushf
    push cx
    push si
    push di
    push es
    push ds
    pop  es                     ; ES = DS (.COM: one segment)
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

; ------------------------------------------------------------
; GetTile(px, py)
; Purpose: world pixel position -> tile code from the WORKING map
; Inputs : [bp+6]=px  [bp+4]=py (signed)
; Output : AX = tile code. py above/below map -> sky (pits are not
;          solid); px outside the level -> ground (solid wall)
; Changes: AX only; callee pops 4
; ------------------------------------------------------------
GetTile:
    push bp
    mov  bp, sp
    push bx
    push cx
    push si

    mov  cx, [bp+4]             ; py
    test cx, cx
    jns $+5
    jmp near .sky
    shr  cx, 4                  ; row
    cmp  cx, GRID_ROWS
    jb $+5
    jmp near .sky
    mov  bx, [bp+6]             ; px
    test bx, bx
    jns $+5
    jmp near .solid
    shr  bx, 4                  ; col
    cmp  bx, GRID_COLS
    jb $+5
    jmp near .solid

    mov  ax, cx
    shl  ax, 6                  ; row*64
    shl  cx, 2                  ; row*4
    sub  ax, cx                 ; row*60
    add  ax, bx                 ; + col
    mov  si, ax
    mov  bx, live_grid_data
    xor  ax, ax
    mov  al, [bx+si]            ; based-indexed addressing
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

; ------------------------------------------------------------
; DrawTile(x, y, code)
; Purpose: 16x16 tile (flat colour) at SCREEN position, clipped
;          at the left and right screen edges
; Inputs : [bp+8]=x (signed)  [bp+6]=y  [bp+4]=tile code
; Output : tile drawn
; Changes: none; callee pops 6
; ------------------------------------------------------------
DrawTile:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx

    cmp  word [bp+4], CELL_PICKUP_COIN
    je $+5
    jmp near .solid_tile
    push word [bp+8]            ; x (signed, clipped inside DrawSprite)
    push word [bp+6]            ; y
    push word gfx_coin
    push word 0
    call DrawSprite
    jmp  .done

.solid_tile:
    mov  ax, [bp+8]             ; x
    mov  cx, CELL_PX          ; visible width
    cmp  ax, 0
    jl $+5
    jmp near .rightclip
    add  cx, ax                 ; width = 16 + x
    jg $+5
    jmp near .done
    xor  ax, ax
    jmp  .draw
.rightclip:
    mov  dx, DISP_WIDTH
    sub  dx, ax
    jg $+5
    jmp near .done
    cmp  cx, dx
    ja $+5
    jmp near .draw
    mov  cx, dx
.draw:
    mov  bx, [bp+4]
    mov  dl, [bx+cell_pal_lut]   ; indexed colour lookup
    xor  dh, dh
    push ax                     ; x
    push word [bp+6]            ; y
    push cx                     ; w
    push word CELL_PX         ; h
    push dx                     ; colour
    call FillRect
.done:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  6

; ------------------------------------------------------------
; DrawMap(camera_x)
; Purpose: draw the visible 21 columns: first column camera_x/16,
;          pixel offset camera_x mod 16. Sky tiles are skipped
;          because ClearFrame already filled the sky colour.
; Inputs : [bp+4]=camera_x     Outputs: map in the frame buffer
; Changes: none; callee pops 2
; ------------------------------------------------------------
DrawMap:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    xor  si, si                 ; SI = row
.rowloop:
    xor  di, di                 ; DI = visible column number
.colloop:
    mov  bx, [bp+4]
    shr  bx, 4
    add  bx, di                 ; BX = map column
    cmp  bx, GRID_COLS
    jb $+5
    jmp near .nextcol
    mov  ax, si
    mov  dx, ax
    shl  ax, 6
    shl  dx, 2
    sub  ax, dx                 ; row*60
    add  ax, bx
    mov  bx, ax
    mov  al, [bx+live_grid_data]
    xor  ah, ah                 ; AX = tile code
    test ax, ax
    jnz $+5
    jmp near .nextcol

    mov  cx, di
    shl  cx, 4                  ; i*16
    mov  dx, [bp+4]
    and  dx, 15                 ; camera_x mod 16
    sub  cx, dx                 ; screen x
    mov  dx, si
    shl  dx, 4                  ; screen y
    push cx
    push dx
    push ax
    call DrawTile
.nextcol:
    inc  di
    cmp  di, VIEW_COLS+1
    jae $+5
    jmp near .colloop
    inc  si
    cmp  si, GRID_ROWS
    jae $+5
    jmp near .rowloop

    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  2

; ============================================================
; MODULE 4 : sprites
; ============================================================
; ------------------------------------------------------------
; ConvertSprite(address)
; Purpose: 256 ASCII hex digits -> colour indexes 0..15. ONCE only.
; Inputs : [bp+4]=sprite address     Outputs: sprite converted
; Changes: none; callee pops 2
; ------------------------------------------------------------
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
    ja $+5
    jmp near .store
    sub  al, 7                  ; 'A'-'0'=17 -> 10
.store:
    mov  [bx], al
    inc  bx
    loop .next
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  2

; ------------------------------------------------------------
; DrawSprite(x, y, address, flags)
; Purpose: 16x16 sprite into draw_seg. Colour 0 = transparent.
;          Every pixel is clipped, mirror and blink supported.
; Inputs : [bp+10]=x (signed) [bp+8]=y (signed)
;          [bp+6]=address [bp+4]=flags (SPR_MIRROR | SPR_BLINK)
; Output : sprite drawn
; Changes: none; callee pops 8
; ------------------------------------------------------------
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
    mov  si, [bp+6]             ; SI = start of current sprite row
    xor  dx, dx                 ; DX = row 0..15
.row:
    mov  ax, [bp+8]
    add  ax, dx                 ; AX = screen y
    cmp  ax, 0
    jge $+5
    jmp near .nextrow
    cmp  ax, DISP_HEIGHT
    jl $+5
    jmp near .nextrow
    mov  di, ax
    shl  di, 8
    shl  ax, 6
    add  di, ax                 ; DI = y*320
    xor  cx, cx                 ; CX = column 0..15
.col:
    mov  bx, cx
    test word [bp+4], GFX_FLIP_H
    jnz $+5
    jmp near .read
    mov  bx, 15
    sub  bx, cx                 ; mirrored source column
.read:
    mov  al, [si+bx]
    test al, al
    jnz $+5
    jmp near .nextcol
    mov  bx, [bp+10]
    add  bx, cx                 ; BX = screen x
    cmp  bx, 0
    jge $+5
    jmp near .nextcol
    cmp  bx, DISP_WIDTH
    jl $+5
    jmp near .nextcol
    test word [bp+4], GFX_FLICKER
    jnz $+5
    jmp near .plot
    push ax
    mov  ax, bx
    add  ax, [bp+8]
    add  ax, dx
    test al, 1                  ; checkerboard: (x+y) even only
    pop  ax                     ; POP keeps the flags
    jz $+5
    jmp near .nextcol
.plot:
    mov  [es:bx+di], al         ; based-indexed addressing
.nextcol:
    inc  cx
    cmp  cx, 16
    jae $+5
    jmp near .col
.nextrow:
    add  si, 16
    inc  dx
    cmp  dx, 16
    jae $+5
    jmp near .row

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
; MODULE 5 : frame buffer
; ============================================================
; ------------------------------------------------------------
; AllocFrameBuffer
; Purpose: shrink our block to 64 KB (INT 21h AH=4Ah), then allocate
;          4000 paragraphs (AH=48h) for the 64000-byte frame buffer
; Inputs : none
; Outputs: CF=0 -> fb_seg = new segment;  CF=1 -> failed
; Changes: AX, flags (BX, ES preserved)
; ------------------------------------------------------------
AllocFrameBuffer:
    push bx
    push es
    mov  ax, cs
    mov  es, ax                 ; ES = our PSP segment
    mov  bx, 1000h              ; keep 64 KB
    mov  ah, 4Ah
    int  21h
    jnc $+5
    jmp near .fail
    mov  bx, BACKBUF_PARAS
    mov  ah, 48h
    int  21h                    ; AX = new segment
    jnc $+5
    jmp near .fail
    mov  [backbuf_seg], ax
    clc
.fail:
    pop  es                     ; POP keeps the carry flag
    pop  bx
    ret

; ------------------------------------------------------------
; FreeFrameBuffer
; Purpose: give the buffer back to DOS (INT 21h AH=49h)
; Inputs : none     Outputs: none     Changes: none
; ------------------------------------------------------------
FreeFrameBuffer:
    push ax
    push es
    mov  ax, [backbuf_seg]
    test ax, ax
    jnz $+5
    jmp near .skip
    mov  es, ax
    mov  ah, 49h
    int  21h
.skip:
    pop  es
    pop  ax
    ret

; ------------------------------------------------------------
; ClearFrame
; Purpose: fill the frame buffer with sky using ONE REP STOSW
; Inputs : none     Outputs: buffer cleared
; Changes: none (AX, CX, DI, ES, flags preserved)
; ------------------------------------------------------------
ClearFrame:
    pushf
    push ax
    push cx
    push di
    push es
    mov  es, [backbuf_seg]
    xor  di, di
    mov  ax, PAL_BACKDROP*101h       ; colour in both bytes of the word
    mov  cx, 32000
    cld
    rep  stosw
    pop  es
    pop  di
    pop  cx
    pop  ax
    popf
    ret

; ------------------------------------------------------------
; Present
; Purpose: copy the frame buffer to video memory with ONE REP MOVSW
; Inputs : none     Outputs: frame visible
; Changes: none (AX, CX, SI, DI, DS, ES, flags preserved)
; ------------------------------------------------------------
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
    mov  ds, [backbuf_seg]           ; DS changes: no variable access until restored
    xor  si, si
    xor  di, di
    mov  cx, 32000
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
; MODULE 7 : keyboard interrupt (INT 09h)
; ============================================================
; ------------------------------------------------------------
; InstallKeyboard
; Purpose: clear key table, save old INT 09h vector (AH=35h),
;          install KeyboardISR (AH=25h)
; Inputs : none     Outputs: old_int9 saved, ISR active
; Changes: none (AX, BX, CX, DX, DI, ES preserved)
; ------------------------------------------------------------
InstallKeyboard:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    push ds
    pop  es                     ; ES = DS for STOSB
    cld
    mov  di, key_held_buf
    mov  cx, 128
    xor  al, al
    rep  stosb                  ; no stuck keys

    mov  ax, 3509h              ; get vector 09h -> ES:BX
    int  21h
    mov  [prev_irq1_off], bx
    mov  [prev_irq1_seg], es

    mov  dx, KeyboardISR        ; DS:DX = our handler
    mov  ax, 2509h
    int  21h

    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ------------------------------------------------------------
; RestoreKeyboard
; Purpose: put the original INT 09h vector back
; Inputs : none     Outputs: vector restored
; Changes: none (AX, DX, DS preserved)
; ------------------------------------------------------------
RestoreKeyboard:
    push ax
    push dx
    push ds
    mov  dx, [prev_irq1_off]     ; read BEFORE DS is changed
    mov  ds, [prev_irq1_seg]
    mov  ax, 2509h
    int  21h
    pop  ds
    pop  dx
    pop  ax
    ret

; ------------------------------------------------------------
; KeyboardISR   (hardware interrupt, ends with IRET)
; Purpose: scan code from port 60h. E0h prefix ignored. Press ->
;          key_table[code]=1, release (bit 7) -> 0. Then EOI.
; Inputs : port 60h     Outputs: key_table
; Changes: none (AX, BX preserved); uses CS: because DS is unknown
; ------------------------------------------------------------
KeyboardISR:
    push ax
    push bx

    in   al, 60h                ; scan code
    cmp  al, 0E0h
    jne $+5
    jmp near .eoi

    mov  ah, al                 ; AH = original (bit 7 = release)
    xor  bh, bh
    mov  bl, al
    and  bl, 7Fh                ; BX = key number 0..127
    mov  al, 1                  ; assume pressed
    test ah, 80h
    jnz $+5
    jmp near .store
    xor  al, al                 ; release -> 0
.store:
    mov  [cs:key_held_buf + bx], al

.eoi:
    mov  al, 20h
    out  20h, al                ; end of interrupt to the PIC

    pop  bx
    pop  ax
    iret

; ------------------------------------------------------------
; IsKeyDown(scancode)
; Purpose: read one entry of the key-state table
; Inputs : [bp+4]=scan code     Output: AL = 1 held, 0 not held
; Changes: AL only; callee pops 2
; ------------------------------------------------------------
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

; ------------------------------------------------------------
; KeyPressed(scancode)
; Purpose: 1 only on the frame a key goes down (held now and not
;          held in the previous frame). Menus, P, Esc.
; Inputs : [bp+4]=scan code     Output: AL = 1 / 0
; Changes: AL only; callee pops 2
; ------------------------------------------------------------
KeyPressed:
    push bp
    mov  bp, sp
    push bx
    mov  bx, [bp+4]
    and  bx, 7Fh
    xor  al, al
    cmp  byte [key_held_buf + bx], 0
    jne $+5
    jmp near .done
    cmp  byte [key_last_buf + bx], 0
    je $+5
    jmp near .done
    mov  al, 1
.done:
    pop  bx
    pop  bp
    ret  2

; ------------------------------------------------------------
; SaveKeys
; Purpose: key_table -> key_prev (128 bytes, REP MOVSB)
; Inputs : none     Outputs: key_prev     Changes: none
; ------------------------------------------------------------
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
; MODULE 8 : timer interrupt (INT 08h) and game clock
; ============================================================
; ------------------------------------------------------------
; InstallTimer
; Purpose: save old INT 08h vector, install TimerISR, program the
;          PIT (channel 0) to about 60 Hz
; Inputs : none     Outputs: ISR active, last_tick synced
; Changes: none (AX, BX, DX, ES preserved)
; ------------------------------------------------------------
InstallTimer:
    push ax
    push bx
    push dx
    push es

    mov  ax, 3508h              ; get vector 08h -> ES:BX
    int  21h
    mov  [prev_irq0_off], bx
    mov  [prev_irq0_seg], es

    cli
    mov  dx, TimerISR
    mov  ax, 2508h
    int  21h

    mov  al, 36h                ; channel 0, lo/hi byte, mode 3
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

; ------------------------------------------------------------
; RestoreTimer
; Purpose: PIT back to 18.2 Hz (divisor 0) and original INT 08h
; Inputs : none     Outputs: original timer behaviour
; Changes: none (AX, DX, DS preserved)
; ------------------------------------------------------------
RestoreTimer:
    push ax
    push dx
    push ds
    cli
    mov  al, 36h
    out  43h, al
    xor  al, al
    out  40h, al                ; low byte 0
    out  40h, al                ; high byte 0 -> 65536
    mov  dx, [prev_irq0_off]     ; read BEFORE DS changes
    mov  ds, [prev_irq0_seg]
    mov  ax, 2508h
    int  21h
    sti
    pop  ds
    pop  dx
    pop  ax
    ret

; ------------------------------------------------------------
; TimerISR   (hardware interrupt, about 60 times per second)
; Purpose: tick_count++. An accumulator makes the ORIGINAL handler
;          run at 18.2 Hz (DOS clock stays correct). The original
;          handler sends the EOI itself; otherwise we send it.
; Inputs : none     Outputs: tick_count
; Changes: none (AX preserved); uses CS: overrides
; ------------------------------------------------------------
TimerISR:
    push ax
    inc  word [cs:sys_ticks]
    mov  ax, IRQ0_RELOAD
    add  [cs:pit_chain_acc], ax
    jnc $+5
    jmp near .chain
    mov  al, 20h
    out  20h, al                ; EOI
    pop  ax
    iret
.chain:
    pop  ax
    jmp  far [cs:prev_irq0_off]  ; old handler ends with IRET

; ------------------------------------------------------------
; WaitTick
; Purpose: HLT until TICKS_PER_FRAME ticks have passed. No delay
;          loops: speed comes from the timer interrupt.
; Inputs : none     Outputs: last_tick updated
; Changes: none (AX preserved)
; ------------------------------------------------------------
WaitTick:
    push ax
.wait:
    hlt
    mov  ax, [sys_ticks]
    sub  ax, [prev_frame_tick]
    cmp  ax, STEP_TICKS
    jae $+5
    jmp near .wait
    mov  ax, [sys_ticks]
    mov  [prev_frame_tick], ax
    pop  ax
    ret

; ------------------------------------------------------------
; UpdateClock
; Purpose: once per frame; every 60 ticks (1 real second)
;          time_left decreases. Frozen while clock_frozen = 1.
; Inputs : none     Outputs: time_left (stops at 0)
; Changes: flags only
; ------------------------------------------------------------
UpdateClock:
    cmp  byte [clock_halted], 0
    je $+5
    jmp near .done
    add  word [sec_tick_acc], STEP_TICKS
    cmp  word [sec_tick_acc], HZ_RATE
    jae $+5
    jmp near .done
    sub  word [sec_tick_acc], HZ_RATE
    cmp  word [stage_clock], 0
    jne $+5
    jmp near .done
    dec  word [stage_clock]
.done:
    ret

; ============================================================
; MODULE 9 : player movement and physics (8.8 fixed point)
; ============================================================
; ------------------------------------------------------------
; UpdatePlayer(left, right, run, jump)
; Purpose: one frame of Mario's physics (Section 5.2): accel,
;          brake, friction, speed limit, ground-only jump with
;          variable height, gravity, pose. The movement and the
;          tile collision are done by MoveHeroX / MoveHeroY.
; Inputs : [bp+10]=left [bp+8]=right [bp+6]=run [bp+4]=jump
; Output : hero variables updated
; Changes: none (AX, BX, CX, flags preserved); callee pops 8
; ------------------------------------------------------------
UpdatePlayer:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    pushf

    mov  bx, CAP_WALK_VX           ; BX = speed limit
    cmp  word [bp+6], 0
    jne $+5
    jmp near .lim
    mov  bx, CAP_SPRINT_VX
.lim:
    mov  ax, [bp+8]             ; right held?
    test ax, ax
    jnz $+5
    jmp near .rnot
    mov  ax, 1
.rnot:
    mov  cx, [bp+10]            ; left held?
    test cx, cx
    jnz $+5
    jmp near .lnot
    mov  cx, 1
.lnot:
    cmp  ax, cx
    jne $+5
    jmp near .friction
    test ax, ax
    jz $+5
    jmp near .goright

    ; ---------- moving LEFT ----------
    mov  byte [plr_dir], 1
    neg  bx
    mov  ax, [plr_vx]
    cmp  ax, bx
    jge $+5
    jmp near .l_decel
    mov  cx, RUN_ACCEL
    test ax, ax
    jg $+5
    jmp near .l_acc
    mov  cx, RUN_ACCEL*2            ; brake harder
.l_acc:
    sub  ax, cx
    cmp  ax, bx
    jl $+5
    jmp near .l_store
    mov  ax, bx
.l_store:
    mov  [plr_vx], ax
    jmp  .jump
.l_decel:
    add  ax, GROUND_DRAG
    cmp  ax, bx
    jg $+5
    jmp near .l_store
    mov  ax, bx
    jmp  .l_store

    ; ---------- moving RIGHT ----------
.goright:
    mov  byte [plr_dir], 0
    mov  ax, [plr_vx]
    cmp  ax, bx
    jle $+5
    jmp near .r_decel
    mov  cx, RUN_ACCEL
    test ax, ax
    js $+5
    jmp near .r_acc
    mov  cx, RUN_ACCEL*2
.r_acc:
    add  ax, cx
    cmp  ax, bx
    jg $+5
    jmp near .r_store
    mov  ax, bx
.r_store:
    mov  [plr_vx], ax
    jmp  .jump
.r_decel:
    sub  ax, GROUND_DRAG
    cmp  ax, bx
    jl $+5
    jmp near .r_store
    mov  ax, bx
    jmp  .r_store

    ; ---------- no direction: friction towards 0 ----------
.friction:
    mov  ax, [plr_vx]
    test ax, ax
    jnz $+5
    jmp near .jump
    jns $+5
    jmp near .f_neg
    sub  ax, GROUND_DRAG
    js $+5
    jmp near .f_store
    xor  ax, ax
    jmp  .f_store
.f_neg:
    add  ax, GROUND_DRAG
    jns $+5
    jmp near .f_store
    xor  ax, ax
.f_store:
    mov  [plr_vx], ax

    ; ---------- jump / variable jump height ----------
.jump:
    cmp  word [bp+4], 0
    jne $+5
    jmp near .nojump
    cmp  byte [leap_btn_held], 0
    je $+5
    jmp near .jmark
    cmp  byte [plr_grounded], 0
    jne $+5
    jmp near .jmark
    mov  word [plr_vy], LEAP_IMPULSE
    mov  byte [plr_grounded], 0
.jmark:
    mov  byte [leap_btn_held], 1
    jmp  .gravity
.nojump:
    mov  byte [leap_btn_held], 0
    mov  ax, [plr_vy]
    test ax, ax
    js $+5
    jmp near .gravity
    cmp  ax, LEAP_RELEASE_VY
    jl $+5
    jmp near .gravity
    mov  word [plr_vy], LEAP_RELEASE_VY   ; released early: short hop

    ; ---------- gravity ----------
.gravity:
    mov  ax, [plr_vy]
    add  ax, FALL_ACCEL
    cmp  ax, TERMINAL_VY
    jg $+5
    jmp near .g_ok
    mov  ax, TERMINAL_VY
.g_ok:
    mov  [plr_vy], ax

    ; ---------- move one axis at a time, with tile collision ----------
    call MoveHeroX
    call MoveHeroY

    ; ---------- pose: 0 stand, 1 run, 2 jump ----------
    mov  al, 2
    cmp  byte [plr_grounded], 0
    jne $+5
    jmp near .setpose
    mov  al, 0
    cmp  word [plr_vx], 0
    jne $+5
    jmp near .setpose
    mov  al, 1
.setpose:
    mov  [plr_anim_state], al

    popf
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  8

; ============================================================
; MODULE 10 : collision detection
; ============================================================
; ------------------------------------------------------------
; IsSolid(px, py)
; Purpose: is the WORKING-map tile at world pixel (px,py) solid?
;          Solid codes are 1..10 (Appendix A.2)
; Inputs : [bp+6]=px  [bp+4]=py (signed)
; Output : AX = 1 solid, 0 not solid
; Changes: AX, flags; callee pops 4
; ------------------------------------------------------------
IsSolid:
    push bp
    mov  bp, sp
    push word [bp+6]
    push word [bp+4]
    call GetTile
    dec  ax                     ; 1..10 -> 0..9 ; 0 -> FFFFh
    cmp  ax, 9
    jbe $+5
    jmp near .no
    mov  ax, 1
    jmp  .done
.no:
    xor  ax, ax
.done:
    pop  bp
    ret  4

; ------------------------------------------------------------
; HeroHeight
; Purpose: hitbox height from the form (Small 16, Super 32)
; Inputs : form     Output: AX = height     Changes: AX, flags
; ------------------------------------------------------------
HeroHeight:
    mov  ax, 16
    cmp  byte [plr_power_tier], 0
    jne $+5
    jmp near .done
    mov  ax, 32
.done:
    ret

; ------------------------------------------------------------
; WallAt(px)
; Purpose: solid tile at world x = px at feet, middle or head?
; Inputs : [bp+4]=px     Output: AX = 1 blocked, 0 free
; Changes: AX, flags; callee pops 2
; ------------------------------------------------------------
WallAt:
    push bp
    mov  bp, sp
    push bx
    push cx
    push dx
    call HeroHeight
    mov  cx, ax                 ; CX = height
    mov  bx, [plr_y]
    dec  bx                     ; lowest body pixel
    push word [bp+4]
    push bx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .done
    mov  dx, cx
    shr  dx, 1
    mov  bx, [plr_y]
    sub  bx, dx                 ; middle of the body
    push word [bp+4]
    push bx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .done
    mov  bx, [plr_y]
    sub  bx, cx                 ; head
    push word [bp+4]
    push bx
    call IsSolid
.done:
    pop  dx
    pop  cx
    pop  bx
    pop  bp
    ret  2

; ------------------------------------------------------------
; MoveHeroX
; Purpose: move Mario by hero_vx (8.8); wall -> place him against
;          the wall and vx = 0
; Inputs : hero_x/xf, hero_vx, hero_y, form
; Outputs: hero_x/xf, hero_vx
; Changes: none except flags
; ------------------------------------------------------------
MoveHeroX:
    push ax
    push bx
    push cx
    push dx

    mov  cx, [plr_vx]
    sar  cx, 8                  ; signed whole pixels
    mov  al, [plr_vx]          ; fraction byte
    add  [plr_sub_x], al
    adc  [plr_x], cx           ; carry goes into the pixel word

    mov  ax, [plr_vx]
    test ax, ax
    jnz $+5
    jmp near .done
    jns $+5
    jmp near .left

    mov  bx, [plr_x]           ; ----- moving right -----
    add  bx, BOX_PAD_R
    push bx
    call WallAt
    test ax, ax
    jnz $+5
    jmp near .done
    mov  bx, [plr_x]
    add  bx, BOX_PAD_R
    and  bx, 0FFF0h             ; left edge of the wall's tile column
    sub  bx, BOX_PAD_R+1
    mov  [plr_x], bx
    jmp  .stop
.left:
    mov  bx, [plr_x]           ; ----- moving left -----
    add  bx, BOX_PAD_L
    push bx
    call WallAt
    test ax, ax
    jnz $+5
    jmp near .done
    mov  bx, [plr_x]
    add  bx, BOX_PAD_L
    and  bx, 0FFF0h
    add  bx, 16                 ; right edge of the wall's tile
    sub  bx, BOX_PAD_L
    mov  [plr_x], bx
.stop:
    mov  word [plr_vx], 0
    mov  byte [plr_sub_x], 0
.done:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ------------------------------------------------------------
; MoveHeroY
; Purpose: move Mario by hero_vy and resolve: falling -> land on
;          solid tile (vy=0, on_ground=1, stomp_chain=0); rising ->
;          head hit (block_hit, hit_col, hit_row) and bump; saves
;          hero_prev_y; death_flag when the top passes y >= 192.
; Inputs : hero variables     Outputs: hero_y/yf/vy, on_ground ...
; Changes: none except flags
; ------------------------------------------------------------
MoveHeroY:
    push ax
    push bx
    push cx
    push dx

    mov  ax, [plr_y]
    mov  [plr_prev_y], ax      ; feet position in the previous frame
    mov  cx, [plr_vy]
    sar  cx, 8
    mov  al, [plr_vy]
    add  [plr_sub_y], al
    adc  [plr_y], cx
    mov  byte [plr_grounded], 0
    call HeroHeight
    mov  dx, ax                 ; DX = height
    cmp  word [plr_vy], 0
    jge $+5
    jmp near .rising

    mov  bx, [plr_y]           ; ----- falling / still -----
    mov  ax, [plr_x]
    add  ax, BOX_PAD_L
    push ax
    push bx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .land
    mov  ax, [plr_x]
    add  ax, BOX_PAD_R
    push ax
    push bx
    call IsSolid
    test ax, ax
    jnz $+5
    jmp near .pitchk
.land:
    and  word [plr_y], 0FFF0h  ; top of that tile row
    mov  byte [plr_sub_y], 0
    mov  word [plr_vy], 0
    mov  byte [plr_grounded], 1
    mov  byte [combo_hits], 0
    jmp  .pitchk

.rising:
    mov  bx, [plr_y]
    sub  bx, dx                 ; BX = y of the head
    mov  ax, [plr_x]
    add  ax, BOX_MID_X
    push ax
    push bx
    call IsSolid
    test ax, ax
    jnz $+5
    jmp near .corners
    mov  ax, [plr_x]           ; centre solid -> report the block
    add  ax, BOX_MID_X
    shr  ax, 4
    mov  [bumped_col], ax
    mov  ax, bx
    shr  ax, 4
    mov  [bumped_row], ax
    mov  byte [tile_bumped], 1
    jmp  .bump
.corners:
    mov  ax, [plr_x]
    add  ax, BOX_PAD_L
    push ax
    push bx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .bump
    mov  ax, [plr_x]
    add  ax, BOX_PAD_R
    push ax
    push bx
    call IsSolid
    test ax, ax
    jnz $+5
    jmp near .pitchk
.bump:
    and  bx, 0FFF0h
    add  bx, 16                 ; bottom edge of the tile row
    add  bx, dx                 ; feet = tile bottom + height
    mov  [plr_y], bx
    mov  byte [plr_sub_y], 0
    mov  word [plr_vy], 0      ; starts falling

.pitchk:
    mov  ax, [plr_y]
    sub  ax, dx                 ; top of Mario
    cmp  ax, 192
    jge $+5
    jmp near .done
    mov  byte [plr_is_dead], 1   ; fell below the map
.done:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ------------------------------------------------------------
; CheckFlag
; Purpose: does Mario's hitbox overlap a flag-pole tile (12)?
;          First contact: flag_touched = 1, flag_row = feet row
; Inputs : hero variables     Outputs: flag_touched, flag_row
; Changes: none except flags
; ------------------------------------------------------------
CheckFlag:
    push ax
    push bx
    push cx
    call HeroHeight
    mov  cx, ax
    mov  bx, [plr_y]
    dec  bx
    call .row
    mov  bx, [plr_y]
    mov  ax, cx
    shr  ax, 1
    sub  bx, ax
    call .row
    mov  bx, [plr_y]
    sub  bx, cx
    call .row
    pop  cx
    pop  bx
    pop  ax
    ret
.row:                           ; BX = py to test
    mov  ax, [plr_x]
    add  ax, BOX_PAD_L
    push ax
    push bx
    call GetTile
    cmp  ax, CELL_GOAL_POLE
    jne $+5
    jmp near .hit
    mov  ax, [plr_x]
    add  ax, BOX_PAD_R
    push ax
    push bx
    call GetTile
    cmp  ax, CELL_GOAL_POLE
    je $+5
    jmp near .rowend
.hit:
    cmp  byte [goal_reached], 0
    je $+5
    jmp near .rowend
    mov  byte [goal_reached], 1
    mov  ax, [plr_y]
    dec  ax
    shr  ax, 4
    mov  [goal_hit_row], al         ; row of the feet
.rowend:
    ret

; ------------------------------------------------------------
; FlagPoints
; Purpose: flag score from flag_row via a word table (Section 5.4)
; Inputs : flag_row     Output: AX = points     Changes: AX
; ------------------------------------------------------------
FlagPoints:
    push bx
    xor  bx, bx
    mov  bl, [goal_hit_row]
    shl  bx, 1
    mov  ax, [pole_score_lut + bx]    ; indexed addressing
    pop  bx
    ret

; ------------------------------------------------------------
; RectOverlap(ax, ay, aw, ah, bx, by, bw, bh)
; Purpose: do two rectangles overlap? (signed compares)
; Inputs : [bp+18]=ax [bp+16]=ay [bp+14]=aw [bp+12]=ah
;          [bp+10]=bx [bp+8]=by  [bp+6]=bw  [bp+4]=bh
; Output : AX = 1 overlap, 0 no overlap
; Changes: AX, flags; callee pops 16
; ------------------------------------------------------------
RectOverlap:
    push bp
    mov  bp, sp
    mov  ax, [bp+10]
    add  ax, [bp+6]             ; b.right
    cmp  [bp+18], ax
    jl $+5
    jmp near .no
    mov  ax, [bp+18]
    add  ax, [bp+14]            ; a.right
    cmp  [bp+10], ax
    jl $+5
    jmp near .no
    mov  ax, [bp+8]
    add  ax, [bp+4]             ; b.bottom
    cmp  [bp+16], ax
    jl $+5
    jmp near .no
    mov  ax, [bp+16]
    add  ax, [bp+12]            ; a.bottom
    cmp  [bp+8], ax
    jl $+5
    jmp near .no
    mov  ax, 1
    jmp  .done
.no:
    xor  ax, ax
.done:
    pop  bp
    ret  16

; ------------------------------------------------------------
; StompTest(prev_feet, enemy_top, enemy_height)
; Purpose: Section 5.6 stomp rule: Mario moving down AND his feet
;          in the previous frame at or above the enemy's upper half
; Inputs : [bp+8]=prev feet y  [bp+6]=enemy top y  [bp+4]=height
; Output : AX = 1 stomp, 0 hurt
; Changes: AX, flags; callee pops 6
; ------------------------------------------------------------
StompTest:
    push bp
    mov  bp, sp
    push bx
    xor  ax, ax
    cmp  word [plr_vy], 0
    jg $+5
    jmp near .done
    mov  bx, [bp+4]
    shr  bx, 1
    add  bx, [bp+6]             ; middle line of the enemy
    cmp  [bp+8], bx
    jle $+5
    jmp near .done
    mov  ax, 1
.done:
    pop  bx
    pop  bp
    ret  6

; ============================================================
; MODULE 6 : camera and scrolling (Section 5.3)
; ============================================================
; ------------------------------------------------------------
; UpdateCamera
; Purpose: once per frame after Mario moved:
;          screen_x = hero_x - camera_x; if screen_x > 160 then
;          new = hero_x - 160, clamp to 640, camera = max(camera,new)
;          (never scrolls left); left wall: hero_x < camera_x ->
;          hero_x = camera_x, vx = 0; right end: hero_x <= 944.
; Inputs : hero_x, camera_x     Outputs: camera_x, hero_x, hero_vx
; Changes: none except flags
; ------------------------------------------------------------
UpdateCamera:
    push ax
    push bx

    mov  ax, [plr_x]
    mov  bx, ax
    sub  bx, [scroll_offset_x]         ; BX = screen_x
    cmp  bx, CAM_DEADZONE_X
    jg $+5
    jmp near .leftwall
    sub  ax, CAM_DEADZONE_X         ; AX = new_camera
    cmp  ax, CAM_LIMIT_X
    ja $+5
    jmp near .nomax
    mov  ax, CAM_LIMIT_X
.nomax:
    cmp  ax, [scroll_offset_x]
    ja $+5
    jmp near .leftwall
    mov  [scroll_offset_x], ax

.leftwall:
    mov  ax, [plr_x]
    cmp  ax, [scroll_offset_x]
    jl $+5
    jmp near .rightend
    mov  ax, [scroll_offset_x]         ; invisible wall on the left edge
    mov  [plr_x], ax
    mov  byte [plr_sub_x], 0
    mov  word [plr_vx], 0

.rightend:
    cmp  word [plr_x], STAGE_END_X
    jg $+5
    jmp near .done
    mov  word [plr_x], STAGE_END_X
    mov  byte [plr_sub_x], 0
    mov  word [plr_vx], 0
.done:
    pop  bx
    pop  ax
    ret

; ============================================================
; MODULE 11 : enemies and shells
; ============================================================
; ------------------------------------------------------------
; ResetEnemies
; Purpose: enemy_init -> enemies with ONE REP MOVSW
; Inputs : none     Outputs: enemies at their start
; Changes: none (flags, CX, SI, DI, ES preserved)
; ------------------------------------------------------------
ResetEnemies:
    pushf
    push cx
    push si
    push di
    push es
    push ds
    pop  es
    cld
    mov  si, foe_spawn_list
    mov  di, foe_pool
    mov  cx, FOE_SLOTS*FOE_STRIDE/2
    rep  movsw
    pop  es
    pop  di
    pop  si
    pop  cx
    popf
    ret

; ------------------------------------------------------------
; UpdateEnemies
; Purpose: frame step 4: update every used slot
; Inputs : enemies     Outputs: enemies updated
; Changes: none (CX, SI preserved)
; ------------------------------------------------------------
UpdateEnemies:
    push cx
    push si
    mov  si, foe_pool
    mov  cx, FOE_SLOTS
.next:
    cmp  byte [si+FOE_KIND], KIND_EMPTY
    jne $+5
    jmp near .skip
    push si
    call UpdateOneEnemy
.skip:
    add  si, FOE_STRIDE
    loop .next
    pop  si
    pop  cx
    ret

; ------------------------------------------------------------
; UpdateOneEnemy(record)
; Purpose: grace countdown, activation (within one tile of the
;          screen), removal, flat timer, walk/slide with wall and
;          enemy turn, Koopa edge turn, shell kills, gravity
; Inputs : [bp+4]=address of the record
; Output : record updated (E_TYPE = 0 when removed)
; Changes: none; callee pops 2
; ------------------------------------------------------------
UpdateOneEnemy:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov  si, [bp+4]

    cmp  byte [si+FOE_SAFE_T], 0
    jne $+5
    jmp near .g_ok
    dec  byte [si+FOE_SAFE_T]
.g_ok:
    cmp  byte [si+FOE_MODE], MODE_DORMANT
    je $+5
    jmp near .active
    mov  ax, [si+FOE_POS_X]
    sub  ax, [scroll_offset_x]
    cmp  ax, DISP_WIDTH+CELL_PX
    jl $+5
    jmp near .done
    mov  byte [si+FOE_MODE], MODE_PATROL
.active:
    mov  ax, [si+FOE_POS_X]
    sub  ax, [scroll_offset_x]
    cmp  ax, -32
    jge $+5
    jmp near .remove
    cmp  word [si+FOE_POS_Y], 192
    jl $+5
    jmp near .remove

    cmp  byte [si+FOE_MODE], MODE_SQUASHED
    je $+5
    jmp near .notflat
    dec  byte [si+FOE_CNT]
    jnz $+5
    jmp near .remove
    jmp  .gravity
.notflat:
    cmp  byte [si+FOE_MODE], MODE_CARAPACE
    jne $+5
    jmp near .gravity

    mov  bx, WALKER_VX       ; BX = signed speed (8.8)
    cmp  byte [si+FOE_KIND], KIND_TURTLE
    je $+5
    jmp near .spd_a
    mov  bx, TURTLE_VX
.spd_a:
    cmp  byte [si+FOE_MODE], MODE_SPINNING
    je $+5
    jmp near .spd_b
    mov  bx, SPIN_VX
.spd_b:
    cmp  byte [si+FOE_HEADING], 0
    jne $+5
    jmp near .move
    neg  bx                     ; moving left
.move:
    mov  cx, bx
    sar  cx, 8
    mov  al, bl                 ; fraction byte
    add  [si+FOE_SUB_X], al
    adc  [si+FOE_POS_X], cx

    mov  di, [si+FOE_POS_X]           ; DI = leading edge x
    cmp  byte [si+FOE_HEADING], 0
    je $+5
    jmp near .probe
    add  di, 15
.probe:
    mov  dx, [si+FOE_POS_Y]
    add  dx, 8
    push di
    push dx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .turn
    add  dx, 7                  ; y + 15
    push di
    push dx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .turn

    cmp  byte [si+FOE_KIND], KIND_TURTLE      ; Koopa turns at platform edges
    je $+5
    jmp near .others
    cmp  byte [si+FOE_MODE], MODE_PATROL
    je $+5
    jmp near .others
    cmp  word [si+FOE_VEL_Y], 0
    je $+5
    jmp near .others
    mov  dx, [si+FOE_POS_Y]
    add  dx, 16
    push di
    push dx
    call IsSolid
    test ax, ax
    jnz $+5
    jmp near .turn

.others:
    cmp  byte [si+FOE_MODE], MODE_PATROL
    je $+5
    jmp near .after_move
    push si
    call BlockedByEnemy
    test ax, ax
    jnz $+5
    jmp near .after_move
.turn:                          ; undo this frame's step, face the other way
    mov  cx, bx
    sar  cx, 8
    mov  al, bl
    sub  [si+FOE_SUB_X], al
    sbb  [si+FOE_POS_X], cx
    xor  byte [si+FOE_HEADING], 1
    jmp  .gravity
.after_move:
    cmp  byte [si+FOE_MODE], MODE_SPINNING
    je $+5
    jmp near .gravity
    push si
    call ShellKills

.gravity:
    mov  ax, [si+FOE_VEL_Y]
    add  ax, FALL_ACCEL
    cmp  ax, TERMINAL_VY
    jg $+5
    jmp near .g_store
    mov  ax, TERMINAL_VY
.g_store:
    mov  [si+FOE_VEL_Y], ax
    mov  cx, ax
    sar  cx, 8
    mov  al, [si+FOE_VEL_Y]
    add  [si+FOE_SUB_Y], al
    adc  [si+FOE_POS_Y], cx

    mov  dx, [si+FOE_POS_Y]
    add  dx, 16                 ; pixel row under the feet
    mov  ax, [si+FOE_POS_X]
    add  ax, 2
    push ax
    push dx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .land
    mov  ax, [si+FOE_POS_X]
    add  ax, 13
    push ax
    push dx
    call IsSolid
    test ax, ax
    jnz $+5
    jmp near .done
.land:
    mov  ax, [si+FOE_POS_Y]
    add  ax, 16
    and  ax, 0FFF0h
    sub  ax, 16
    mov  [si+FOE_POS_Y], ax
    mov  byte [si+FOE_SUB_Y], 0
    mov  word [si+FOE_VEL_Y], 0
    jmp  .done
.remove:
    mov  byte [si+FOE_KIND], KIND_EMPTY
.done:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  2

; ------------------------------------------------------------
; EnemiesTouch(recA, recB)
; Purpose: do two 16x16 enemy boxes overlap? (|dx|<16 and |dy|<16)
; Inputs : [bp+6]=recA  [bp+4]=recB     Output: AX = 1 / 0
; Changes: AX, flags; callee pops 4
; ------------------------------------------------------------
EnemiesTouch:
    push bp
    mov  bp, sp
    push si
    push di
    mov  si, [bp+6]
    mov  di, [bp+4]
    mov  ax, [si+FOE_POS_X]
    sub  ax, [di+FOE_POS_X]
    js $+5
    jmp near .x_abs
    neg  ax
.x_abs:
    cmp  ax, 16
    jl $+5
    jmp near .no
    mov  ax, [si+FOE_POS_Y]
    sub  ax, [di+FOE_POS_Y]
    js $+5
    jmp near .y_abs
    neg  ax
.y_abs:
    cmp  ax, 16
    jl $+5
    jmp near .no
    mov  ax, 1
    jmp  .done
.no:
    xor  ax, ax
.done:
    pop  di
    pop  si
    pop  bp
    ret  4

; ------------------------------------------------------------
; BlockedByEnemy(record)
; Purpose: does a walking enemy touch another walking enemy or a
;          stationary shell? (then it turns around)
; Inputs : [bp+4]=record     Output: AX = 1 blocked, 0 free
; Changes: AX, flags; callee pops 2
; ------------------------------------------------------------
BlockedByEnemy:
    push bp
    mov  bp, sp
    push cx
    push si
    push di
    mov  si, [bp+4]
    mov  di, foe_pool
    mov  cx, FOE_SLOTS
.next:
    cmp  di, si
    jne $+5
    jmp near .skip
    cmp  byte [di+FOE_KIND], KIND_EMPTY
    jne $+5
    jmp near .skip
    mov  al, [di+FOE_MODE]
    cmp  al, MODE_PATROL
    jne $+5
    jmp near .test
    cmp  al, MODE_CARAPACE
    je $+5
    jmp near .skip
.test:
    push si
    push di
    call EnemiesTouch
    test ax, ax
    jz $+5
    jmp near .done
.skip:
    add  di, FOE_STRIDE
    loop .next
    xor  ax, ax
.done:
    pop  di
    pop  si
    pop  cx
    pop  bp
    ret  2

; ------------------------------------------------------------
; ShellKills(record)
; Purpose: a sliding shell removes every walking enemy it touches
;          (+500 each)
; Inputs : [bp+4]=shell record     Output: victims removed, score
; Changes: none; callee pops 2
; ------------------------------------------------------------
ShellKills:
    push bp
    mov  bp, sp
    push ax
    push cx
    push si
    push di
    mov  si, [bp+4]
    mov  di, foe_pool
    mov  cx, FOE_SLOTS
.next:
    cmp  di, si
    jne $+5
    jmp near .skip
    cmp  byte [di+FOE_KIND], KIND_EMPTY
    jne $+5
    jmp near .skip
    cmp  byte [di+FOE_MODE], MODE_PATROL
    je $+5
    jmp near .skip
    push si
    push di
    call EnemiesTouch
    test ax, ax
    jnz $+5
    jmp near .skip
    mov  byte [di+FOE_KIND], KIND_EMPTY
    push word 500
    call AddScore
.skip:
    add  di, FOE_STRIDE
    loop .next
    pop  di
    pop  si
    pop  cx
    pop  ax
    pop  bp
    ret  2

; ------------------------------------------------------------
; ResolveEnemies
; Purpose: frame step 5: Mario against every enemy that can touch
;          him (enemies in kick grace are ignored)
; Inputs : hero + enemies     Outputs: score, health, state
; Changes: none
; ------------------------------------------------------------
ResolveEnemies:
    push ax
    push cx
    push si
    cmp  byte [plr_is_dead], 0
    je $+5
    jmp near .done
    mov  si, foe_pool
    mov  cx, FOE_SLOTS
.next:
    cmp  byte [si+FOE_KIND], KIND_EMPTY
    jne $+5
    jmp near .skip
    cmp  byte [si+FOE_SAFE_T], 0
    je $+5
    jmp near .skip
    mov  al, [si+FOE_MODE]
    cmp  al, MODE_PATROL
    jne $+5
    jmp near .test
    cmp  al, MODE_CARAPACE
    jne $+5
    jmp near .test
    cmp  al, MODE_SPINNING
    je $+5
    jmp near .skip
.test:
    push si
    call HeroVsEnemy
.skip:
    add  si, FOE_STRIDE
    loop .next
.done:
    pop  si
    pop  cx
    pop  ax
    ret

; ------------------------------------------------------------
; HeroVsEnemy(record)
; Purpose: Section 5.6 outcomes: overlap? stationary shell -> kick
;          (+400); stomp -> defeat + chain points + bounce;
;          otherwise hurt (ignored while invulnerable)
; Inputs : [bp+4]=record
; Output : enemy state, score, hero state
; Changes: none; callee pops 2
; ------------------------------------------------------------
HeroVsEnemy:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    mov  si, [bp+4]

    call HeroHeight
    mov  bx, ax                 ; BX = Mario height
    mov  ax, [plr_x]
    add  ax, BOX_PAD_L
    push ax                     ; a.x
    mov  ax, [plr_y]
    sub  ax, bx
    push ax                     ; a.y (top of Mario)
    push word 12                ; a.w
    push bx                     ; a.h
    mov  ax, [si+FOE_POS_X]
    add  ax, 2
    push ax                     ; b.x
    push word [si+FOE_POS_Y]          ; b.y
    push word 12                ; b.w
    push word 16                ; b.h
    call RectOverlap
    test ax, ax
    jnz $+5
    jmp near .done

    cmp  byte [si+FOE_MODE], MODE_CARAPACE
    jne $+5
    jmp near .kick

    push word [plr_prev_y]
    push word [si+FOE_POS_Y]
    push word 16
    call StompTest
    test ax, ax
    jz $+5
    jmp near .stomp

    cmp  word [plr_mercy_cnt], 0
    je $+5
    jmp near .done
    call HurtHero
    jmp  .done

.kick:                          ; slide away from Mario
    mov  ax, [plr_x]
    add  ax, 8
    mov  bx, [si+FOE_POS_X]
    add  bx, 8
    mov  byte [si+FOE_HEADING], 1
    cmp  ax, bx
    jl $+5
    jmp near .kick_go
    mov  byte [si+FOE_HEADING], 0
.kick_go:
    mov  byte [si+FOE_MODE], MODE_SPINNING
    mov  byte [si+FOE_SAFE_T], KICK_SAFE_TICKS
    push word 400
    call AddScore
    jmp  .done

.stomp:
    mov  word [plr_vy], BOUNCE_LOW_VY
    push word KEY_LEAP_CODE
    call IsKeyDown
    test al, al
    jnz $+5
    jmp near .bounce
    mov  word [plr_vy], BOUNCE_HIGH_VY
.bounce:
    mov  ax, [si+FOE_POS_Y]
    mov  [plr_y], ax           ; feet on top of the enemy
    mov  byte [plr_sub_y], 0
    mov  byte [plr_grounded], 0
    cmp  byte [si+FOE_KIND], KIND_TURTLE
    jne $+5
    jmp near .koopa
    mov  byte [si+FOE_MODE], MODE_SQUASHED
    mov  byte [si+FOE_CNT], SQUASH_TICKS
    jmp  .chain
.koopa:
    mov  byte [si+FOE_MODE], MODE_CARAPACE
    mov  byte [si+FOE_SAFE_T], KICK_SAFE_TICKS
.chain:
    call StompScore
.done:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  2

; ------------------------------------------------------------
; StompScore
; Purpose: stomp-chain points from a word table; 11th stomp = 1-UP
; Inputs : stomp_chain     Outputs: score / lives, chain + 1
; Changes: none
; ------------------------------------------------------------
StompScore:
    push ax
    push bx
    xor  bx, bx
    mov  bl, [combo_hits]
    cmp  bl, 10
    jb $+5
    jmp near .oneup
    shl  bx, 1
    push word [combo_score_lut + bx]
    call AddScore
    inc  byte [combo_hits]
    jmp  .done
.oneup:
    call AddLife
.done:
    pop  bx
    pop  ax
    ret

; ------------------------------------------------------------
; HurtHero
; Purpose: Super -> Small + 2 s invulnerability; Small -> death
; Inputs : form     Outputs: form, hp, invuln_timer or death_flag
; Changes: flags only
; ------------------------------------------------------------
HurtHero:
    cmp  byte [plr_power_tier], 0
    jne $+5
    jmp near .die
    mov  byte [plr_power_tier], 0
    mov  byte [plr_vitality], 1
    mov  word [plr_mercy_cnt], MERCY_TICKS
    ret
.die:
    mov  byte [plr_is_dead], 1
    ret

; ------------------------------------------------------------
; TickInvuln
; Purpose: frame step 6: count the blink timer down
; Inputs : invuln_timer     Outputs: invuln_timer - 1
; Changes: flags only
; ------------------------------------------------------------
TickInvuln:
    cmp  word [plr_mercy_cnt], 0
    jne $+5
    jmp near .done
    dec  word [plr_mercy_cnt]
.done:
    ret

; ------------------------------------------------------------
; AddLife
; Purpose: lives + 1, never above 99
; Inputs : lives     Outputs: lives     Changes: flags only
; ------------------------------------------------------------
AddLife:
    cmp  byte [plr_lives], 99
    jb $+5
    jmp near .done
    inc  byte [plr_lives]
.done:
    ret

; ------------------------------------------------------------
; AddScore(points)
; Purpose: 32-bit score += points (ADD/ADC), clamp at 999,999
;          (000F423Fh). The ONLY place where the score changes.
; Inputs : [bp+4]=points (word)     Output: score_lo / score_hi
; Changes: none; callee pops 2
; ------------------------------------------------------------
AddScore:
    push bp
    mov  bp, sp
    push ax
    mov  ax, [bp+4]
    add  [pts_low], ax
    adc  word [pts_high], 0
    cmp  word [pts_high], 0Fh
    jae $+5
    jmp near .done
    jbe $+5
    jmp near .clamp
    cmp  word [pts_low], 423Fh
    ja $+5
    jmp near .done
.clamp:
    mov  word [pts_high], 0Fh
    mov  word [pts_low], 423Fh
.done:
    pop  ax
    pop  bp
    ret  2

; ------------------------------------------------------------
; ScoreToText
; Purpose: 32-bit score -> 6 ASCII digits by repeated division by
;          10 (high word first; its remainder feeds the next DIV).
;          Remainders are pushed and popped in reverse order.
;          Also fills lives_txt and hp_txt.
; Inputs : score_hi:score_lo, lives, hp
; Outputs: score_txt (6 chars), lives_txt, hp_txt
; Changes: none
; ------------------------------------------------------------
ScoreToText:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov  si, [pts_high]
    mov  di, [pts_low]
    mov  bx, 10
    mov  cx, 6
.div:
    mov  ax, si
    xor  dx, dx
    div  bx                     ; high word / 10
    mov  si, ax
    mov  ax, di                 ; DX (remainder) = high half
    div  bx                     ; DX = digit
    mov  di, ax
    push dx
    loop .div
    xor  si, si
.pop:
    pop  ax
    add  al, '0'
    mov  [pts_ascii + si], al
    inc  si
    cmp  si, 6
    jae $+5
    jmp near .pop
    mov  al, [plr_lives]
    add  al, '0'
    mov  [lives_ascii], al
    mov  al, [plr_vitality]
    add  al, '0'
    mov  [vitality_ascii], al
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ------------------------------------------------------------
; DrawEnemies
; Purpose: draw every used enemy on screen (-16 < screen_x < 320)
; Inputs : enemies, camera_x     Outputs: sprites in the buffer
; Changes: none
; ------------------------------------------------------------
DrawEnemies:
    push ax
    push bx
    push cx
    push dx
    push si
    mov  si, foe_pool
    mov  cx, FOE_SLOTS
.next:
    cmp  byte [si+FOE_KIND], KIND_EMPTY
    jne $+5
    jmp near .skip
    mov  ax, [si+FOE_POS_X]
    sub  ax, [scroll_offset_x]         ; screen_x = world_x - camera_x
    cmp  ax, -16
    jg $+5
    jmp near .skip
    cmp  ax, DISP_WIDTH
    jl $+5
    jmp near .skip
    mov  bx, gfx_walker
    cmp  byte [si+FOE_KIND], KIND_TURTLE
    jne $+5
    jmp near .koopa
    cmp  byte [si+FOE_MODE], MODE_SQUASHED
    je $+5
    jmp near .draw
    mov  bx, gfx_walker_flat
    jmp  .draw
.koopa:
    mov  bx, gfx_turtle
    cmp  byte [si+FOE_MODE], MODE_CARAPACE
    jae $+5
    jmp near .draw
    mov  bx, gfx_carapace
.draw:
    mov  dl, [si+FOE_HEADING]         ; 1 = left = SPR_MIRROR
    xor  dh, dh
    push ax
    push word [si+FOE_POS_Y]
    push bx
    push dx
    call DrawSprite
.skip:
    add  si, FOE_STRIDE
    loop .next
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; MODULE 12 : blocks, coins and power-ups
; ============================================================
; ------------------------------------------------------------
; AddCoin
; Purpose: +200 points, coins + 1; at 100: coins = 0, lives + 1
; Inputs : none     Outputs: score, coins, lives
; Changes: flags only
; ------------------------------------------------------------
AddCoin:
    push word 200
    call AddScore
    inc  byte [coin_tally]
    cmp  byte [coin_tally], 100
    jae $+5
    jmp near .done
    mov  byte [coin_tally], 0
    call AddLife
.done:
    ret

; ------------------------------------------------------------
; PowerUp
; Purpose: Small -> Super. hero_y is the FEET position, so the
;          feet stay fixed and the top rises. HP never exceeds 2.
; Inputs : none     Outputs: form = 1, hp = 2     Changes: flags
; ------------------------------------------------------------
PowerUp:
    mov  byte [plr_power_tier], 1
    mov  byte [plr_vitality], 2
    ret

; ------------------------------------------------------------
; TriggerBlock
; Purpose: react to a head hit on the WORKING map (Section 5.9)
;          brick: Super -> sky +50; ? coin -> empty + coin;
;          ? mushroom -> empty + mushroom
; Inputs : block_hit, hit_col, hit_row, form
; Outputs: work_map, score, coins, mushrooms
; Changes: none
; ------------------------------------------------------------
TriggerBlock:
    push ax
    push bx
    push si
    cmp  byte [tile_bumped], 0
    jne $+5
    jmp near .done
    mov  byte [tile_bumped], 0
    cmp  word [bumped_col], GRID_COLS
    jb $+5
    jmp near .done
    cmp  word [bumped_row], GRID_ROWS
    jb $+5
    jmp near .done
    mov  ax, [bumped_row]
    mov  bx, ax
    shl  ax, 6
    shl  bx, 2
    sub  ax, bx                 ; row*60
    add  ax, [bumped_col]
    mov  si, ax
    mov  al, [live_grid_data + si]
    cmp  al, CELL_PRIZE_COIN
    jne $+5
    jmp near .qcoin
    cmp  al, CELL_PRIZE_MUSH
    jne $+5
    jmp near .qmush
    cmp  al, CELL_MASONRY
    je $+5
    jmp near .done
    cmp  byte [plr_power_tier], 0
    jne $+5
    jmp near .done
    mov  byte [live_grid_data + si], CELL_AIR
    push word 50
    call AddScore
    jmp  .done
.qcoin:
    mov  byte [live_grid_data + si], CELL_USED
    call AddCoin
    jmp  .done
.qmush:
    mov  byte [live_grid_data + si], CELL_USED
    push word [bumped_col]
    push word [bumped_row]
    call SpawnMushroom
.done:
    pop  si
    pop  bx
    pop  ax
    ret

; ------------------------------------------------------------
; SpawnMushroom(col, row)
; Purpose: mushroom in the first free slot, on top of the block
; Inputs : [bp+6]=col  [bp+4]=row of the block
; Output : one mushroom record active
; Changes: none; callee pops 4
; ------------------------------------------------------------
SpawnMushroom:
    push bp
    mov  bp, sp
    push ax
    push cx
    push si
    mov  si, item_pool
    mov  cx, ITEM_SLOTS
.find:
    cmp  byte [si+ITEM_ALIVE], 0
    jne $+5
    jmp near .found
    add  si, ITEM_STRIDE
    loop .find
    jmp  .done
.found:
    mov  byte [si+ITEM_ALIVE], 1
    mov  byte [si+ITEM_HEADING], 0
    mov  ax, [bp+6]
    shl  ax, 4
    mov  [si+ITEM_POS_X], ax
    mov  byte [si+ITEM_SUB_X], 0
    mov  ax, [bp+4]
    shl  ax, 4
    sub  ax, 16                 ; on top of the block
    mov  [si+ITEM_POS_Y], ax
    mov  byte [si+ITEM_SUB_Y], 0
    mov  word [si+ITEM_VEL_Y], 0
.done:
    pop  si
    pop  cx
    pop  ax
    pop  bp
    ret  4

; ------------------------------------------------------------
; ResetMushrooms
; Purpose: remove every mushroom (REP STOSW)
; Inputs : none     Outputs: table cleared
; Changes: none
; ------------------------------------------------------------
ResetMushrooms:
    pushf
    push ax
    push cx
    push di
    push es
    push ds
    pop  es
    cld
    mov  di, item_pool
    mov  cx, ITEM_SLOTS*ITEM_STRIDE/2
    xor  ax, ax
    rep  stosw
    pop  es
    pop  di
    pop  cx
    pop  ax
    popf
    ret

; ------------------------------------------------------------
; UpdateMushrooms
; Purpose: frame step 4: update every active mushroom
; Inputs : mushrooms     Outputs: mushrooms updated
; Changes: none
; ------------------------------------------------------------
UpdateMushrooms:
    push cx
    push si
    mov  si, item_pool
    mov  cx, ITEM_SLOTS
.next:
    cmp  byte [si+ITEM_ALIVE], 0
    jne $+5
    jmp near .skip
    push si
    call UpdateOneMushroom
.skip:
    add  si, ITEM_STRIDE
    loop .next
    pop  si
    pop  cx
    ret

; ------------------------------------------------------------
; UpdateOneMushroom(record)
; Purpose: remove when left behind / in a pit; move 1 px/frame,
;          turn at walls, gravity, land on solid tiles
; Inputs : [bp+4]=address of the record
; Output : record updated (M_ACT = 0 when removed)
; Changes: none; callee pops 2
; ------------------------------------------------------------
UpdateOneMushroom:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov  si, [bp+4]

    mov  ax, [si+ITEM_POS_X]
    sub  ax, [scroll_offset_x]
    cmp  ax, -32
    jge $+5
    jmp near .remove
    cmp  word [si+ITEM_POS_Y], 192
    jl $+5
    jmp near .remove

    mov  bx, ITEM_VX
    cmp  byte [si+ITEM_HEADING], 0
    jne $+5
    jmp near .move
    neg  bx
.move:
    mov  cx, bx
    sar  cx, 8
    mov  al, bl
    add  [si+ITEM_SUB_X], al
    adc  [si+ITEM_POS_X], cx

    mov  di, [si+ITEM_POS_X]           ; leading edge x
    cmp  byte [si+ITEM_HEADING], 0
    je $+5
    jmp near .probe
    add  di, 15
.probe:
    mov  dx, [si+ITEM_POS_Y]
    add  dx, 8
    push di
    push dx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .turn
    add  dx, 7
    push di
    push dx
    call IsSolid
    test ax, ax
    jnz $+5
    jmp near .gravity
.turn:
    mov  cx, bx
    sar  cx, 8
    mov  al, bl
    sub  [si+ITEM_SUB_X], al
    sbb  [si+ITEM_POS_X], cx
    xor  byte [si+ITEM_HEADING], 1

.gravity:
    mov  ax, [si+ITEM_VEL_Y]
    add  ax, FALL_ACCEL
    cmp  ax, TERMINAL_VY
    jg $+5
    jmp near .g_store
    mov  ax, TERMINAL_VY
.g_store:
    mov  [si+ITEM_VEL_Y], ax
    mov  cx, ax
    sar  cx, 8
    mov  al, [si+ITEM_VEL_Y]
    add  [si+ITEM_SUB_Y], al
    adc  [si+ITEM_POS_Y], cx

    mov  dx, [si+ITEM_POS_Y]
    add  dx, 16
    mov  ax, [si+ITEM_POS_X]
    add  ax, 2
    push ax
    push dx
    call IsSolid
    test ax, ax
    jz $+5
    jmp near .land
    mov  ax, [si+ITEM_POS_X]
    add  ax, 13
    push ax
    push dx
    call IsSolid
    test ax, ax
    jnz $+5
    jmp near .done
.land:
    mov  ax, [si+ITEM_POS_Y]
    add  ax, 16
    and  ax, 0FFF0h
    sub  ax, 16
    mov  [si+ITEM_POS_Y], ax
    mov  byte [si+ITEM_SUB_Y], 0
    mov  word [si+ITEM_VEL_Y], 0
    jmp  .done
.remove:
    mov  byte [si+ITEM_ALIVE], 0
.done:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  2

; ------------------------------------------------------------
; CheckMushrooms
; Purpose: Mario overlaps a mushroom -> removed, +1000, Small
;          becomes Super (already Super: points only)
; Inputs : hero + mushrooms     Outputs: score, form, hp
; Changes: none
; ------------------------------------------------------------
CheckMushrooms:
    push ax
    push bx
    push cx
    push si
    call HeroHeight
    mov  bx, ax                 ; BX = Mario height
    mov  si, item_pool
    mov  cx, ITEM_SLOTS
.next:
    cmp  byte [si+ITEM_ALIVE], 0
    jne $+5
    jmp near .skip
    mov  ax, [plr_x]
    add  ax, BOX_PAD_L
    push ax
    mov  ax, [plr_y]
    sub  ax, bx
    push ax
    push word 12
    push bx
    mov  ax, [si+ITEM_POS_X]
    add  ax, 2
    push ax
    push word [si+ITEM_POS_Y]
    push word 12
    push word 16
    call RectOverlap
    test ax, ax
    jnz $+5
    jmp near .skip
    mov  byte [si+ITEM_ALIVE], 0
    push word 1000
    call AddScore
    cmp  byte [plr_power_tier], 0
    je $+5
    jmp near .skip
    call PowerUp
.skip:
    add  si, ITEM_STRIDE
    loop .next
    pop  si
    pop  cx
    pop  bx
    pop  ax
    ret

; ------------------------------------------------------------
; CollectCoins
; Purpose: sample Mario's hitbox at 2 x-positions and 3 heights;
;          every coin tile found is collected
; Inputs : hero variables     Outputs: map, score, coins
; Changes: none
; ------------------------------------------------------------
CollectCoins:
    push ax
    push bx
    push cx
    call HeroHeight
    mov  cx, ax
    mov  bx, [plr_y]
    dec  bx
    call .row
    mov  bx, [plr_y]
    mov  ax, cx
    shr  ax, 1
    sub  bx, ax
    call .row
    mov  bx, [plr_y]
    sub  bx, cx
    call .row
    pop  cx
    pop  bx
    pop  ax
    ret
.row:                           ; BX = py to test
    mov  ax, [plr_x]
    add  ax, BOX_PAD_L
    push ax
    push bx
    call TakeCoinAt
    mov  ax, [plr_x]
    add  ax, BOX_PAD_R
    push ax
    push bx
    call TakeCoinAt
    ret

; ------------------------------------------------------------
; TakeCoinAt(px, py)
; Purpose: coin tile at the pixel -> tile becomes sky, AddCoin
; Inputs : [bp+6]=px  [bp+4]=py
; Output : map / score / coins
; Changes: none; callee pops 4
; ------------------------------------------------------------
TakeCoinAt:
    push bp
    mov  bp, sp
    push ax
    push bx
    push word [bp+6]
    push word [bp+4]
    call GetTile
    cmp  ax, CELL_PICKUP_COIN
    je $+5
    jmp near .done
    mov  bx, [bp+4]
    shr  bx, 4                  ; row
    mov  ax, bx
    shl  ax, 6
    shl  bx, 2
    sub  ax, bx                 ; row*60
    mov  bx, [bp+6]
    shr  bx, 4                  ; col
    add  bx, ax
    mov  byte [live_grid_data + bx], CELL_AIR
    call AddCoin
.done:
    pop  bx
    pop  ax
    pop  bp
    ret  4

; ------------------------------------------------------------
; DrawMushrooms
; Purpose: draw every active mushroom that is on screen
; Inputs : mushrooms, camera_x     Outputs: sprites in the buffer
; Changes: none
; ------------------------------------------------------------
DrawMushrooms:
    push ax
    push cx
    push si
    mov  si, item_pool
    mov  cx, ITEM_SLOTS
.next:
    cmp  byte [si+ITEM_ALIVE], 0
    jne $+5
    jmp near .skip
    mov  ax, [si+ITEM_POS_X]
    sub  ax, [scroll_offset_x]
    cmp  ax, -16
    jg $+5
    jmp near .skip
    cmp  ax, DISP_WIDTH
    jl $+5
    jmp near .skip
    push ax
    push word [si+ITEM_POS_Y]
    push word gfx_powerup
    push word 0
    call DrawSprite
.skip:
    add  si, ITEM_STRIDE
    loop .next
    pop  si
    pop  cx
    pop  ax
    ret

; ============================================================
; MODULE 13 : HUD, bitmap font
; ============================================================
; ------------------------------------------------------------
; DrawGlyph(x, y, address, colour)
; Purpose: 8x8 1-bit glyph into the frame buffer (bit 7 = left pixel)
; Inputs : [bp+10]=x [bp+8]=y [bp+6]=glyph address [bp+4]=colour
; Output : glyph drawn
; Changes: none; callee pops 8
; ------------------------------------------------------------
DrawGlyph:
    push bp
    mov  bp, sp
    push ax
    push cx
    push dx
    push si
    push di
    push es

    mov  es, [render_target_seg]
    mov  di, [bp+8]             ; y
    mov  ax, di
    shl  di, 8
    shl  ax, 6
    add  di, ax                 ; y*320
    add  di, [bp+10]            ; + x
    mov  si, [bp+6]
    mov  ah, [bp+4]             ; AH = colour
    mov  dx, 8                  ; rows left
.row:
    mov  al, [si]
    mov  cx, 8
    push di
.bit:
    shl  al, 1                  ; MSB -> carry
    jc $+5
    jmp near .skip
    mov  [es:di], ah
.skip:
    inc  di
    loop .bit
    pop  di
    add  di, DISP_WIDTH
    inc  si
    dec  dx
    jz $+5
    jmp near .row

    pop  es
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  ax
    pop  bp
    ret  8

; ------------------------------------------------------------
; DrawChar(x, y, char, colour)
; Purpose: ASCII -> glyph: '0'-'9' 0..9, 'A'-'Z' 10..35, '-' 36,
;          anything else 37 (blank)
; Inputs : [bp+10]=x [bp+8]=y [bp+6]=char [bp+4]=colour
; Output : character drawn
; Changes: none; callee pops 8
; ------------------------------------------------------------
DrawChar:
    push bp
    mov  bp, sp
    push ax
    push bx
    mov  ax, [bp+6]
    xor  ah, ah
    cmp  al, '-'
    jne $+5
    jmp near .dash
    cmp  al, '0'
    jae $+5
    jmp near .blank
    cmp  al, '9'
    ja $+5
    jmp near .digit
    cmp  al, 'A'
    jae $+5
    jmp near .blank
    cmp  al, 'Z'
    jbe $+5
    jmp near .blank
    sub  al, 'A'-10
    jmp  .addr
.digit:
    sub  al, '0'
    jmp  .addr
.dash:
    mov  al, 36
    jmp  .addr
.blank:
    mov  al, 37
.addr:
    mov  bx, ax
    shl  bx, 3                  ; 8 bytes per glyph
    add  bx, bmp_charset
    push word [bp+10]
    push word [bp+8]
    push bx
    push word [bp+4]
    call DrawGlyph
    pop  bx
    pop  ax
    pop  bp
    ret  8

; ------------------------------------------------------------
; DrawText(x, y, address, colour)
; Purpose: zero-terminated string, 8 pixels per character
; Inputs : [bp+10]=x [bp+8]=y [bp+6]=string [bp+4]=colour
; Output : text drawn
; Changes: none; callee pops 8
; ------------------------------------------------------------
DrawText:
    push bp
    mov  bp, sp
    push ax
    push dx
    push si
    mov  si, [bp+6]
    mov  dx, [bp+10]
.next:
    mov  al, [si]
    test al, al
    jnz $+5
    jmp near .done
    xor  ah, ah
    push dx
    push word [bp+8]
    push ax
    push word [bp+4]
    call DrawChar
    add  dx, 8
    inc  si
    jmp  .next
.done:
    pop  si
    pop  dx
    pop  ax
    pop  bp
    ret  8

; ------------------------------------------------------------
; DrawNumber(x, y, value, digits, colour)
; Purpose: zero-padded decimal number. Repeated division by 10,
;          remainders PUSHed, then POPped in reverse order.
; Inputs : [bp+12]=x [bp+10]=y [bp+8]=value [bp+6]=digits (>=1)
;          [bp+4]=colour
; Output : number drawn
; Changes: none; callee pops 10
; ------------------------------------------------------------
DrawNumber:
    push bp
    mov  bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov  ax, [bp+8]
    mov  bx, 10
    mov  cx, [bp+6]
    mov  si, cx
.div:
    xor  dx, dx
    div  bx
    push dx
    loop .div
    mov  di, [bp+12]
.pop:
    pop  ax
    add  al, '0'
    xor  ah, ah
    push di
    push word [bp+10]
    push ax
    push word [bp+4]
    call DrawChar
    add  di, 8
    dec  si
    jz $+5
    jmp near .pop
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pop  bp
    ret  10

; ------------------------------------------------------------
; DrawHUD
; Purpose: HUD strip (top 16 px): SCORE, COINS, WORLD, TIME,
;          LIVES, HEALTH hearts. Fixed: it never scrolls.
; Inputs : score, coins, time_left, lives, hp
; Output : HUD in the frame buffer
; Changes: none
; ------------------------------------------------------------
DrawHUD:
    push ax
    push bx

    push word 0
    push word 0
    push word DISP_WIDTH
    push word 16
    push word PAL_BAR_BG
    call FillRect

    push word 4                 ; labels, y = 0
    push word 0
    push word hud_lbl_pts
    push word PAL_HEADER_TXT
    call DrawText
    push word 68
    push word 0
    push word hud_lbl_coins
    push word PAL_HEADER_TXT
    call DrawText
    push word 116
    push word 0
    push word hud_lbl_stage
    push word PAL_HEADER_TXT
    call DrawText
    push word 164
    push word 0
    push word hud_lbl_clock
    push word PAL_HEADER_TXT
    call DrawText
    push word 204
    push word 0
    push word hud_lbl_lives
    push word PAL_HEADER_TXT
    call DrawText
    push word 256
    push word 0
    push word hud_lbl_hp
    push word PAL_HEADER_TXT
    call DrawText

    call ScoreToText            ; values, y = 8
    push word 4
    push word 8
    push word pts_ascii
    push word PAL_NUM_TXT
    call DrawText

    push word 68                ; COINS: X + 2 digits
    push word 8
    push word 'X'
    push word PAL_NUM_TXT
    call DrawChar
    xor  ax, ax
    mov  al, [coin_tally]
    push word 76
    push word 8
    push ax
    push word 2
    push word PAL_NUM_TXT
    call DrawNumber

    push word 116               ; WORLD
    push word 8
    push word hud_val_stage
    push word PAL_NUM_TXT
    call DrawText

    push word 164               ; TIME: 3 digits
    push word 8
    push word [stage_clock]
    push word 3
    push word PAL_NUM_TXT
    call DrawNumber

    push word 204               ; LIVES: X + number
    push word 8
    push word 'X'
    push word PAL_NUM_TXT
    call DrawChar
    xor  ax, ax
    mov  al, [plr_lives]
    mov  bx, 1
    cmp  al, 10
    jae $+5
    jmp near .one
    mov  bx, 2
.one:
    push word 212
    push word 8
    push ax
    push bx
    push word PAL_NUM_TXT
    call DrawNumber

    push word 256               ; hearts
    push word 8
    push word bmp_heart_icon
    push word PAL_VITAL_ON
    call DrawGlyph
    mov  bx, PAL_VITAL_OFF
    cmp  byte [plr_vitality], 2
    jae $+5
    jmp near .second
    mov  bx, PAL_VITAL_ON
.second:
    push word 266
    push word 8
    push word bmp_heart_icon
    push bx
    call DrawGlyph

    pop  bx
    pop  ax
    ret

; ============================================================
; MODULE 14 / 15 : game states, screens, restart, clean exit
; ============================================================
; ------------------------------------------------------------
; ResetHero
; Purpose: Mario at the level start as Small Mario, camera 0, clock 300
; Inputs : none     Outputs: hero variables, camera, clock
; Changes: flags only
; ------------------------------------------------------------
ResetHero:
    mov  word [plr_x], 32
    mov  byte [plr_sub_x], 0
    mov  word [plr_y], 160     ; feet on the ground
    mov  byte [plr_sub_y], 0
    mov  word [plr_prev_y], 160
    mov  word [plr_vx], 0
    mov  word [plr_vy], 0
    mov  byte [plr_power_tier], 0
    mov  byte [plr_vitality], 1
    mov  byte [plr_grounded], 1
    mov  byte [plr_dir], 0
    mov  byte [plr_anim_state], 0
    mov  byte [leap_btn_held], 0
    mov  byte [combo_hits], 0
    mov  word [plr_mercy_cnt], 0
    mov  byte [plr_is_dead], 0
    mov  byte [plr_hidden], 0
    mov  byte [clear_step], 0
    mov  word [scroll_offset_x], 0
    mov  word [stage_clock], STAGE_SECONDS
    mov  word [sec_tick_acc], 0
    ret

; ------------------------------------------------------------
; ResetLevel
; Purpose: restore map, enemies, mushrooms, Mario, camera, clock.
;          Score, coins and lives are KEPT (Section 5.8).
; Inputs : none     Outputs: level at its start     Changes: flags
; ------------------------------------------------------------
ResetLevel:
    call ResetMap
    call ResetEnemies
    call ResetMushrooms
    call ResetHero
    mov  byte [goal_reached], 0
    mov  byte [tile_bumped], 0
    mov  byte [clock_halted], 0
    ret

; ------------------------------------------------------------
; NewGame
; Purpose: ResetLevel plus score 0, coins 0, lives 3
; Inputs : none     Outputs: fresh game     Changes: flags
; ------------------------------------------------------------
NewGame:
    mov  word [pts_low], 0
    mov  word [pts_high], 0
    mov  byte [coin_tally], 0
    mov  byte [plr_lives], 3
    call ResetLevel
    ret

; ------------------------------------------------------------
; DrawBox(x, y, w, h, border, fill)
; Purpose: filled rectangle with a 2-pixel border
; Inputs : [bp+14]=x [bp+12]=y [bp+10]=w [bp+8]=h
;          [bp+6]=border colour  [bp+4]=fill colour
; Changes: none; callee pops 12
; ------------------------------------------------------------
DrawBox:
    push bp
    mov  bp, sp
    push ax
    push word [bp+14]
    push word [bp+12]
    push word [bp+10]
    push word [bp+8]
    push word [bp+6]
    call FillRect
    mov  ax, [bp+14]
    add  ax, 2
    push ax
    mov  ax, [bp+12]
    add  ax, 2
    push ax
    mov  ax, [bp+10]
    sub  ax, 4
    push ax
    mov  ax, [bp+8]
    sub  ax, 4
    push ax
    push word [bp+4]
    call FillRect
    pop  ax
    pop  bp
    ret  12

; ------------------------------------------------------------
; DrawTextC(y, address, colour)
; Purpose: zero-terminated string centred horizontally
; Inputs : [bp+8]=y  [bp+6]=string  [bp+4]=colour
; Changes: none; callee pops 6
; ------------------------------------------------------------
DrawTextC:
    push bp
    mov  bp, sp
    push ax
    push si
    mov  si, [bp+6]
    xor  ax, ax
.len:
    cmp  byte [si], 0
    jne $+5
    jmp near .got
    inc  si
    inc  ax
    jmp  .len
.got:
    shl  ax, 3                  ; width in pixels
    neg  ax
    add  ax, DISP_WIDTH
    shr  ax, 1                  ; x = (320 - width) / 2
    push ax
    push word [bp+8]
    push word [bp+6]
    push word [bp+4]
    call DrawText
    pop  si
    pop  ax
    pop  bp
    ret  6

; ------------------------------------------------------------
; DrawMario
; Purpose: draw Mario (16x16 Small, two halves for Super). Skipped
;          on every second frame while invulnerable (blink) and
;          when he has entered the castle (hide_hero).
; Inputs : hero variables, camera_x     Changes: flags only
; ------------------------------------------------------------
DrawMario:
    push ax
    cmp  byte [plr_hidden], 0
    je $+5
    jmp near .done
    test word [plr_mercy_cnt], 1
    jz $+5
    jmp near .done
    mov  ax, [plr_x]
    sub  ax, [scroll_offset_x]         ; screen_x = world_x - camera_x
    mov  [view_px_x], ax
    mov  ax, [plr_y]
    sub  ax, 16                 ; top of the lower half
    mov  [view_px_y], ax
    xor  ax, ax
    mov  al, [plr_dir]           ; 1 = mirror
    mov  [blit_opts], ax
    push word [view_px_x]
    push word [view_px_y]
    push word gfx_player
    push word [blit_opts]
    call DrawSprite
    cmp  byte [plr_power_tier], 0
    jne $+5
    jmp near .done
    mov  ax, [view_px_y]
    sub  ax, 16                 ; upper half (placeholder art)
    push word [view_px_x]
    push ax
    push word gfx_player
    push word [blit_opts]
    call DrawSprite
.done:
    pop  ax
    ret

; ------------------------------------------------------------
; DrawWorld
; Purpose: frame step 9: clear, draw tiles, items, enemies, Mario,
;          HUD (also used by Paused, Dying and Win)
; Inputs : game variables     Outputs: finished frame in buffer
; Changes: none
; ------------------------------------------------------------
DrawWorld:
    call ClearFrame
    push word [scroll_offset_x]
    call DrawMap
    call DrawMushrooms
    call DrawEnemies
    call DrawMario
    call DrawHUD
    ret

; ------------------------------------------------------------
; DebugKeys   (listed in the README)
; Purpose: S = Small/Super, C = coins 99, T = time 5 s, R = reset
; Inputs : keys     Outputs: hero / coins / clock / level
; Changes: none
; ------------------------------------------------------------
DebugKeys:
    push ax
    push word KEY_DBG_SIZE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .c
    xor  byte [plr_power_tier], 1
    mov  al, [plr_power_tier]
    inc  al
    mov  [plr_vitality], al               ; hp = 1 + form
.c:
    push word KEY_DBG_COINS
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .t
    mov  byte [coin_tally], 99
.t:
    push word KEY_DBG_TIME
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .r
    mov  word [stage_clock], 5
.r:
    push word KEY_DBG_RESET
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .done
    call ResetLevel
.done:
    pop  ax
    ret

; ------------------------------------------------------------
; StateTitle   (GS_TITLE)
; Purpose: Up/Down move the highlight, Enter on START = new game,
;          Enter on EXIT or Esc = leave. Draws the title screen.
; ------------------------------------------------------------
StateTitle:
    push ax
    push word KEY_U_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .down
    mov  byte [title_cursor], 0
.down:
    push word KEY_D_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .esc
    mov  byte [title_cursor], 1
.esc:
    push word KEY_ESC_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .enter
    mov  byte [curr_phase], PHASE_QUIT
    jmp  .done
.enter:
    push word KEY_RET_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .draw
    cmp  byte [title_cursor], 0
    je $+5
    jmp near .exitsel
    call NewGame
    mov  byte [curr_phase], PHASE_ACTIVE
    jmp  .done
.exitsel:
    mov  byte [curr_phase], PHASE_QUIT
    jmp  .done

.draw:
    push word 0                 ; sky
    push word 0
    push word DISP_WIDTH
    push word DISP_HEIGHT
    push word 9
    call FillRect
    push word 0                 ; brick border: top, bottom, left, right
    push word 0
    push word DISP_WIDTH
    push word 16
    push word 4
    call FillRect
    push word 0
    push word 184
    push word DISP_WIDTH
    push word 16
    push word 4
    call FillRect
    push word 0
    push word 0
    push word 16
    push word DISP_HEIGHT
    push word 4
    call FillRect
    push word 304
    push word 0
    push word 16
    push word DISP_HEIGHT
    push word 4
    call FillRect
    push word 16                ; ground and grass
    push word 160
    push word 288
    push word 24
    push word 6
    call FillRect
    push word 16
    push word 160
    push word 288
    push word 4
    push word 2
    call FillRect

    push word 40                ; title text
    push word str_game_name
    push word 12
    call DrawTextC
    push word 56
    push word str_sub_name
    push word 15
    call DrawTextC

    push word 100               ; menu box
    push word 88
    push word 120
    push word 44
    push word 15
    push word 0
    call DrawBox
    push word 124
    push word 98
    push word str_opt_play
    push word 14
    call DrawText
    push word 124
    push word 114
    push word str_opt_quit
    push word 15
    call DrawText
    xor  ax, ax
    mov  al, [title_cursor]
    shl  ax, 4                  ; 16 pixels per menu line
    add  ax, 99
    push word 110               ; highlight marker
    push ax
    push word 6
    push word 6
    push word 14
    call FillRect

    push word 24                ; decoration
    push word 144
    push word gfx_player
    push word 0
    call DrawSprite
    push word 280
    push word 144
    push word gfx_walker
    push word GFX_FLIP_H
    call DrawSprite
    push word 168               ; team line: EDIT txt_team
    push word str_credits
    push word 15
    call DrawTextC
.done:
    pop  ax
    ret

; ------------------------------------------------------------
; StatePlaying   (GS_PLAYING)   Section 5.13, steps 2 to 9
; (step 1 = WaitTick and step 10 = Present are in the main loop)
; ------------------------------------------------------------
StatePlaying:
    push ax
    push word KEY_PAUSE_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .nopause
    mov  byte [curr_phase], PHASE_HOLD
    jmp  .done
.nopause:
    push word KEY_ESC_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .run
    mov  byte [curr_phase], PHASE_MENU
    jmp  .done
.run:
    call DebugKeys

    push word KEY_L_CODE           ; step 2: key-state table -> arguments
    call IsKeyDown
    xor  ah, ah
    push ax
    push word KEY_R_CODE
    call IsKeyDown
    xor  ah, ah
    push ax
    push word KEY_SPRINT_CODE
    call IsKeyDown
    xor  ah, ah
    push ax
    push word KEY_LEAP_CODE
    call IsKeyDown
    xor  ah, ah
    push ax
    call UpdatePlayer           ; step 3

    call UpdateEnemies          ; step 4
    call UpdateMushrooms

    call ResolveEnemies         ; step 5
    call CheckMushrooms
    call CollectCoins
    call TriggerBlock

    call TickInvuln             ; step 6
    call UpdateClock
    cmp  word [stage_clock], 0
    je $+5
    jmp near .time_ok
    mov  byte [plr_is_dead], 1   ; clock reached 0 (Section 5.10)
.time_ok:

    call CheckFlag              ; step 7
    cmp  byte [plr_is_dead], 0
    je $+5
    jmp near .dead
    cmp  byte [goal_reached], 0
    je $+5
    jmp near .won
    call UpdateCamera           ; step 8
    call DrawWorld              ; step 9
    jmp  .done

.dead:
    call StartDeath
    mov  byte [curr_phase], PHASE_FALLING
    mov  word [phase_delay_cnt], FALL_ANIM_TICKS
    jmp  .done
.won:
    call FlagPoints             ; AX = points for the contact height
    push ax
    call AddScore
    call StartWin               ; sets GS_WIN
.done:
    pop  ax
    ret

; ------------------------------------------------------------
; StatePaused   (GS_PAUSED)
; Purpose: frozen picture with a PAUSED box. P = resume, Esc = title.
; ------------------------------------------------------------
StatePaused:
    push ax
    push word KEY_PAUSE_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .esc
    mov  byte [curr_phase], PHASE_ACTIVE
    jmp  .done
.esc:
    push word KEY_ESC_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .draw
    mov  byte [curr_phase], PHASE_MENU
    jmp  .done
.draw:
    call DrawWorld
    push word 80
    push word 76
    push word 160
    push word 48
    push word 15
    push word 0
    call DrawBox
    push word 88
    push word str_hold_hdr
    push word 14
    call DrawTextC
    push word 104
    push word str_hold_hint
    push word 15
    call DrawTextC
.done:
    pop  ax
    ret

; ------------------------------------------------------------
; StartDeath
; Purpose: begin the death animation (Section 5.8). Enemy / clock
;          death: hop up about 48 px. Pit death: no hop.
; Inputs : hero_y     Outputs: hero_vy, hero_vx, invuln_timer
; Changes: flags only
; ------------------------------------------------------------
StartDeath:
    mov  word [plr_mercy_cnt], 0
    mov  word [plr_vx], 0
    mov  byte [clock_halted], 1
    cmp  word [plr_y], 192
    jl $+5
    jmp near .done
    mov  word [plr_vy], DEFEAT_BOUNCE_VY
.done:
    ret

; ------------------------------------------------------------
; StateDying   (GS_DYING)
; Purpose: Mario moves with gravity only (no collisions), world
;          frozen. After DEATH_FRAMES: lives - 1, then LIFE LOST
;          (lives left) or GAME OVER.
; Changes: none
; ------------------------------------------------------------
StateDying:
    push ax
    push cx
    mov  ax, [plr_vy]
    add  ax, FALL_ACCEL
    mov  [plr_vy], ax
    mov  cx, ax
    sar  cx, 8
    add  [plr_sub_y], al
    adc  [plr_y], cx
    call DrawWorld
    dec  word [phase_delay_cnt]
    jz $+5
    jmp near .done
    dec  byte [plr_lives]
    jnz $+5
    jmp near .gameover
    mov  byte [curr_phase], PHASE_RETRY
    mov  word [phase_delay_cnt], RETRY_BANNER_TICKS
    jmp  .done
.gameover:
    mov  byte [curr_phase], PHASE_DEFEAT
.done:
    pop  cx
    pop  ax
    ret

; ------------------------------------------------------------
; StateLifeLost   (GS_LIFELOST)
; Purpose: black screen: WORLD 1-1, Mario icon, lives left; after
;          about 2 s ResetLevel and back to PLAYING
; ------------------------------------------------------------
StateLifeLost:
    push ax
    push word 0
    push word 0
    push word DISP_WIDTH
    push word DISP_HEIGHT
    push word 0
    call FillRect
    push word 56
    push word str_stage_hdr
    push word 15
    call DrawTextC
    push word 128
    push word 88
    push word gfx_player
    push word 0
    call DrawSprite
    push word 156
    push word 96
    push word 'X'
    push word 15
    call DrawChar
    xor  ax, ax
    mov  al, [plr_lives]
    push word 172
    push word 96
    push ax
    push word 2
    push word 15
    call DrawNumber
    push word 130
    push word str_rem_lives
    push word 14
    call DrawTextC
    dec  word [phase_delay_cnt]
    jz $+5
    jmp near .done
    call ResetLevel
    mov  byte [curr_phase], PHASE_ACTIVE
.done:
    pop  ax
    ret

; ------------------------------------------------------------
; StartWin
; Purpose: flag touched: freeze the clock and controls, snap Mario
;          to the pole, begin the slide (flag points already added)
; Inputs : none     Outputs: hero at the pole, game_state = GS_WIN
; Changes: flags only
; ------------------------------------------------------------
StartWin:
    mov  word [plr_x], POLE_LOCK_X
    mov  byte [plr_sub_x], 0
    mov  word [plr_vx], 0
    mov  word [plr_vy], 0
    mov  byte [plr_dir], 0
    mov  word [plr_mercy_cnt], 0
    mov  byte [clock_halted], 1
    mov  byte [clear_step], 0
    mov  byte [plr_hidden], 0
    mov  byte [curr_phase], PHASE_CLEAR_ANIM
    ret

; ------------------------------------------------------------
; StateWin   (GS_WIN)
; Purpose: phase 0 = slide down the pole (3 px/frame); phase 1 =
;          walk right WALK_FRAMES, step down to the ground,
;          disappear at the castle door. Then time_left * 50 is
;          added to the score and LEVEL COMPLETE starts.
; Changes: none
; ------------------------------------------------------------
StateWin:
    push ax
    push bx
    push dx
    cmp  byte [clear_step], 0
    je $+5
    jmp near .walk

    mov  ax, [plr_y]           ; ---- phase 0: slide ----
    add  ax, POLE_DROP_VY
    cmp  ax, POLE_BOTTOM_Y
    jge $+5
    jmp near .slide_set
    mov  ax, POLE_BOTTOM_Y
    mov  byte [clear_step], 1
    mov  word [phase_delay_cnt], VICTORY_MARCH_TICKS
.slide_set:
    mov  [plr_y], ax
    jmp  .draw

.walk:                          ; ---- phase 1: walk to the castle ----
    add  word [plr_x], VICTORY_STEP_VX
    mov  ax, [plr_x]
    mov  bx, POLE_BOTTOM_Y
    cmp  ax, 904
    jge $+5
    jmp near .feet
    mov  bx, FLOOR_BASE_Y
.feet:
    mov  [plr_y], bx
    cmp  ax, KEEP_DOOR_X
    jge $+5
    jmp near .timer
    mov  byte [plr_hidden], 1
.timer:
    dec  word [phase_delay_cnt]
    jz $+5
    jmp near .draw

    mov  ax, [stage_clock]        ; ---- finished: time bonus ----
    mov  bx, 50
    mul  bx                     ; AX = time_left * 50 (max 15000)
    mov  [clock_reward], ax
    push ax
    call AddScore
    mov  byte [curr_phase], PHASE_SUMMARY
    jmp  .done
.draw:
    call DrawWorld
.done:
    pop  dx
    pop  bx
    pop  ax
    ret

; ------------------------------------------------------------
; StateComplete   (GS_COMPLETE)
; Purpose: LEVEL COMPLETE screen; Enter -> TITLE
; ------------------------------------------------------------
StateComplete:
    push ax
    push word KEY_RET_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .draw
    mov  byte [curr_phase], PHASE_MENU
    jmp  .done
.draw:
    call ScoreToText
    push word 0
    push word 0
    push word DISP_WIDTH
    push word DISP_HEIGHT
    push word 0
    call FillRect
    push word 40
    push word 24
    push word 240
    push word 152
    push word 14
    push word 0
    call DrawBox
    push word 40
    push word str_stage_clear
    push word 14
    call DrawTextC
    push word 72
    push word 70
    push word hud_lbl_coins
    push word 15
    call DrawText
    push word 200
    push word 70
    push word 'X'
    push word 15
    call DrawChar
    xor  ax, ax
    mov  al, [coin_tally]
    push word 208
    push word 70
    push ax
    push word 2
    push word 15
    call DrawNumber
    push word 72
    push word 86
    push word str_rem_time
    push word 15
    call DrawText
    push word 200
    push word 86
    push word [stage_clock]
    push word 3
    push word 15
    call DrawNumber
    push word 72
    push word 102
    push word str_time_pts
    push word 15
    call DrawText
    push word 200
    push word 102
    push word [clock_reward]
    push word 5
    push word 15
    call DrawNumber
    push word 72
    push word 118
    push word str_total_pts
    push word 14
    call DrawText
    push word 200
    push word 118
    push word pts_ascii
    push word 14
    call DrawText
    push word 150
    push word str_next_prompt
    push word 10
    call DrawTextC
.done:
    pop  ax
    ret

; ------------------------------------------------------------
; StateGameOver   (GS_GAMEOVER)
; Purpose: GAME OVER screen with the final score; Enter -> TITLE
; ------------------------------------------------------------
StateGameOver:
    push ax
    push word KEY_RET_CODE
    call KeyPressed
    test al, al
    jnz $+5
    jmp near .draw
    mov  byte [curr_phase], PHASE_MENU
    jmp  .done
.draw:
    call ScoreToText
    push word 0
    push word 0
    push word DISP_WIDTH
    push word DISP_HEIGHT
    push word 0
    call FillRect
    push word 48
    push word 40
    push word 224
    push word 120
    push word 4
    push word 0
    call DrawBox
    push word 56
    push word str_defeat_hdr
    push word 12
    call DrawTextC
    push word 72
    push word 88
    push word str_total_pts
    push word 15
    call DrawText
    push word 192
    push word 88
    push word pts_ascii
    push word 15
    call DrawText
    push word 72
    push word 104
    push word hud_lbl_coins
    push word 14
    call DrawText
    push word 192
    push word 104
    push word 'X'
    push word 14
    call DrawChar
    xor  ax, ax
    mov  al, [coin_tally]
    push word 200
    push word 104
    push ax
    push word 2
    push word 14
    call DrawNumber
    push word 72
    push word 120
    push word hud_lbl_clock
    push word 14
    call DrawText
    push word 192
    push word 120
    push word [stage_clock]
    push word 3
    push word 14
    call DrawNumber
    push word 140
    push word str_menu_prompt
    push word 10
    call DrawTextC
.done:
    pop  ax
    ret

; ------------------------------------------------------------
; CleanExit
; Purpose: the ONLY way out. Restores timer rate + vector and the
;          keyboard vector, frees the frame buffer, text mode,
;          flushes the DOS keyboard buffer, exits to DOS.
; Inputs : none     Outputs: never returns
; ------------------------------------------------------------
CleanExit:
    call RestoreTimer
    call RestoreKeyboard
    call FreeFrameBuffer
    mov  ax, 0003h
    int  10h
    mov  ax, 0C00h              ; flush the DOS keyboard buffer
    int  21h
    mov  ax, 4C00h
    int  21h

; ============================================================
; DATA  (everything is at the end of the file)
; ============================================================
backbuf_seg          dw 0                    ; segment of the frame buffer
render_target_seg        dw VGA_SEGMENT            ; set to fb_seg in start
scroll_offset_x        dw 0
err_alloc_str       db "Not enough memory for frame buffer.$"

; ---- keyboard ----
prev_irq1_off    dw 0
prev_irq1_seg    dw 0
key_held_buf       times 128 db 0          ; 1 = held
key_last_buf        times 128 db 0          ; key_table of the previous frame

; ---- timer ----
prev_irq0_off    dw 0                    ; far pointer: offset FIRST, then segment
prev_irq0_seg    dw 0
sys_ticks      dw 0
prev_frame_tick       dw 0
pit_chain_acc        dw 0
sec_tick_acc         dw 0
stage_clock       dw STAGE_SECONDS
clock_halted    db 0

; ---- hero data ----
plr_x          dw 32                   ; world x, whole pixels
plr_sub_x         db 0                    ; x fraction (1/256 px)
plr_y          dw 160                  ; world y of the FEET
plr_sub_y         db 0
plr_vx         dw 0                    ; velocity, 8.8 signed
plr_vy         dw 0
plr_prev_y     dw 160                  ; feet y in the previous frame
plr_grounded       db 1
plr_dir          db 0                    ; 0 = right, 1 = left (mirror)
plr_anim_state       db 0                    ; 0 stand, 1 run, 2 jump
plr_power_tier            db 0                    ; 0 = Small, 1 = Super
plr_vitality              db 1
plr_mercy_cnt    dw 0
combo_hits     db 0
leap_btn_held       db 0
plr_is_dead      db 0
goal_reached    db 0
goal_hit_row        db 0
tile_bumped       db 0
bumped_col         dw 0
bumped_row         dw 0
clear_step       db 0                    ; 0 = sliding, 1 = walking
plr_hidden       db 0                    ; 1 = Mario entered the castle
view_px_x           dw 0
view_px_y           dw 0
blit_opts       dw 0

; ---- score / lives ----
plr_lives           db 3
coin_tally           db 0
pts_low        dw 0
pts_high        dw 0
clock_reward      dw 0
pts_ascii       db "000000", 0          ; ScoreToText fills these 6 digits
lives_ascii       db "3"
vitality_ascii          db "1"

; row:            0     1     2     3     4    5   6   7   8   9  10  11
pole_score_lut        dw 5000, 5000, 5000, 5000, 2000, 800, 400, 400, 100, 100, 100, 100
combo_score_lut       dw 100, 200, 400, 500, 800, 1000, 2000, 4000, 5000, 8000

; ---- game state ----
curr_phase      db PHASE_MENU
title_cursor        db 0                    ; 0 = START GAME, 1 = EXIT
phase_delay_cnt     dw 0

; jump table: order MUST match the GS_* numbers
phase_handlers     dw StateTitle, StatePlaying, StatePaused, StateDying
                dw StateLifeLost, StateWin, StateComplete, StateGameOver

; ---- texts (capital letters only: the font has no lowercase) ----
str_game_name       db "SUPER MARIO", 0
str_sub_name      db "ENGINE", 0
str_opt_play       db "START GAME", 0
str_opt_quit        db "EXIT", 0
str_credits        db "GROUP 00 TEAM NAMES", 0     ; EDIT: your group and names
str_hold_hdr      db "PAUSED", 0
str_hold_hint      db "PRESS P TO RESUME", 0
str_stage_hdr   db "WORLD 1-1", 0
str_rem_lives    db "LIVES LEFT", 0
str_stage_clear    db "LEVEL COMPLETE", 0
str_rem_time    db "TIME LEFT", 0
str_time_pts   db "TIME BONUS", 0
str_total_pts       db "FINAL SCORE", 0
str_next_prompt       db "PRESS ENTER TO CONTINUE", 0
str_defeat_hdr    db "GAME OVER", 0
str_menu_prompt  db "PRESS ENTER FOR TITLE", 0
hud_lbl_pts       db "SCORE", 0
hud_lbl_coins       db "COINS", 0
hud_lbl_stage       db "WORLD", 0
hud_lbl_clock        db "TIME", 0
hud_lbl_lives       db "LIVES", 0
hud_lbl_hp      db "HEALTH", 0
hud_val_stage       db "1-1", 0

; ---- enemies: one record = 16 bytes ----
%macro SPAWN_FOE 3
    db  %1, MODE_DORMANT             ; type, state
    dw  %2                      ; x
    db  0, 1                    ; xf, dir (1 = left)
    dw  %3                      ; y (top)
    db  0, 0                    ; yf, timer
    dw  0                       ; vy
    db  0, 0                    ; grace, spare
    dw  0                       ; padding to 16 bytes
%endmacro

foe_spawn_list:                     ; 4 Goombas + 2 Koopas, ground top = y 144
    SPAWN_FOE KIND_WALKER, 288, 144    ; near the start: stomp test
    SPAWN_FOE KIND_WALKER, 416, 144    ; right of pit 1: walks off the ledge
    SPAWN_FOE KIND_WALKER, 448, 144    ; stomp chain: two Goombas in one jump
    SPAWN_FOE KIND_TURTLE,  608, 144    ; right of pipe 2: turns at pipe + edge
    SPAWN_FOE KIND_WALKER, 752, 144    ; shell-kill target
    SPAWN_FOE KIND_TURTLE,  720, 144    ; stomp -> shell -> kick into the Goomba
    times 2*FOE_STRIDE db 0     ; two free slots (8 slots in total)

foe_pool         times FOE_SLOTS*FOE_STRIDE db 0
item_pool       times ITEM_SLOTS*ITEM_STRIDE db 0

; ---- tiles: colour per tile code 0..14 (placeholders, VGA palette) ----
;                 sky gnd brk ?c ?m emp pTL pTR pBL pBR stair coin flag wall door
cell_pal_lut     db   9,  6,  4, 14, 14,  8,  2,  2, 10, 10,   7,  15,  15,  8,   0

; ---- level map, 60 x 12, ASCII (one group = 10 columns) ----
; '0'sky '1'ground '2'brick '3'?coin '4'?mushroom '5'empty
; '6''7' pipe top  '8''9' pipe body  ':'stair  ';'coin  '<'flag
; '='castle wall  '>'castle door
base_grid_data:
    db "0000000000","0000000000","0000000000","0000000000","0000000000","0000000000"  ; row 0 (HUD)
    db "0000000000","0000000000","0000000000","0000000000","0000000000","0000000000"  ; row 1
    db "0000000000","0000000000","0000000000","0000000000","0000000000","000000<000"  ; row 2
    db "0000000000","0000000000","0000000000","0000000000","0000000000","000000<000"  ; row 3
    db "0000000000","0000000000","0000000000","0000000000","0000000000","000000<000"  ; row 4
    db "0000000000","0000000000","0000000000","00;;;00000","0000000000","000000<000"  ; row 5
    db "0000000000","4000232320","0000000000","0000000024","2320000000","0:0000<000"  ; row 6
    db "0000000000","0000000000","00;;;00000","0000006700","0000000000","::0000<0=="  ; row 7
    db "00000;;000","0000000000","0000000000","6700008900","00;;00000:","::0000<0=="  ; row 8
    db "0000000000","0000000000","0000000000","8900008900","00000000::","::0000:0>="  ; row 9
    times 22 db '1'             ; row 10: ground, pit cols 22-24,
    times 3  db '0'             ;         pit cols 42-43
    times 17 db '1'
    times 2  db '0'
    times 16 db '1'
    times 22 db '1'             ; row 11: same as row 10
    times 3  db '0'
    times 17 db '1'
    times 2  db '0'
    times 16 db '1'

live_grid_data        times GRID_BYTES db 0

; ---- 8x8 heart and font (38 glyphs x 8 bytes, MSB = left pixel) ----
bmp_heart_icon:          db 066h, 0FFh, 0FFh, 0FFh, 07Eh, 03Ch, 018h, 000h

bmp_charset:
    db 070h,088h,098h,0A8h,0C8h,088h,070h,000h   ; 0
    db 020h,060h,020h,020h,020h,020h,070h,000h   ; 1
    db 070h,088h,008h,010h,020h,040h,0F8h,000h   ; 2
    db 0F0h,008h,008h,070h,008h,008h,0F0h,000h   ; 3
    db 010h,030h,050h,090h,0F8h,010h,010h,000h   ; 4
    db 0F8h,080h,0F0h,008h,008h,088h,070h,000h   ; 5
    db 030h,040h,080h,0F0h,088h,088h,070h,000h   ; 6
    db 0F8h,008h,010h,020h,040h,040h,040h,000h   ; 7
    db 070h,088h,088h,070h,088h,088h,070h,000h   ; 8
    db 070h,088h,088h,078h,008h,010h,060h,000h   ; 9
    db 070h,088h,088h,0F8h,088h,088h,088h,000h   ; A
    db 0F0h,088h,088h,0F0h,088h,088h,0F0h,000h   ; B
    db 070h,088h,080h,080h,080h,088h,070h,000h   ; C
    db 0E0h,090h,088h,088h,088h,090h,0E0h,000h   ; D
    db 0F8h,080h,080h,0F0h,080h,080h,0F8h,000h   ; E
    db 0F8h,080h,080h,0F0h,080h,080h,080h,000h   ; F
    db 070h,088h,080h,0B8h,088h,088h,078h,000h   ; G
    db 088h,088h,088h,0F8h,088h,088h,088h,000h   ; H
    db 070h,020h,020h,020h,020h,020h,070h,000h   ; I
    db 038h,010h,010h,010h,010h,090h,060h,000h   ; J
    db 088h,090h,0A0h,0C0h,0A0h,090h,088h,000h   ; K
    db 080h,080h,080h,080h,080h,080h,0F8h,000h   ; L
    db 088h,0D8h,0A8h,0A8h,088h,088h,088h,000h   ; M
    db 088h,0C8h,0A8h,098h,088h,088h,088h,000h   ; N
    db 070h,088h,088h,088h,088h,088h,070h,000h   ; O
    db 0F0h,088h,088h,0F0h,080h,080h,080h,000h   ; P
    db 070h,088h,088h,088h,0A8h,090h,068h,000h   ; Q
    db 0F0h,088h,088h,0F0h,0A0h,090h,088h,000h   ; R
    db 078h,080h,080h,070h,008h,008h,0F0h,000h   ; S
    db 0F8h,020h,020h,020h,020h,020h,020h,000h   ; T
    db 088h,088h,088h,088h,088h,088h,070h,000h   ; U
    db 088h,088h,088h,088h,088h,050h,020h,000h   ; V
    db 088h,088h,088h,0A8h,0A8h,0D8h,088h,000h   ; W
    db 088h,088h,050h,020h,050h,088h,088h,000h   ; X
    db 088h,088h,050h,020h,020h,020h,020h,000h   ; Y
    db 0F8h,008h,010h,020h,040h,080h,0F8h,000h   ; Z
    db 000h,000h,000h,0F8h,000h,000h,000h,000h   ; -
    db 000h,000h,000h,000h,000h,000h,000h,000h   ; blank

; ---- sprites: 16 x 16, one hex digit per pixel (0 = transparent) ----
gfx_player:                   ; Small Mario standing (placeholder art)
    db "0000CCCCCC000000"
    db "000CCCCCCCCCC000"
    db "000666EEE6E00000"
    db "00666E6EEE6EEE00"
    db "00666EE6EEE6EEE0"
    db "0000EEEEEEE66600"
    db "000000EEEEEEE000"
    db "00CC1CCCCC000000"
    db "0CCC11CC11CCC000"
    db "CCCC1111111CCCC0"
    db "EEC1E1111E1CEE00"
    db "EEE111111111EEE0"
    db "EE1111111111EE00"
    db "0011110000111100"
    db "0666600000066600"
    db "6666600000066660"

gfx_walker:
    db "0000006666000000"
    db "0000666666660000"
    db "0006666666666000"
    db "0066666666666600"
    db "0666FF6666FF6660"
    db "0666666666666660"
    db "0066666666666600"
    db "0000EEEEEEEE0000"
    db "000EEEEEEEEEE000"
    db "000EEEEEEEEEE000"
    db "0000EEEEEEEE0000"
    db "0000066666600000"
    db "0888888008888880"
    db "0888888008888880"
    db "0000000000000000"
    db "0000000000000000"

gfx_walker_flat:                    ; flattened Goomba
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000066666600000"
    db "0006666666666000"
    db "0066FF6666FF6600"
    db "0666666666666660"
    db "0000EEEEEEEE0000"
    db "0888888008888880"

gfx_turtle:                   ; Koopa Troopa
    db "0000000AA0000000"
    db "000000AAAA000000"
    db "000000AFFA000000"
    db "000000AAAA000000"
    db "0000000EE0000000"
    db "000002AAAA200000"
    db "00002AAAAAA20000"
    db "0002AA2AA2AA2000"
    db "0002AAAAAAAA2000"
    db "0002AA2AA2AA2000"
    db "00002AAAAAA20000"
    db "0000022222200000"
    db "000000EEEE000000"
    db "00000EEEEEE00000"
    db "0000EE0000EE0000"
    db "0000EE0000EE0000"

gfx_carapace:                   ; Koopa shell
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000022222200000"
    db "0002AAAAAAAA2000"
    db "002AA2AAAA2AA200"
    db "002AAAAAAAAAA200"
    db "00FFFFFFFFFFFF00"
    db "000FFFFFFFFFF000"
    db "0000FFFFFFFF0000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"

gfx_powerup:
    db "00000CCCCCC00000"
    db "0000CCFFFFCCC000"
    db "000CCFFFFFFCCC00"
    db "00CCCFFFFFFCCCC0"
    db "00CCCCFFFFCCCCC0"
    db "00CFFCCCCCCFFCC0"
    db "00FFFCCCCCCFFFC0"
    db "00CFFCCCCCCFFCC0"
    db "000CCCCCCCCCC000"
    db "0000FFFFFFFF0000"
    db "000FF8FFFF8FF000"
    db "000FFFFFFFFFF000"
    db "0000FFFFFFFF0000"
    db "0000000000000000"
    db "0000000000000000"
    db "0000000000000000"

gfx_coin:
    db "0000000000000000"
    db "0000006666000000"
    db "000006EEEE600000"
    db "00006EEFFFE60000"
    db "0006EEFFEE6E6000"
    db "0006EEF66E6E6000"
    db "0006EEF66E6E6000"
    db "0006EEF66E6E6000"
    db "0006EEF66E6E6000"
    db "0006EEF66E6E6000"
    db "0006EEF66E6E6000"
    db "0006EEFFEE6E6000"
    db "00006EE666E60000"
    db "000006EEEE600000"
    db "0000006666000000"
    db "0000000000000000"
