;*****************************************************************************
;* pixel.asm: h264 encoder library
;*****************************************************************************
;* Copyright (C) 2003-2008 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Laurent Aimar <fenrir@via.ecp.fr>
;*          Alex Izvorski <aizvorksi@gmail.com>
;*
;* This program is free software; you can redistribute it and/or modify
;* it under the terms of the GNU General Public License as published by
;* the Free Software Foundation; either version 2 of the License, or
;* (at your option) any later version.
;*
;* This program is distributed in the hope that it will be useful,
;* but WITHOUT ANY WARRANTY; without even the implied warranty of
;* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;* GNU General Public License for more details.
;*
;* You should have received a copy of the GNU General Public License
;* along with this program; if not, write to the Free Software
;* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111, USA.
;*****************************************************************************

%include "x86inc.asm"
%include "x86util.asm"

SECTION_RODATA
pw_1:    times 8 dw 1
ssim_c1: times 4 dd 416    ; .01*.01*255*255*64
ssim_c2: times 4 dd 235963 ; .03*.03*255*255*64*63
mask_ff: times 16 db 0xff
         times 16 db 0

SECTION .text

%macro HADDD 2 ; sum junk
%if mmsize == 16
    movhlps %2, %1
    paddd   %1, %2
    pshuflw %2, %1, 0xE
    paddd   %1, %2
%else
    mova    %2, %1
    psrlq   %2, 32
    paddd   %1, %2
%endif
%endmacro

%macro HADDW 2
    pmaddwd %1, [pw_1 GLOBAL]
    HADDD   %1, %2
%endmacro

;=============================================================================
; SSD
;=============================================================================

%macro SSD_FULL 6
    mova      m1, [r0+%1]
    mova      m2, [r2+%2]
    mova      m3, [r0+%3]
    mova      m4, [r2+%4]

    mova      m5, m2
    mova      m6, m4
    psubusb   m2, m1
    psubusb   m4, m3
    psubusb   m1, m5
    psubusb   m3, m6
    por       m1, m2
    por       m3, m4

    mova      m2, m1
    mova      m4, m3
    punpcklbw m1, m7
    punpcklbw m3, m7
    punpckhbw m2, m7
    punpckhbw m4, m7
    pmaddwd   m1, m1
    pmaddwd   m2, m2
    pmaddwd   m3, m3
    pmaddwd   m4, m4

%if %6
    lea       r0, [r0+2*r1]
    lea       r2, [r2+2*r3]
%endif
    paddd     m1, m2
    paddd     m3, m4
%if %5
    paddd     m0, m1
%else
    SWAP      m0, m1
%endif
    paddd     m0, m3
%endmacro

%macro SSD_HALF 6
    movh      m1, [r0+%1]
    movh      m2, [r2+%2]
    movh      m3, [r0+%3]
    movh      m4, [r2+%4]

    punpcklbw m1, m7
    punpcklbw m2, m7
    punpcklbw m3, m7
    punpcklbw m4, m7
    psubw     m1, m2
    psubw     m3, m4
    pmaddwd   m1, m1
    pmaddwd   m3, m3

%if %6
    lea       r0, [r0+2*r1]
    lea       r2, [r2+2*r3]
%endif
%if %5
    paddd     m0, m1
%else
    SWAP      m0, m1
%endif
    paddd     m0, m3
%endmacro

;-----------------------------------------------------------------------------
; int x264_pixel_ssd_16x16_mmx( uint8_t *, int, uint8_t *, int )
;-----------------------------------------------------------------------------
%macro SSD 3
cglobal x264_pixel_ssd_%1x%2_%3, 4,4
    pxor    m7, m7
%assign i 0
%rep %2/2
%if %1 > mmsize
    SSD_FULL 0,  0,     mmsize,    mmsize, i, 0
    SSD_FULL r1, r3, r1+mmsize, r3+mmsize, 1, i<%2/2-1
%elif %1 == mmsize
    SSD_FULL 0, 0, r1, r3, i, i<%2/2-1
%else
    SSD_HALF 0, 0, r1, r3, i, i<%2/2-1
%endif
%assign i i+1
%endrep
    HADDD   m0, m1
    movd   eax, m0
    RET
%endmacro

INIT_MMX
SSD 16, 16, mmx
SSD 16,  8, mmx
SSD  8, 16, mmx
SSD  8,  8, mmx
SSD  8,  4, mmx
SSD  4,  8, mmx
SSD  4,  4, mmx
INIT_XMM
SSD 16, 16, sse2
SSD 16,  8, sse2
SSD  8, 16, sse2
SSD  8,  8, sse2
SSD  8,  4, sse2


;=============================================================================
; variance
;=============================================================================

%macro VAR_START 0
    pxor  m5, m5    ; sum
    pxor  m6, m6    ; sum squared
    pxor  m7, m7    ; zero
%ifdef ARCH_X86_64
    %define t3d r3d
%else
    %define t3d r2d
%endif
%endmacro

%macro VAR_END 1
%if mmsize == 16
    movhlps m0, m5
    paddw   m5, m0
%endif
    movifnidn r2d, r2m
    movd   r1d, m5
    movd  [r2], m5  ; return sum
    imul   r1d, r1d
    HADDD   m6, m1
    shr    r1d, %1
    movd   eax, m6
    sub    eax, r1d  ; sqr - (sum * sum >> shift)
    RET
%endmacro

%macro VAR_2ROW 2
    mov      t3d, %2
.loop:
    mova      m0, [r0]
    mova      m1, m0
    mova      m3, [r0+%1]
    mova      m2, m0
    punpcklbw m0, m7
    mova      m4, m3
    punpckhbw m1, m7
%ifidn %1, r1
    lea       r0, [r0+%1*2]
%else
    add       r0, r1
%endif
    punpckhbw m4, m7
    psadbw    m2, m7
    paddw     m5, m2
    mova      m2, m3
    punpcklbw m3, m7
    dec t3d
    psadbw    m2, m7
    pmaddwd   m0, m0
    paddw     m5, m2
    pmaddwd   m1, m1
    paddd     m6, m0
    pmaddwd   m3, m3
    paddd     m6, m1
    pmaddwd   m4, m4
    paddd     m6, m3
    paddd     m6, m4
    jg .loop
%endmacro

;-----------------------------------------------------------------------------
; int x264_pixel_var_wxh_mmxext( uint8_t *, int, int * )
;-----------------------------------------------------------------------------
INIT_MMX
cglobal x264_pixel_var_16x16_mmxext, 2,3
    VAR_START
    VAR_2ROW 8, 16
    VAR_END 8

cglobal x264_pixel_var_8x8_mmxext, 2,3
    VAR_START
    VAR_2ROW r1, 4
    VAR_END 6

INIT_XMM
cglobal x264_pixel_var_16x16_sse2, 2,3
    VAR_START
    VAR_2ROW r1, 8
    VAR_END 8

