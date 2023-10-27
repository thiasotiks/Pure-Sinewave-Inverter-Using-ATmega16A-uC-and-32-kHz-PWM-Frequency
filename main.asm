; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ATmega16A_SPWM_32k_basic ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

; This code is under MIT License
; Copyright (c) 2023 Sayantan Sinha
;
#define invStatus r24
#define INVZC invStatus, 5

.equ tableStart = 0x0100
.equ tableEnd = 0x0238

.org 0x0
jmp init_io

.org OVF0addr
jmp timer0_ovf_isr

.org 0x0090
init_io:
  ldi r16, LOW(RAMEND)        ; Inialize the Stack Pointer with the last address of the RAM
  out spl, r16                ; SP low byte = RAM_END low byte
  ldi r16, HIGH(RAMEND)
  out sph, r16                ; SP high byte = RAM_END high byte

  sbi DDRB,0                  ; Set PB0 (pin# 1) as output
  sbi DDRB,3                  ; Set PB3(OC0) (pin# 4) as output
  sbi DDRD,4                  ; Set PD4(OC1B) (pin# 19) as output
  sbi DDRD,5                  ; Set PD5(OC1A) (pin# 18) as output
  sbi DDRD,7                  ; Set PD7(OC2) (pin# 21) as output
  cli                         ; Disable global interrupts

  rcall load_lookup           ; Load the lookup table into the SRAM 
  call init_tc_spwm

loopinf:
  ldi r18,0b00000001          ; Bit pattern to toggle PB0 by XOR operation
  blink_led:
    in r19,PORTB              ; R19 = PORTB
    eor r19,r18               ; R19 = R19 XOR R18
    out PORTB,r19             ; PORTB = R19
    rcall delay1ms            ; Delay 1 ms
    rjmp blink_led            ; Goto blink_led loop
    
  rjmp loopinf

init_tc_spwm:
  ldi r16,0
  ldi r17,4
  ldi r18,6
  out TCNT0,r16
  out TCNT1L,r17              ; To synchronize Timer1 with Timer0
  out TCNT2,r18               ; To synchronize Timer2 with Timer0
  
  ldi r16,0b01000001          ; TCCR0: FOC0 WGM00 COM01 COM00 WGM01 CS02 CS01 CS00 (DS_ATmega16A, p. 79)
  out TCCR0,r16               ; Phase Correct PWM, OC0 Disconnected, No Prescaling (DS_ATmega16A, pp. 80-81)

  ldi r17, 0b00000001         ; TCCR1A: COM1A1 COM1A0 COM1B1 COM1B0 FOC1A FOC1B WGM11 WGM10 (DS_ATmega16A, p. 105)
  out TCCR1A, r17             ; OC1A & OC1B Disconnected, PWM, Phase Correct, 8-bit
  ldi r18, 0b00000001         ; TCCR1B: ICNC1 ICES1 - WGM13 WGM12 CS12 CS11 CS10
  out TCCR1B, r18             ; No Prescaling

  ldi r19, 0b01000001         ; TCCR2: FOC2 WGM20 COM21 COM20 WGM21 CS22 CS21 CS20 (DS_ATmega16A, p. 125)
  out TCCR2, r19              ; Phase Correct PWM, OC2 Disconnected, No Prescaling (DS_ATmega16A, p. 125)
  
  ldi r20, 0
  out OCR0, r20               ; OCR0 = 0
  out OCR2, r20               ; OCR2 = 0
  
  ldi r20, 4
  out OCR1AL, r20             ; OCR1A = 4
  out OCR1BL, r20             ; OCR1B = 4

  ori r16, 0b00100000         ; Load bit pattern for: Clear OC0 on compare match when up-counting
  ori r17, 0b11000000         ; Load bit pattern for: Set OC1A on compare match when up-counting, OC1B Disconnected
  out TCCR0, r16
  out TCCR1A, r17
  sei                         ; Global interrupt enable
  ldi r16, 0b00000001         ; Load bit pattern for Timer0 Overflow Interrupt Enable
  out TIMSK, r16              ; TIMSK: OCIE2 TOIE2 TICIE1 OCIE1A OCIE1B TOIE1 OCIE0 TOIE0 (DS_ATmega16A, p.82)
  ret

timer0_ovf_isr:
;  push	r1
;  push r0
;  in	r0, sreg ;0x3f	; 63
;  push	r0
;  eor	r1, r1

  ld r16, x+                  ; Load duty cycle from SRAM and increament the X ptr.
  out OCR0, r16               ; Load duty cycle to OCR0
  out OCR2, r16               ; Load duty cycle to OCR2
  subi r16, 252               ; r16 = r16 - (-4)
  out OCR1AL, r16             ; OCR1A = OCR0 + 4 (4 is for dead-time)
  out OCR1BL, r16             ; OCR1B = OCR2 + 4 (4 is for dead-time)
   
  ;sbrs INVZC                  ; If INVZC = 0 then Goto test_invzc
  ;rjmp test_invzc             ; else Alter half-cycle
 
  cpi r26, 0x01               ; If X = 0x0101 then Alter half-cycle
  brne test_invzc             ; else Goto test_invzc
  cpi r27, 0x01
  brne test_invzc

  ;cbr INVZC                   ; INVZC = 0
  in r16, TCCR0
  sbrc r16, 5                 ; If OC0 is disconnected (bit-5 @ TCCR0 = 0) then goto pos_half
  rjmp neg_half
  pos_half:
    ldi r16, 0b01100001       ; bit pattern: OC0 Clear on compare match when up-counting
    ldi r17, 0b11000001       ; bit pattern: OC1A Set on Compare match when up-counting, OC1B Disconnected
    ldi r18, 0b01000001       ; bit pattern: OC2 Disconnected
    out TCCR2, r18            ; OC2 Disconnected
    out TCCR1A, r17           ; OC1A Set on Compare match when up-counting, OC1B Disconnected
    out TCCR0, r16            ; OC0 Clear on compare match when up-counting
    sbi PORTD, 4              ; OC1B = High
    reti
  neg_half:
    ldi r16, 0b01000001       ; bit pattern: OC0 Disconnected
    ldi r17, 0b00110001       ; bit pattern: OC1A Disconnected, OC1B Set on Compare match when up-counting
    ldi r18, 0b01100001       ; bit pattern: OC2 Clear on compare match when up-counting
    out TCCR0, r16            ; OC0 Disconnected
    out TCCR1A, r17           ; OC1A Disconnected, OC1B Set on Compare match when up-counting
    out TCCR2, r18            ; OC2 Clear on compare match when up-counting
    sbi PORTD, 5              ; OC1A = High
    reti
  test_invzc:
    ldi r16, 0x39             ; Test if X = 0x0239 (End of look up table)
    ldi r17, 0x02
    cpse r16, r26             ; R26 = 0x39 ?
    reti                      ; No : Return
    cpse r17, r27             ; Yes: R27 = 0x02 ?
    reti                      ; No : Return
  reset_lt_ptr:               ; Yes:  Reset look up table ptr
    ldi r26, 0x00             ; Reset X ptr with the starting addr of Lookup table (SRAM addr: 0x0100)
    ldi r27, 0x01             ; Indirect memory pointer X -> 0x0100
    ;sbr INVZC                 ; INVZC = 1

;  pop	r0
;  out	sreg, r0	; 63
;  pop	r0
;  pop	r1
  reti                        ; Return from interrupt

delay1ms:
  ldi r17,99                  ; R17 = 100 (T_delay = ((r16 * 3 - 1 + 4) * r17 - 1) * 62.5 ns)
  dly_loop2:                  ; Each loop will take ((r16 * 3 - 1) + 4) T_clks
    ldi r16,53                ; R16 = 53
    dly_loop1:                ; Each loop will take 3 T_clks if (R16 - 1) > 0 or 2 T_clks if (R16 - 1) = 0)
      dec r16                 ; R16 = R16 - 1
      brne dly_loop1          ; If (R16 - 1) > 0 then goto dly_loop1
    dec r17                   ; R17 = R17 - 1
    brne dly_loop2            ; If (R17 - 1) > 0 then goto dly_loop2
  ret

load_lookup:
  ldi r26,0x00                ; Lookup table starts from SRAM address: 0x0100
  ldi r27,0x01                ; Indirect memory pointer X -> 0x0100
  
  ldi r16,0                   ; #Entry = 313 @ 0x0100 to 0x0238
  st x+,r16
  ldi r16,3
  st x+,r16
  ldi r16,5
  st x+,r16
  ldi r16,8
  st x+,r16
  ldi r16,10
  st x+,r16
  ldi r16,13
  st x+,r16
  ldi r16,15
  st x+,r16
  ldi r16,18
  st x+,r16
  ldi r16,20
  st x+,r16
  ldi r16,23
  st x+,r16
  ldi r16,25
  st x+,r16
  ldi r16,28
  st x+,r16
  ldi r16,30
  st x+,r16
  ldi r16,33
  st x+,r16
  ldi r16,35
  st x+,r16
  ldi r16,37
  st x+,r16
  ldi r16,40
  st x+,r16
  ldi r16,42
  st x+,r16
  ldi r16,45
  st x+,r16
  ldi r16,47
  st x+,r16
  ldi r16,50
  st x+,r16
  ldi r16,52
  st x+,r16
  ldi r16,55
  st x+,r16
  ldi r16,57
  st x+,r16
  ldi r16,60
  st x+,r16
  ldi r16,62
  st x+,r16
  ldi r16,65
  st x+,r16
  ldi r16,67
  st x+,r16
  ldi r16,69
  st x+,r16
  ldi r16,72
  st x+,r16
  ldi r16,74
  st x+,r16
  ldi r16,77
  st x+,r16
  ldi r16,79
  st x+,r16
  ldi r16,81
  st x+,r16
  ldi r16,84
  st x+,r16
  ldi r16,86
  st x+,r16
  ldi r16,88
  st x+,r16
  ldi r16,91
  st x+,r16
  ldi r16,93
  st x+,r16
  ldi r16,95
  st x+,r16
  ldi r16,98
  st x+,r16
  ldi r16,100
  st x+,r16
  ldi r16,102
  st x+,r16
  ldi r16,105
  st x+,r16
  ldi r16,107
  st x+,r16
  ldi r16,109
  st x+,r16
  ldi r16,111
  st x+,r16
  ldi r16,114
  st x+,r16
  ldi r16,116
  st x+,r16
  ldi r16,118
  st x+,r16
  ldi r16,120
  st x+,r16
  ldi r16,122
  st x+,r16
  ldi r16,125
  st x+,r16
  ldi r16,127
  st x+,r16
  ldi r16,129
  st x+,r16
  ldi r16,131
  st x+,r16
  ldi r16,133
  st x+,r16
  ldi r16,135
  st x+,r16
  ldi r16,137
  st x+,r16
  ldi r16,140
  st x+,r16
  ldi r16,142
  st x+,r16
  ldi r16,144
  st x+,r16
  ldi r16,146
  st x+,r16
  ldi r16,148
  st x+,r16
  ldi r16,150
  st x+,r16
  ldi r16,152
  st x+,r16
  ldi r16,154
  st x+,r16
  ldi r16,156
  st x+,r16
  ldi r16,158
  st x+,r16
  ldi r16,160
  st x+,r16
  ldi r16,162
  st x+,r16
  ldi r16,163
  st x+,r16
  ldi r16,165
  st x+,r16
  ldi r16,167
  st x+,r16
  ldi r16,169
  st x+,r16
  ldi r16,171
  st x+,r16
  ldi r16,173
  st x+,r16
  ldi r16,175
  st x+,r16
  ldi r16,176
  st x+,r16
  ldi r16,178
  st x+,r16
  ldi r16,180
  st x+,r16
  ldi r16,182
  st x+,r16
  ldi r16,183
  st x+,r16
  ldi r16,185
  st x+,r16
  ldi r16,187
  st x+,r16
  ldi r16,188
  st x+,r16
  ldi r16,190
  st x+,r16
  ldi r16,192
  st x+,r16
  ldi r16,193
  st x+,r16
  ldi r16,195
  st x+,r16
  ldi r16,196
  st x+,r16
  ldi r16,198
  st x+,r16
  ldi r16,199
  st x+,r16
  ldi r16,201
  st x+,r16
  ldi r16,202
  st x+,r16
  ldi r16,204
  st x+,r16
  ldi r16,205
  st x+,r16
  ldi r16,207
  st x+,r16
  ldi r16,208
  st x+,r16
  ldi r16,210
  st x+,r16
  ldi r16,211
  st x+,r16
  ldi r16,212
  st x+,r16
  ldi r16,214
  st x+,r16
  ldi r16,215
  st x+,r16
  ldi r16,216
  st x+,r16
  ldi r16,217
  st x+,r16
  ldi r16,219
  st x+,r16
  ldi r16,220
  st x+,r16
  ldi r16,221
  st x+,r16
  ldi r16,222
  st x+,r16
  ldi r16,223
  st x+,r16
  ldi r16,224
  st x+,r16
  ldi r16,225
  st x+,r16
  ldi r16,227
  st x+,r16
  ldi r16,228
  st x+,r16
  ldi r16,229
  st x+,r16
  ldi r16,230
  st x+,r16
  ldi r16,231
  st x+,r16
  ldi r16,232
  st x+,r16
  ldi r16,232
  st x+,r16
  ldi r16,233
  st x+,r16
  ldi r16,234
  st x+,r16
  ldi r16,235
  st x+,r16
  ldi r16,236
  st x+,r16
  ldi r16,237
  st x+,r16
  ldi r16,238
  st x+,r16
  ldi r16,238
  st x+,r16
  ldi r16,239
  st x+,r16
  ldi r16,240
  st x+,r16
  ldi r16,241
  st x+,r16
  ldi r16,241
  st x+,r16
  ldi r16,242
  st x+,r16
  ldi r16,242
  st x+,r16
  ldi r16,243
  st x+,r16
  ldi r16,244
  st x+,r16
  ldi r16,244
  st x+,r16
  ldi r16,245
  st x+,r16
  ldi r16,245
  st x+,r16
  ldi r16,246
  st x+,r16
  ldi r16,246
  st x+,r16
  ldi r16,247
  st x+,r16
  ldi r16,247
  st x+,r16
  ldi r16,247
  st x+,r16
  ldi r16,248
  st x+,r16
  ldi r16,248
  st x+,r16
  ldi r16,248
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249                     ; 250 -> 249 (No pulse @250 after feeding into H-bridge)
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,249
  st x+,r16
  ldi r16,248
  st x+,r16
  ldi r16,248
  st x+,r16
  ldi r16,248
  st x+,r16
  ldi r16,247
  st x+,r16
  ldi r16,247
  st x+,r16
  ldi r16,247
  st x+,r16
  ldi r16,246
  st x+,r16
  ldi r16,246
  st x+,r16
  ldi r16,245
  st x+,r16
  ldi r16,245
  st x+,r16
  ldi r16,244
  st x+,r16
  ldi r16,244
  st x+,r16
  ldi r16,243
  st x+,r16
  ldi r16,242
  st x+,r16
  ldi r16,242
  st x+,r16
  ldi r16,241
  st x+,r16
  ldi r16,241
  st x+,r16
  ldi r16,240
  st x+,r16
  ldi r16,239
  st x+,r16
  ldi r16,238
  st x+,r16
  ldi r16,238
  st x+,r16
  ldi r16,237
  st x+,r16
  ldi r16,236
  st x+,r16
  ldi r16,235
  st x+,r16
  ldi r16,234
  st x+,r16
  ldi r16,233
  st x+,r16
  ldi r16,232
  st x+,r16
  ldi r16,232
  st x+,r16
  ldi r16,231
  st x+,r16
  ldi r16,230
  st x+,r16
  ldi r16,229
  st x+,r16
  ldi r16,228
  st x+,r16
  ldi r16,227
  st x+,r16
  ldi r16,225
  st x+,r16
  ldi r16,224
  st x+,r16
  ldi r16,223
  st x+,r16
  ldi r16,222
  st x+,r16
  ldi r16,221
  st x+,r16
  ldi r16,220
  st x+,r16
  ldi r16,219
  st x+,r16
  ldi r16,217
  st x+,r16
  ldi r16,216
  st x+,r16
  ldi r16,215
  st x+,r16
  ldi r16,214
  st x+,r16
  ldi r16,212
  st x+,r16
  ldi r16,211
  st x+,r16
  ldi r16,210
  st x+,r16
  ldi r16,208
  st x+,r16
  ldi r16,207
  st x+,r16
  ldi r16,205
  st x+,r16
  ldi r16,204
  st x+,r16
  ldi r16,202
  st x+,r16
  ldi r16,201
  st x+,r16
  ldi r16,199
  st x+,r16
  ldi r16,198
  st x+,r16
  ldi r16,196
  st x+,r16
  ldi r16,195
  st x+,r16
  ldi r16,193
  st x+,r16
  ldi r16,192
  st x+,r16
  ldi r16,190
  st x+,r16
  ldi r16,188
  st x+,r16
  ldi r16,187
  st x+,r16
  ldi r16,185
  st x+,r16
  ldi r16,183
  st x+,r16
  ldi r16,182
  st x+,r16
  ldi r16,180
  st x+,r16
  ldi r16,178
  st x+,r16
  ldi r16,176
  st x+,r16
  ldi r16,175
  st x+,r16
  ldi r16,173
  st x+,r16
  ldi r16,171
  st x+,r16
  ldi r16,169
  st x+,r16
  ldi r16,167
  st x+,r16
  ldi r16,165
  st x+,r16
  ldi r16,163
  st x+,r16
  ldi r16,162
  st x+,r16
  ldi r16,160
  st x+,r16
  ldi r16,158
  st x+,r16
  ldi r16,156
  st x+,r16
  ldi r16,154
  st x+,r16
  ldi r16,152
  st x+,r16
  ldi r16,150
  st x+,r16
  ldi r16,148
  st x+,r16
  ldi r16,146
  st x+,r16
  ldi r16,144
  st x+,r16
  ldi r16,142
  st x+,r16
  ldi r16,140
  st x+,r16
  ldi r16,137
  st x+,r16
  ldi r16,135
  st x+,r16
  ldi r16,133
  st x+,r16
  ldi r16,131
  st x+,r16
  ldi r16,129
  st x+,r16
  ldi r16,127
  st x+,r16
  ldi r16,125
  st x+,r16
  ldi r16,122
  st x+,r16
  ldi r16,120
  st x+,r16
  ldi r16,118
  st x+,r16
  ldi r16,116
  st x+,r16
  ldi r16,114
  st x+,r16
  ldi r16,111
  st x+,r16
  ldi r16,109
  st x+,r16
  ldi r16,107
  st x+,r16
  ldi r16,105
  st x+,r16
  ldi r16,102
  st x+,r16
  ldi r16,100
  st x+,r16
  ldi r16,98
  st x+,r16
  ldi r16,95
  st x+,r16
  ldi r16,93
  st x+,r16
  ldi r16,91
  st x+,r16
  ldi r16,88
  st x+,r16
  ldi r16,86
  st x+,r16
  ldi r16,84
  st x+,r16
  ldi r16,81
  st x+,r16
  ldi r16,79
  st x+,r16
  ldi r16,77
  st x+,r16
  ldi r16,74
  st x+,r16
  ldi r16,72
  st x+,r16
  ldi r16,69
  st x+,r16
  ldi r16,67
  st x+,r16
  ldi r16,65
  st x+,r16
  ldi r16,62
  st x+,r16
  ldi r16,60
  st x+,r16
  ldi r16,57
  st x+,r16
  ldi r16,55
  st x+,r16
  ldi r16,52
  st x+,r16
  ldi r16,50
  st x+,r16
  ldi r16,47
  st x+,r16
  ldi r16,45
  st x+,r16
  ldi r16,42
  st x+,r16
  ldi r16,40
  st x+,r16
  ldi r16,37
  st x+,r16
  ldi r16,35
  st x+,r16
  ldi r16,33
  st x+,r16
  ldi r16,30
  st x+,r16
  ldi r16,28
  st x+,r16
  ldi r16,25
  st x+,r16
  ldi r16,23
  st x+,r16
  ldi r16,20
  st x+,r16
  ldi r16,18
  st x+,r16
  ldi r16,15
  st x+,r16
  ldi r16,13
  st x+,r16
  ldi r16,10
  st x+,r16
  ldi r16,8
  st x+,r16
  ldi r16,5
  st x+,r16
  ldi r16,3
  st x+,r16
  ldi r26, 0x00             ; Reset X ptr with the starting addr of Lookup table (SRAM addr: 0x0100)
  ldi r27, 0x01             ; Indirect memory pointer X -> 0x0100
  ret
