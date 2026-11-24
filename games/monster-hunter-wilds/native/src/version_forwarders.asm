; SPDX-License-Identifier: GPL-3.0-or-later
; Tail forwarding preserves the original Windows x64 arguments and return ABI,
; including the undocumented GetFileVersionInfoByHandle signature.
EXTERN ghl_resolve_version_export:PROC
.code
FORWARD_VERSION MACRO symbol, index
PUBLIC symbol
symbol PROC FRAME
    sub rsp, 0A8h
    .allocstack 0A8h
    .endprolog
    mov [rsp+20h], rcx
    mov [rsp+28h], rdx
    mov [rsp+30h], r8
    mov [rsp+38h], r9
    movdqu [rsp+40h], xmm0
    movdqu [rsp+50h], xmm1
    movdqu [rsp+60h], xmm2
    movdqu [rsp+70h], xmm3
    mov ecx, index
    call ghl_resolve_version_export
    mov r11, rax
    mov rcx, [rsp+20h]
    mov rdx, [rsp+28h]
    mov r8, [rsp+30h]
    mov r9, [rsp+38h]
    movdqu xmm0, [rsp+40h]
    movdqu xmm1, [rsp+50h]
    movdqu xmm2, [rsp+60h]
    movdqu xmm3, [rsp+70h]
    add rsp, 0A8h
    jmp r11
symbol ENDP
ENDM
FORWARD_VERSION ghl_version_0, 0
FORWARD_VERSION ghl_version_1, 1
FORWARD_VERSION ghl_version_2, 2
FORWARD_VERSION ghl_version_3, 3
FORWARD_VERSION ghl_version_4, 4
FORWARD_VERSION ghl_version_5, 5
FORWARD_VERSION ghl_version_6, 6
FORWARD_VERSION ghl_version_7, 7
FORWARD_VERSION ghl_version_8, 8
FORWARD_VERSION ghl_version_9, 9
FORWARD_VERSION ghl_version_10, 10
FORWARD_VERSION ghl_version_11, 11
FORWARD_VERSION ghl_version_12, 12
FORWARD_VERSION ghl_version_13, 13
FORWARD_VERSION ghl_version_14, 14
FORWARD_VERSION ghl_version_15, 15
FORWARD_VERSION ghl_version_16, 16
END