cglobal x264_pixel_var_8x8_sse2, 2,3
    VAR_START
    mov t3d, 4
.loop:
    movh      m0, [r0]
    movhps    m0, [r0+r1]
    lea       r0, [r0+r1*2]
    mova      m1, m0
    punpcklbw m0, m7
    mova      m2, m1
    punpckhbw m1, m7
    dec t3d
    pmaddwd   m0, m0
    pmaddwd   m1, m1
    psadbw    m2, m7
    paddw     m5, m2
    paddd     m6, m0
    paddd     m6, m1
    jnz .loop
    VAR_END 6


;=============================================================================
; SATD
;=============================================================================

; phaddw is used only in 4x4 hadamard, because in 8x8 it's slower:
; even on Penryn, phaddw has latency 3 while paddw and punpck* have 1.
; 4x4 is special in that 4x4 transpose in xmmregs takes extra munging,
; whereas phaddw-based transform doesn't care what order the coefs end up in.

%macro PHSUMSUB 3
    movdqa m%3, m%1
    phaddw m%1, m%2
    phsubw m%3, m%2
    SWAP %2, %3
%endmacro

%macro HADAMARD4_ROW_PHADD 5
    PHSUMSUB %1, %2, %5
    PHSUMSUB %3, %4, %5
    PHSUMSUB %1, %3, %5
    PHSUMSUB %2, %4, %5
    SWAP %3, %4
%endmacro

%macro HADAMARD4_1D 4
    SUMSUB_BADC %1, %2, %3, %4
    SUMSUB_BADC %1, %3, %2, %4
%endmacro

%macro HADAMARD4x4_SUM 1    ; %1 = dest (row sum of one block)
    %xdefine %%n n%1
    HADAMARD4_1D  m4, m5, m6, m7
    TRANSPOSE4x4W  4,  5,  6,  7, %%n
    HADAMARD4_1D  m4, m5, m6, m7
    ABS2          m4, m5, m3, m %+ %%n
    ABS2          m6, m7, m3, m %+ %%n
    paddw         m6, m4
    paddw         m7, m5
    pavgw         m6, m7
    SWAP %%n, 6
%endmacro

; in: r4=3*stride1, r5=3*stride2
; in: %2 = horizontal offset
; in: %3 = whether we need to increment pix1 and pix2
; clobber: m3..m7
; out: %1 = satd
%macro SATD_4x4_MMX 3
    LOAD_DIFF m4, m3, none, [r0+%2],      [r2+%2]
    LOAD_DIFF m5, m3, none, [r0+r1+%2],   [r2+r3+%2]
    LOAD_DIFF m6, m3, none, [r0+2*r1+%2], [r2+2*r3+%2]
    LOAD_DIFF m7, m3, none, [r0+r4+%2],   [r2+r5+%2]
%if %3
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
%endif
    HADAMARD4x4_SUM %1
%endmacro

%macro SATD_8x4_START 1
    SATD_4x4_MMX m0, 0, 0
    SATD_4x4_MMX m1, 4, %1
%endmacro

%macro SATD_8x4_INC 1
    SATD_4x4_MMX m2, 0, 0
    paddw        m0, m1
    SATD_4x4_MMX m1, 4, %1
    paddw        m0, m2
%endmacro

%macro SATD_16x4_START 1
    SATD_4x4_MMX m0,  0, 0
    SATD_4x4_MMX m1,  4, 0
    SATD_4x4_MMX m2,  8, 0
    paddw        m0, m1
    SATD_4x4_MMX m1, 12, %1
    paddw        m0, m2
%endmacro

%macro SATD_16x4_INC 1
    SATD_4x4_MMX m2,  0, 0
    paddw        m0, m1
    SATD_4x4_MMX m1,  4, 0
    paddw        m0, m2
    SATD_4x4_MMX m2,  8, 0
    paddw        m0, m1
    SATD_4x4_MMX m1, 12, %1
    paddw        m0, m2
%endmacro

%macro SATD_8x4_SSE2 1
    LOAD_DIFF_8x4P  m0, m1, m2, m3, m4, m5
%if %1
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
%endif
    HADAMARD4_1D    m0, m1, m2, m3
    TRANSPOSE2x4x4W  0,  1,  2,  3,  4
    HADAMARD4_1D    m0, m1, m2, m3
    ABS4            m0, m1, m2, m3, m4, m5
    paddusw  m0, m1
    paddusw  m2, m3
    paddusw  m6, m0
    paddusw  m6, m2
%endmacro

%macro SATD_8x4_PHADD 1
    LOAD_DIFF_8x4P  m0, m1, m2, m3, m4, m5
%if %1
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
%endif
    HADAMARD4_1D    m0, m1, m2, m3
    HADAMARD4_ROW_PHADD 0, 1, 2, 3, 4
    ABS4            m0, m1, m2, m3, m4, m5
    paddusw  m0, m1
    paddusw  m2, m3
    paddusw  m6, m0
    paddusw  m6, m2
%endmacro

%macro SATD_START_MMX 0
    lea  r4, [3*r1] ; 3*stride1
    lea  r5, [3*r3] ; 3*stride2
%endmacro

%macro SATD_END_MMX 0
    pshufw      m1, m0, 01001110b
    paddw       m0, m1
    pshufw      m1, m0, 10110001b
    paddw       m0, m1
    movd       eax, m0
    and        eax, 0xffff
    RET
%endmacro

; FIXME avoid the spilling of regs to hold 3*stride.
; for small blocks on x86_32, modify pixel pointer instead.

;-----------------------------------------------------------------------------
; int x264_pixel_satd_16x16_mmxext (uint8_t *, int, uint8_t *, int )
;-----------------------------------------------------------------------------
INIT_MMX
cglobal x264_pixel_satd_16x16_mmxext, 4,6
    SATD_START_MMX
    SATD_16x4_START 1
    SATD_16x4_INC 1
    SATD_16x4_INC 1
    SATD_16x4_INC 0
    paddw       m0, m1
    pxor        m3, m3
    pshufw      m1, m0, 01001110b
    paddw       m0, m1
    punpcklwd   m0, m3
    pshufw      m1, m0, 01001110b
    paddd       m0, m1
    movd       eax, m0
    RET

cglobal x264_pixel_satd_16x8_mmxext, 4,6
    SATD_START_MMX
    SATD_16x4_START 1
    SATD_16x4_INC 0
    paddw  m0, m1
    SATD_END_MMX

cglobal x264_pixel_satd_8x16_mmxext, 4,6
    SATD_START_MMX
    SATD_8x4_START 1
    SATD_8x4_INC 1
    SATD_8x4_INC 1
    SATD_8x4_INC 0
    paddw  m0, m1
    SATD_END_MMX

cglobal x264_pixel_satd_8x8_mmxext, 4,6
    SATD_START_MMX
    SATD_8x4_START 1
    SATD_8x4_INC 0
    paddw  m0, m1
    SATD_END_MMX

cglobal x264_pixel_satd_8x4_mmxext, 4,6
    SATD_START_MMX
    SATD_8x4_START 0
    paddw  m0, m1
    SATD_END_MMX

%macro SATD_W4 1
cglobal x264_pixel_satd_4x8_%1, 4,6
    SATD_START_MMX
    SATD_4x4_MMX m0, 0, 1
    SATD_4x4_MMX m1, 0, 0
    paddw  m0, m1
    SATD_END_MMX

cglobal x264_pixel_satd_4x4_%1, 4,6
    SATD_START_MMX
    SATD_4x4_MMX m0, 0, 0
    SATD_END_MMX
%endmacro

SATD_W4 mmxext

%macro SATD_START_SSE2 0
    pxor    m6, m6
    lea     r4, [3*r1]
    lea     r5, [3*r3]
%endmacro

%macro SATD_END_SSE2 0
    psrlw   m6, 1
    HADDW   m6, m7
    movd   eax, m6
    RET
%endmacro

%macro BACKUP_POINTERS 0
%ifdef ARCH_X86_64
    mov    r10, r0
    mov    r11, r2
%endif
%endmacro

%macro RESTORE_AND_INC_POINTERS 0
%ifdef ARCH_X86_64
    lea     r0, [r10+8]
    lea     r2, [r11+8]
%else
    mov     r0, r0m
    mov     r2, r2m
    add     r0, 8
    add     r2, 8
%endif
%endmacro

;-----------------------------------------------------------------------------
; int x264_pixel_satd_8x4_sse2 (uint8_t *, int, uint8_t *, int )
;-----------------------------------------------------------------------------
%macro SATDS_SSE2 1
INIT_XMM
cglobal x264_pixel_satd_16x16_%1, 4,6
    SATD_START_SSE2
    BACKUP_POINTERS
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 0
    RESTORE_AND_INC_POINTERS
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 0
    SATD_END_SSE2

cglobal x264_pixel_satd_16x8_%1, 4,6
    SATD_START_SSE2
    BACKUP_POINTERS
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 0
    RESTORE_AND_INC_POINTERS
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 0
    SATD_END_SSE2

cglobal x264_pixel_satd_8x16_%1, 4,6
    SATD_START_SSE2
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 0
    SATD_END_SSE2

cglobal x264_pixel_satd_8x8_%1, 4,6
    SATD_START_SSE2
    SATD_8x4_SSE2 1
    SATD_8x4_SSE2 0
    SATD_END_SSE2

cglobal x264_pixel_satd_8x4_%1, 4,6
    SATD_START_SSE2
    SATD_8x4_SSE2 0
    SATD_END_SSE2

%ifdef ARCH_X86_64
;-----------------------------------------------------------------------------
; int x264_pixel_sa8d_8x8_sse2( uint8_t *, int, uint8_t *, int )
;-----------------------------------------------------------------------------
cglobal x264_pixel_sa8d_8x8_%1
    lea  r4, [3*r1]
    lea  r5, [3*r3]
.skip_lea:
    LOAD_DIFF_8x4P m0, m1, m2, m3, m8, m9
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
    LOAD_DIFF_8x4P m4, m5, m6, m7, m8, m9

    HADAMARD8_1D  m0, m1, m2, m3, m4, m5, m6, m7
    TRANSPOSE8x8W  0,  1,  2,  3,  4,  5,  6,  7,  8
    HADAMARD8_1D  m0, m1, m2, m3, m4, m5, m6, m7

    ABS4 m0, m1, m2, m3, m8, m9
    ABS4 m4, m5, m6, m7, m8, m9
    paddusw  m0, m1
    paddusw  m2, m3
    paddusw  m4, m5
    paddusw  m6, m7
    paddusw  m0, m2
    paddusw  m4, m6
    pavgw    m0, m4
    HADDW    m0, m1
    movd eax, m0
    add r10d, eax ; preserve rounding for 16x16
    add eax, 1
    shr eax, 1
    ret

cglobal x264_pixel_sa8d_16x16_%1
    xor  r10d, r10d
    call x264_pixel_sa8d_8x8_%1 ; pix[0]
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
    call x264_pixel_sa8d_8x8_%1.skip_lea ; pix[8*stride]
    neg  r4 ; it's already r1*3
    neg  r5
    lea  r0, [r0+4*r4+8]
    lea  r2, [r2+4*r5+8]
    call x264_pixel_sa8d_8x8_%1 ; pix[8]
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
    call x264_pixel_sa8d_8x8_%1.skip_lea ; pix[8*stride+8]
    mov  eax, r10d
    add  eax, 1
    shr  eax, 1
    ret
%else ; ARCH_X86_32
cglobal x264_pixel_sa8d_8x8_%1, 4,7
    mov  r6, esp
    and  esp, ~15
    sub  esp, 32
    lea  r4, [3*r1]
    lea  r5, [3*r3]
    LOAD_DIFF_8x4P m0, m1, m2, m3, m6, m7
    movdqa [esp], m2
    lea  r0, [r0+4*r1]
    lea  r2, [r2+4*r3]
    LOAD_DIFF_8x4P m4, m5, m6, m7, m2, m2
    movdqa m2, [esp]

    HADAMARD8_1D  m0, m1, m2, m3, m4, m5, m6, m7
    TRANSPOSE8x8W  0,  1,  2,  3,  4,  5,  6,  7, [esp], [esp+16]
    HADAMARD8_1D  m0, m1, m2, m3, m4, m5, m6, m7

%ifidn %1, sse2
    movdqa [esp], m4
    movdqa [esp+16], m2
%endif
    ABS2 m6, m3, m4, m2
    ABS2 m0, m7, m4, m2
    paddusw m0, m6
    paddusw m7, m3
%ifidn %1, sse2
    movdqa m4, [esp]
    movdqa m2, [esp+16]
%endif
    ABS2 m5, m1, m6, m3
    ABS2 m4, m2, m6, m3
    paddusw m5, m1
    paddusw m4, m2
    paddusw m0, m7
    paddusw m5, m4
    pavgw   m0, m5
    HADDW   m0, m7
    movd eax, m0
    mov  ecx, eax ; preserve rounding for 16x16
    add  eax, 1
    shr  eax, 1
    mov  esp, r6
    RET
%endif ; ARCH
%endmacro ; SATDS_SSE2

%macro SA8D_16x16_32 1
%ifndef ARCH_X86_64
cglobal x264_pixel_sa8d_16x16_%1
    push   ebp
    push   dword [esp+20]   ; stride2
    push   dword [esp+20]   ; pix2
    push   dword [esp+20]   ; stride1
    push   dword [esp+20]   ; pix1
    call x264_pixel_sa8d_8x8_%1
    mov    ebp, ecx
    add    dword [esp+0], 8 ; pix1+8
    add    dword [esp+8], 8 ; pix2+8
    call x264_pixel_sa8d_8x8_%1
    add    ebp, ecx
    mov    eax, [esp+4]
    mov    edx, [esp+12]
    shl    eax, 3
    shl    edx, 3
    add    [esp+0], eax     ; pix1+8*stride1+8
    add    [esp+8], edx     ; pix2+8*stride2+8
    call x264_pixel_sa8d_8x8_%1
    add    ebp, ecx
    sub    dword [esp+0], 8 ; pix1+8*stride1
    sub    dword [esp+8], 8 ; pix2+8*stride2
    call x264_pixel_sa8d_8x8_%1
    lea    eax, [ebp+ecx+1]
    shr    eax, 1
    add    esp, 16
    pop    ebp
    ret
%endif ; !ARCH_X86_64
%endmacro ; SA8D_16x16_32



;=============================================================================
; INTRA SATD
;=============================================================================

%macro INTRA_SA8D_SSE2 1
%ifdef ARCH_X86_64
INIT_XMM
;-----------------------------------------------------------------------------
; void x264_intra_sa8d_x3_8x8_core_sse2( uint8_t *fenc, int16_t edges[2][8], int *res )
;-----------------------------------------------------------------------------
cglobal x264_intra_sa8d_x3_8x8_core_%1
    ; 8x8 hadamard
    pxor        m8, m8
    movq        m0, [r0+0*FENC_STRIDE]
    movq        m1, [r0+1*FENC_STRIDE]
    movq        m2, [r0+2*FENC_STRIDE]
    movq        m3, [r0+3*FENC_STRIDE]
    movq        m4, [r0+4*FENC_STRIDE]
    movq        m5, [r0+5*FENC_STRIDE]
    movq        m6, [r0+6*FENC_STRIDE]
    movq        m7, [r0+7*FENC_STRIDE]
    punpcklbw   m0, m8
    punpcklbw   m1, m8
    punpcklbw   m2, m8
    punpcklbw   m3, m8
    punpcklbw   m4, m8
    punpcklbw   m5, m8
    punpcklbw   m6, m8
    punpcklbw   m7, m8
    HADAMARD8_1D  m0, m1, m2, m3, m4, m5, m6, m7
    TRANSPOSE8x8W  0,  1,  2,  3,  4,  5,  6,  7,  8
    HADAMARD8_1D  m0, m1, m2, m3, m4, m5, m6, m7

    ; dc
    movzx       edi, word [r1+0]
    add          di, word [r1+16]
    add         edi, 8
    and         edi, -16
    shl         edi, 2

    pxor        m15, m15
    movdqa      m8,  m2
    movdqa      m9,  m3
    movdqa      m10, m4
    movdqa      m11, m5
    ABS4        m8, m9, m10, m11, m12, m13
    paddusw     m8,  m10
    paddusw     m9,  m11
%ifidn %1, ssse3
    pabsw       m10, m6
    pabsw       m11, m7
    pabsw       m15, m1
%else
    movdqa      m10, m6
    movdqa      m11, m7
    movdqa      m15, m1
    ABS2        m10, m11, m13, m14
    ABS1        m15, m13
%endif
    paddusw     m10, m11
    paddusw     m8,  m9
    paddusw     m15, m10
    paddusw     m15, m8
    movdqa      m14, m15 ; 7x8 sum

    movdqa      m8,  [r1+0] ; left edge
    movd        m9,  edi
    psllw       m8,  3
    psubw       m8,  m0
    psubw       m9,  m0
    ABS1        m8,  m10
    ABS1        m9,  m11 ; 1x8 sum
    paddusw     m14, m8
    paddusw     m15, m9
    punpcklwd   m0,  m1
    punpcklwd   m2,  m3
    punpcklwd   m4,  m5
    punpcklwd   m6,  m7
    punpckldq   m0,  m2
    punpckldq   m4,  m6
    punpcklqdq  m0,  m4 ; transpose
    movdqa      m1,  [r1+16] ; top edge
    movdqa      m2,  m15
    psllw       m1,  3
    psrldq      m2,  2     ; 8x7 sum
    psubw       m0,  m1  ; 8x1 sum
    ABS1        m0,  m1
    paddusw     m2,  m0

    ; 3x HADDW
    movdqa      m7,  [pw_1 GLOBAL]
    pmaddwd     m2,  m7
    pmaddwd     m14, m7
    pmaddwd     m15, m7
    movdqa      m3,  m2
    punpckldq   m2,  m14
    punpckhdq   m3,  m14
    pshufd      m5,  m15, 0xf5
    paddd       m2,  m3
    paddd       m5,  m15
    movdqa      m3,  m2
    punpcklqdq  m2,  m5
    punpckhqdq  m3,  m5
    pavgw       m3,  m2
    pxor        m0,  m0
    pavgw       m3,  m0
    movq      [r2],  m3 ; i8x8_v, i8x8_h
    psrldq      m3,  8
    movd    [r2+8],  m3 ; i8x8_dc
    ret
%endif ; ARCH_X86_64
%endmacro ; INTRA_SA8D_SSE2

; in: r0 = fenc
; out: m0..m3 = hadamard coefs
INIT_MMX
ALIGN 16
load_hadamard:
    pxor        m7, m7
    movd        m0, [r0+0*FENC_STRIDE]
    movd        m1, [r0+1*FENC_STRIDE]
    movd        m2, [r0+2*FENC_STRIDE]
    movd        m3, [r0+3*FENC_STRIDE]
    punpcklbw   m0, m7
    punpcklbw   m1, m7
    punpcklbw   m2, m7
    punpcklbw   m3, m7
    HADAMARD4_1D  m0, m1, m2, m3
    TRANSPOSE4x4W  0,  1,  2,  3,  4
    HADAMARD4_1D  m0, m1, m2, m3
    SAVE_MM_PERMUTATION load_hadamard
    ret

%macro SCALAR_SUMSUB 4
    add %1, %2
    add %3, %4
    add %2, %2
    add %4, %4
    sub %2, %1
    sub %4, %3
%endmacro

%macro SCALAR_HADAMARD_LEFT 5 ; y, 4x tmp
%ifnidn %1, 0
    shl         %1d, 5 ; log(FDEC_STRIDE)
%endif
    movzx       %2d, byte [r1+%1-1+0*FDEC_STRIDE]
    movzx       %3d, byte [r1+%1-1+1*FDEC_STRIDE]
    movzx       %4d, byte [r1+%1-1+2*FDEC_STRIDE]
    movzx       %5d, byte [r1+%1-1+3*FDEC_STRIDE]
%ifnidn %1, 0
    shr         %1d, 5
%endif
    SCALAR_SUMSUB %2d, %3d, %4d, %5d
    SCALAR_SUMSUB %2d, %4d, %3d, %5d
    mov         [left_1d+2*%1+0], %2w
    mov         [left_1d+2*%1+2], %3w
    mov         [left_1d+2*%1+4], %4w
    mov         [left_1d+2*%1+6], %5w
%endmacro

%macro SCALAR_HADAMARD_TOP 5 ; x, 4x tmp
    movzx       %2d, byte [r1+%1-FDEC_STRIDE+0]
    movzx       %3d, byte [r1+%1-FDEC_STRIDE+1]
    movzx       %4d, byte [r1+%1-FDEC_STRIDE+2]
    movzx       %5d, byte [r1+%1-FDEC_STRIDE+3]
    SCALAR_SUMSUB %2d, %3d, %4d, %5d
    SCALAR_SUMSUB %2d, %4d, %3d, %5d
    mov         [top_1d+2*%1+0], %2w
    mov         [top_1d+2*%1+2], %3w
    mov         [top_1d+2*%1+4], %4w
    mov         [top_1d+2*%1+6], %5w
%endmacro

%macro SUM_MM_X3 8 ; 3x sum, 4x tmp, op
    pxor        %7, %7
    pshufw      %4, %1, 01001110b
    pshufw      %5, %2, 01001110b
    pshufw      %6, %3, 01001110b
    paddw       %1, %4
    paddw       %2, %5
    paddw       %3, %6
    punpcklwd   %1, %7
    punpcklwd   %2, %7
    punpcklwd   %3, %7
    pshufw      %4, %1, 01001110b
    pshufw      %5, %2, 01001110b
    pshufw      %6, %3, 01001110b
    %8          %1, %4
    %8          %2, %5
    %8          %3, %6
%endmacro

%macro CLEAR_SUMS 0
%ifdef ARCH_X86_64
    mov   qword [sums+0], 0
    mov   qword [sums+8], 0
    mov   qword [sums+16], 0
%else
    pxor  m7, m7
    movq  [sums+0], m7
    movq  [sums+8], m7
    movq  [sums+16], m7
%endif
%endmacro

; in: m1..m3
; out: m7
; clobber: m4..m6
%macro SUM3x4 1
%ifidn %1, ssse3
    pabsw       m4, m1
    pabsw       m5, m2
    pabsw       m7, m3
    paddw       m4, m5
%else
    movq        m4, m1
    movq        m5, m2
    ABS2        m4, m5, m6, m7
    movq        m7, m3
    paddw       m4, m5
    ABS1        m7, m6
%endif
    paddw       m7, m4
%endmacro

; in: m0..m3 (4x4), m7 (3x4)
; out: m0 v, m4 h, m5 dc
; clobber: m6
%macro SUM4x3 3 ; dc, left, top
    movq        m4, %2
    movd        m5, %1
    psllw       m4, 2
    psubw       m4, m0
    psubw       m5, m0
    punpcklwd   m0, m1
    punpcklwd   m2, m3
    punpckldq   m0, m2 ; transpose
    movq        m1, %3
    psllw       m1, 2
    psubw       m0, m1
    ABS2        m4, m5, m2, m3 ; 1x4 sum
    ABS1        m0, m1 ; 4x1 sum
%endmacro

%macro INTRA_SATDS_MMX 1
INIT_MMX
;-----------------------------------------------------------------------------
; void x264_intra_satd_x3_4x4_mmxext( uint8_t *fenc, uint8_t *fdec, int *res )
;-----------------------------------------------------------------------------
cglobal x264_intra_satd_x3_4x4_%1, 2,6
%ifdef ARCH_X86_64
    ; stack is 16 byte aligned because abi says so
    %define  top_1d  rsp-8  ; size 8
    %define  left_1d rsp-16 ; size 8
    %define  t0  r10
    %define  t0d r10d
%else
    ; stack is 16 byte aligned at least in gcc, and we've pushed 3 regs + return address, so it's still aligned
    SUB         esp, 16
    %define  top_1d  esp+8
    %define  left_1d esp
    %define  t0  r2
    %define  t0d r2d
%endif

    call load_hadamard
    SCALAR_HADAMARD_LEFT 0, r0, r3, r4, r5
    mov         t0d, r0d
    SCALAR_HADAMARD_TOP  0, r0, r3, r4, r5
    lea         t0d, [t0d + r0d + 4]
    and         t0d, -8
    shl         t0d, 1 ; dc

    SUM3x4 %1
    SUM4x3 t0d, [left_1d], [top_1d]
    paddw       m4, m7
    paddw       m5, m7
    movq        m1, m5
    psrlq       m1, 16  ; 4x3 sum
    paddw       m0, m1

    SUM_MM_X3   m0, m4, m5, m1, m2, m3, m6, pavgw
%ifndef ARCH_X86_64
    mov         r2, r2m
%endif
    movd        [r2+0], m0 ; i4x4_v satd
    movd        [r2+4], m4 ; i4x4_h satd
    movd        [r2+8], m5 ; i4x4_dc satd
%ifndef ARCH_X86_64
    ADD         esp, 16
%endif
    RET

%ifdef ARCH_X86_64
    %define  t0  r10
    %define  t0d r10d
    %define  t2  r11
    %define  t2w r11w
    %define  t2d r11d
%else
    %define  t0  r0
    %define  t0d r0d
    %define  t2  r2
    %define  t2w r2w
    %define  t2d r2d
%endif

;-----------------------------------------------------------------------------
; void x264_intra_satd_x3_16x16_mmxext( uint8_t *fenc, uint8_t *fdec, int *res )
;-----------------------------------------------------------------------------
cglobal x264_intra_satd_x3_16x16_%1, 0,7
%ifdef ARCH_X86_64
    %assign  stack_pad  88
%else
    %assign  stack_pad  88 + ((stack_offset+88+4)&15)
%endif
    ; not really needed on x86_64, just shuts up valgrind about storing data below the stack across a function call
    SUB         rsp, stack_pad
%define sums    rsp+64 ; size 24
%define top_1d  rsp+32 ; size 32
%define left_1d rsp    ; size 32
    movifnidn   r1d, r1m
    CLEAR_SUMS

    ; 1D hadamards
    xor         t2d, t2d
    mov         t0d, 12
.loop_edge:
    SCALAR_HADAMARD_LEFT t0, r3, r4, r5, r6
    add         t2d, r3d
    SCALAR_HADAMARD_TOP  t0, r3, r4, r5, r6
    add         t2d, r3d
    sub         t0d, 4
    jge .loop_edge
    shr         t2d, 1
    add         t2d, 8
    and         t2d, -16 ; dc

    ; 2D hadamards
    movifnidn   r0d, r0m
    xor         r3d, r3d
.loop_y:
    xor         r4d, r4d
.loop_x:
    call load_hadamard

    SUM3x4 %1
    SUM4x3 t2d, [left_1d+8*r3], [top_1d+8*r4]
    pavgw       m4, m7
    pavgw       m5, m7
    paddw       m0, [sums+0]  ; i16x16_v satd
    paddw       m4, [sums+8]  ; i16x16_h satd
    paddw       m5, [sums+16] ; i16x16_dc satd
    movq        [sums+0], m0
    movq        [sums+8], m4
    movq        [sums+16], m5

    add         r0, 4
    inc         r4d
    cmp         r4d, 4
    jl  .loop_x
    add         r0, 4*FENC_STRIDE-16
    inc         r3d
    cmp         r3d, 4
    jl  .loop_y

; horizontal sum
    movifnidn   r2d, r2m
    movq        m2, [sums+16]
    movq        m1, [sums+8]
    movq        m0, [sums+0]
    movq        m7, m2
    SUM_MM_X3   m0, m1, m2, m3, m4, m5, m6, paddd
    psrld       m0, 1
    pslld       m7, 16
    psrld       m7, 16
    paddd       m0, m2
    psubd       m0, m7
    movd        [r2+8], m2 ; i16x16_dc satd
    movd        [r2+4], m1 ; i16x16_h satd
    movd        [r2+0], m0 ; i16x16_v satd
    ADD         rsp, stack_pad
    RET

;-----------------------------------------------------------------------------
; void x264_intra_satd_x3_8x8c_mmxext( uint8_t *fenc, uint8_t *fdec, int *res )
;-----------------------------------------------------------------------------
cglobal x264_intra_satd_x3_8x8c_%1, 0,6
    ; not really needed on x86_64, just shuts up valgrind about storing data below the stack across a function call
    SUB          rsp, 72
%define  sums    rsp+48 ; size 24
%define  dc_1d   rsp+32 ; size 16
%define  top_1d  rsp+16 ; size 16
%define  left_1d rsp    ; size 16
    movifnidn   r1d, r1m
    CLEAR_SUMS

    ; 1D hadamards
    mov         t0d, 4
.loop_edge:
    SCALAR_HADAMARD_LEFT t0, t2, r3, r4, r5
    SCALAR_HADAMARD_TOP  t0, t2, r3, r4, r5
    sub         t0d, 4
    jge .loop_edge

    ; dc
    movzx       t2d, word [left_1d+0]
    movzx       r3d, word [top_1d+0]
    movzx       r4d, word [left_1d+8]
    movzx       r5d, word [top_1d+8]
    add         t2d, r3d
    lea         r3, [r4 + r5]
    lea         t2, [2*t2 + 8]
    lea         r3, [2*r3 + 8]
    lea         r4, [4*r4 + 8]
    lea         r5, [4*r5 + 8]
    and         t2d, -16 ; tl
    and         r3d, -16 ; br
    and         r4d, -16 ; bl
    and         r5d, -16 ; tr
    mov         [dc_1d+ 0], t2d ; tl
    mov         [dc_1d+ 4], r5d ; tr
    mov         [dc_1d+ 8], r4d ; bl
    mov         [dc_1d+12], r3d ; br
    lea         r5, [dc_1d]

    ; 2D hadamards
    movifnidn   r0d, r0m
    movifnidn   r2d, r2m
    xor         r3d, r3d
.loop_y:
    xor         r4d, r4d
.loop_x:
    call load_hadamard

    SUM3x4 %1
    SUM4x3 [r5+4*r4], [left_1d+8*r3], [top_1d+8*r4]
    pavgw       m4, m7
    pavgw       m5, m7
    paddw       m0, [sums+16] ; i4x4_v satd
    paddw       m4, [sums+8]  ; i4x4_h satd
    paddw       m5, [sums+0]  ; i4x4_dc satd
    movq        [sums+16], m0
    movq        [sums+8], m4
    movq        [sums+0], m5

    add         r0, 4
    inc         r4d
    cmp         r4d, 2
    jl  .loop_x
    add         r0, 4*FENC_STRIDE-8
    add         r5, 8
    inc         r3d
    cmp         r3d, 2
    jl  .loop_y

; horizontal sum
    movq        m0, [sums+0]
    movq        m1, [sums+8]
    movq        m2, [sums+16]
    movq        m7, m0
    psrlq       m7, 15
    paddw       m2, m7
    SUM_MM_X3   m0, m1, m2, m3, m4, m5, m6, paddd
    psrld       m2, 1
    movd        [r2+0], m0 ; i8x8c_dc satd
    movd        [r2+4], m1 ; i8x8c_h satd
    movd        [r2+8], m2 ; i8x8c_v satd
    ADD         rsp, 72
    RET
%endmacro ; INTRA_SATDS_MMX

; instantiate satds

%ifndef ARCH_X86_64
cextern x264_pixel_sa8d_8x8_mmxext
SA8D_16x16_32 mmxext
%endif

%define ABS1 ABS1_MMX
%define ABS2 ABS2_MMX
SATDS_SSE2 sse2
SA8D_16x16_32 sse2
INTRA_SA8D_SSE2 sse2
INTRA_SATDS_MMX mmxext
%define ABS1 ABS1_SSSE3
%define ABS2 ABS2_SSSE3
SATDS_SSE2 ssse3
SA8D_16x16_32 ssse3
INTRA_SA8D_SSE2 ssse3
INTRA_SATDS_MMX ssse3
SATD_W4 ssse3 ; mmx, but uses pabsw from ssse3.
%define SATD_8x4_SSE2 SATD_8x4_PHADD
SATDS_SSE2 ssse3_phadd



;=============================================================================
; SSIM
;=============================================================================

;-----------------------------------------------------------------------------
; void x264_pixel_ssim_4x4x2_core_sse2( const uint8_t *pix1, int stride1,
;                                       const uint8_t *pix2, int stride2, int sums[2][4] )
;-----------------------------------------------------------------------------
cglobal x264_pixel_ssim_4x4x2_core_sse2, 4,4
    pxor      m0, m0
    pxor      m1, m1
    pxor      m2, m2
    pxor      m3, m3
    pxor      m4, m4
%rep 4
    movq      m5, [r0]
    movq      m6, [r2]
    punpcklbw m5, m0
    punpcklbw m6, m0
    paddw     m1, m5
    paddw     m2, m6
    movdqa    m7, m5
    pmaddwd   m5, m5
    pmaddwd   m7, m6
    pmaddwd   m6, m6
    paddd     m3, m5
    paddd     m4, m7
    paddd     m3, m6
    add       r0, r1
    add       r2, r3
%endrep
    ; PHADDW m1, m2
    ; PHADDD m3, m4
    movdqa    m7, [pw_1 GLOBAL]
    pshufd    m5, m3, 0xb1
    pmaddwd   m1, m7
    pmaddwd   m2, m7
    pshufd    m6, m4, 0xb1
    packssdw  m1, m2
    paddd     m3, m5
    pshufd    m1, m1, 0xd8
    paddd     m4, m6
    pmaddwd   m1, m7
    movdqa    m5, m3
    punpckldq m3, m4
    punpckhdq m5, m4

%ifdef ARCH_X86_64
    %define t0 r4
%else
    %define t0 eax
    mov t0, r4m
%endif

    movq      [t0+ 0], m1
    movq      [t0+ 8], m3
    psrldq    m1, 8
    movq      [t0+16], m1
    movq      [t0+24], m5
    RET

;-----------------------------------------------------------------------------
; float x264_pixel_ssim_end_sse2( int sum0[5][4], int sum1[5][4], int width )
;-----------------------------------------------------------------------------
cglobal x264_pixel_ssim_end4_sse2, 3,3
    movdqa    m0, [r0+ 0]
    movdqa    m1, [r0+16]
    movdqa    m2, [r0+32]
    movdqa    m3, [r0+48]
    movdqa    m4, [r0+64]
    paddd     m0, [r1+ 0]
    paddd     m1, [r1+16]
    paddd     m2, [r1+32]
    paddd     m3, [r1+48]
    paddd     m4, [r1+64]
    paddd     m0, m1
    paddd     m1, m2
    paddd     m2, m3
    paddd     m3, m4
    movdqa    m5, [ssim_c1 GLOBAL]
    movdqa    m6, [ssim_c2 GLOBAL]
    TRANSPOSE4x4D  0, 1, 2, 3, 4

;   s1=m0, s2=m1, ss=m2, s12=m3
    movdqa    m4, m1
    pslld     m1, 16
    pmaddwd   m4, m0  ; s1*s2
    por       m0, m1
    pmaddwd   m0, m0  ; s1*s1 + s2*s2
    pslld     m4, 1
    pslld     m3, 7
    pslld     m2, 6
    psubd     m3, m4  ; covar*2
    psubd     m2, m0  ; vars
    paddd     m0, m5
    paddd     m4, m5
    paddd     m3, m6
    paddd     m2, m6
    cvtdq2ps  m0, m0  ; (float)(s1*s1 + s2*s2 + ssim_c1)
    cvtdq2ps  m4, m4  ; (float)(s1*s2*2 + ssim_c1)
    cvtdq2ps  m3, m3  ; (float)(covar*2 + ssim_c2)
    cvtdq2ps  m2, m2  ; (float)(vars + ssim_c2)
    mulps     m4, m3
    mulps     m0, m2
    divps     m4, m0  ; ssim

    cmp       r2d, 4
    je .skip ; faster only if this is the common case; remove branch if we use ssim on a macroblock level
    neg       r2
%ifdef PIC
    lea       r3, [mask_ff + 16 GLOBAL]
    movdqu    m1, [r3 + r2*4]
%else
    movdqu    m1, [mask_ff + r2*4 + 16 GLOBAL]
%endif
    pand      m4, m1
.skip:
    movhlps   m0, m4
    addps     m0, m4
    pshuflw   m4, m0, 0xE
    addss     m0, m4
%ifndef ARCH_X86_64
    movd     r0m, m0
    fld     dword r0m
%endif
    RET



;=============================================================================
; Successive Elimination ADS
;=============================================================================

%macro ADS_START 1 ; unroll_size
%ifdef ARCH_X86_64
    %define t0  r6
    mov     r10, rsp
%else
    %define t0  r4
    mov     rbp, rsp
%endif
    mov     r0d, r5m
    sub     rsp, r0
    sub     rsp, %1*4-1
    and     rsp, ~15
    mov     t0,  rsp
    shl     r2d,  1
%endmacro

%macro ADS_END 1
    add     r1, 8*%1
    add     r3, 8*%1
    add     t0, 4*%1
    sub     r0d, 4*%1
    jg .loop
    jmp ads_mvs
%endmacro

%define ABS1 ABS1_MMX

;-----------------------------------------------------------------------------
; int x264_pixel_ads4_mmxext( int enc_dc[4], uint16_t *sums, int delta,
;                             uint16_t *cost_mvx, int16_t *mvs, int width, int thresh )
;-----------------------------------------------------------------------------
cglobal x264_pixel_ads4_mmxext, 4,7
    movq    mm6, [r0]
    movq    mm4, [r0+8]
    pshufw  mm7, mm6, 0
    pshufw  mm6, mm6, 0xAA
    pshufw  mm5, mm4, 0
    pshufw  mm4, mm4, 0xAA
    ADS_START 1
.loop:
    movq    mm0, [r1]
    movq    mm1, [r1+16]
    psubw   mm0, mm7
    psubw   mm1, mm6
    ABS1    mm0, mm2
    ABS1    mm1, mm3
    movq    mm2, [r1+r2]
    movq    mm3, [r1+r2+16]
    psubw   mm2, mm5
    psubw   mm3, mm4
    paddw   mm0, mm1
    ABS1    mm2, mm1
    ABS1    mm3, mm1
    paddw   mm0, mm2
    paddw   mm0, mm3
%ifdef ARCH_X86_64
    pshufw  mm1, [r10+8], 0
%else
    pshufw  mm1, [ebp+stack_offset+28], 0
%endif
    paddusw mm0, [r3]
    psubusw mm1, mm0
    packsswb mm1, mm1
    movd    [t0], mm1
    ADS_END 1

cglobal x264_pixel_ads2_mmxext, 4,7
    movq    mm6, [r0]
    pshufw  mm5, r6m, 0
    pshufw  mm7, mm6, 0
    pshufw  mm6, mm6, 0xAA
    ADS_START 1
.loop:
    movq    mm0, [r1]
    movq    mm1, [r1+r2]
    psubw   mm0, mm7
    psubw   mm1, mm6
    ABS1    mm0, mm2
    ABS1    mm1, mm3
    paddw   mm0, mm1
    paddusw mm0, [r3]
    movq    mm4, mm5
    psubusw mm4, mm0
    packsswb mm4, mm4
    movd    [t0], mm4
    ADS_END 1

cglobal x264_pixel_ads1_mmxext, 4,7
    pshufw  mm7, [r0], 0
    pshufw  mm6, r6m, 0
    ADS_START 2
.loop:
    movq    mm0, [r1]
    movq    mm1, [r1+8]
    psubw   mm0, mm7
    psubw   mm1, mm7
    ABS1    mm0, mm2
    ABS1    mm1, mm3
    paddusw mm0, [r3]
    paddusw mm1, [r3+8]
    movq    mm4, mm6
    movq    mm5, mm6
    psubusw mm4, mm0
    psubusw mm5, mm1
    packsswb mm4, mm5
    movq    [t0], mm4
    ADS_END 2

%macro ADS_SSE2 1
cglobal x264_pixel_ads4_%1, 4,7
    movdqa  xmm4, [r0]
    pshuflw xmm7, xmm4, 0
    pshuflw xmm6, xmm4, 0xAA
    pshufhw xmm5, xmm4, 0
    pshufhw xmm4, xmm4, 0xAA
    punpcklqdq xmm7, xmm7
    punpcklqdq xmm6, xmm6
    punpckhqdq xmm5, xmm5
    punpckhqdq xmm4, xmm4
%ifdef ARCH_X86_64
    pshuflw xmm8, r6m, 0
    punpcklqdq xmm8, xmm8
    ADS_START 2
    movdqu  xmm10, [r1]
    movdqu  xmm11, [r1+r2]
.loop:
    movdqa  xmm0, xmm10
    movdqu  xmm1, [r1+16]
    movdqa  xmm10, xmm1
    psubw   xmm0, xmm7
    psubw   xmm1, xmm6
    ABS1    xmm0, xmm2
    ABS1    xmm1, xmm3
    movdqa  xmm2, xmm11
    movdqu  xmm3, [r1+r2+16]
    movdqa  xmm11, xmm3
    psubw   xmm2, xmm5
    psubw   xmm3, xmm4
    paddw   xmm0, xmm1
    movdqu  xmm9, [r3]
    ABS1    xmm2, xmm1
    ABS1    xmm3, xmm1
    paddw   xmm0, xmm2
    paddw   xmm0, xmm3
    paddusw xmm0, xmm9
    movdqa  xmm1, xmm8
    psubusw xmm1, xmm0
    packsswb xmm1, xmm1
    movq    [t0], xmm1
%else
    ADS_START 2
.loop:
    movdqu  xmm0, [r1]
    movdqu  xmm1, [r1+16]
    psubw   xmm0, xmm7
    psubw   xmm1, xmm6
    ABS1    xmm0, xmm2
    ABS1    xmm1, xmm3
    movdqu  xmm2, [r1+r2]
    movdqu  xmm3, [r1+r2+16]
    psubw   xmm2, xmm5
    psubw   xmm3, xmm4
    paddw   xmm0, xmm1
    ABS1    xmm2, xmm1
    ABS1    xmm3, xmm1
    paddw   xmm0, xmm2
    paddw   xmm0, xmm3
    movd    xmm1, [ebp+stack_offset+28]
    movdqu  xmm2, [r3]
    pshuflw xmm1, xmm1, 0
    punpcklqdq xmm1, xmm1
    paddusw xmm0, xmm2
    psubusw xmm1, xmm0
    packsswb xmm1, xmm1
    movq    [t0], xmm1
%endif ; ARCH
    ADS_END 2

cglobal x264_pixel_ads2_%1, 4,7
    movq    xmm6, [r0]
    movd    xmm5, r6m
    pshuflw xmm7, xmm6, 0
    pshuflw xmm6, xmm6, 0xAA
    pshuflw xmm5, xmm5, 0
    punpcklqdq xmm7, xmm7
    punpcklqdq xmm6, xmm6
    punpcklqdq xmm5, xmm5
    ADS_START 2
.loop:
    movdqu  xmm0, [r1]
    movdqu  xmm1, [r1+r2]
    psubw   xmm0, xmm7
    psubw   xmm1, xmm6
    movdqu  xmm4, [r3]
    ABS1    xmm0, xmm2
    ABS1    xmm1, xmm3
    paddw   xmm0, xmm1
    paddusw xmm0, xmm4
    movdqa  xmm1, xmm5
    psubusw xmm1, xmm0
    packsswb xmm1, xmm1
    movq    [t0], xmm1
    ADS_END 2

cglobal x264_pixel_ads1_%1, 4,7
    movd    xmm7, [r0]
    movd    xmm6, r6m
    pshuflw xmm7, xmm7, 0
    pshuflw xmm6, xmm6, 0
    punpcklqdq xmm7, xmm7
    punpcklqdq xmm6, xmm6
    ADS_START 4
.loop:
    movdqu  xmm0, [r1]
    movdqu  xmm1, [r1+16]
    psubw   xmm0, xmm7
    psubw   xmm1, xmm7
    movdqu  xmm2, [r3]
    movdqu  xmm3, [r3+16]
    ABS1    xmm0, xmm4
    ABS1    xmm1, xmm5
    paddusw xmm0, xmm2
    paddusw xmm1, xmm3
    movdqa  xmm4, xmm6
    movdqa  xmm5, xmm6
    psubusw xmm4, xmm0
    psubusw xmm5, xmm1
    packsswb xmm4, xmm5
    movdqa  [t0], xmm4
    ADS_END 4
%endmacro

ADS_SSE2 sse2
%define ABS1 ABS1_SSSE3
ADS_SSE2 ssse3

; int x264_pixel_ads_mvs( int16_t *mvs, uint8_t *masks, int width )
; {
;     int nmv=0, i, j;
;     *(uint32_t*)(masks+width) = 0;
;     for( i=0; i<width; i+=8 )
;     {
;         uint64_t mask = *(uint64_t*)(masks+i);
;         if( !mask ) continue;
;         for( j=0; j<8; j++ )
;             if( mask & (255<<j*8) )
;                 mvs[nmv++] = i+j;
;     }
;     return nmv;
; }
cglobal x264_pixel_ads_mvs
ads_mvs:
    xor     eax, eax
    xor     esi, esi
%ifdef ARCH_X86_64
    ; mvs = r4
    ; masks = rsp
    ; width = r5
    ; clear last block in case width isn't divisible by 8. (assume divisible by 4, so clearing 4 bytes is enough.)
    mov     dword [rsp+r5], 0
    jmp .loopi
.loopi0:
    add     esi, 8
    cmp     esi, r5d
    jge .end
.loopi:
    mov     rdi, [rsp+rsi]
    test    rdi, rdi
    jz .loopi0
    xor     ecx, ecx
%macro TEST 1
    mov     [r4+rax*2], si
    test    edi, 0xff<<(%1*8)
    setne   cl
    add     eax, ecx
    inc     esi
%endmacro
    TEST 0
    TEST 1
    TEST 2
    TEST 3
    shr     rdi, 32
    TEST 0
    TEST 1
    TEST 2
    TEST 3
    cmp     esi, r5d
    jl .loopi
.end:
    mov     rsp, r10
    ret

%else
    ; no PROLOGUE, inherit from x264_pixel_ads1
    mov     ebx, [ebp+stack_offset+20] ; mvs
    mov     edi, [ebp+stack_offset+24] ; width
    mov     dword [esp+edi], 0
    push    ebp
    jmp .loopi
.loopi0:
    add     esi, 8
    cmp     esi, edi
    jge .end
.loopi:
    mov     ebp, [esp+esi+4]
    mov     edx, [esp+esi+8]
    mov     ecx, ebp
    or      ecx, edx
    jz .loopi0
    xor     ecx, ecx
%macro TEST 2
    mov     [ebx+eax*2], si
    test    %2, 0xff<<(%1*8)
    setne   cl
    add     eax, ecx
    inc     esi
%endmacro
    TEST 0, ebp
    TEST 1, ebp
    TEST 2, ebp
    TEST 3, ebp
    TEST 0, edx
    TEST 1, edx
    TEST 2, edx
    TEST 3, edx
    cmp     esi, edi
    jl .loopi
.end:
    pop     esp
    RET
%endif ; ARCH

