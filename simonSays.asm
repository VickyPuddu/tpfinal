LIST P=16F887
#include <p16f887.inc>

 __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _CP_OFF & _CPD_OFF & _BOREN_ON & _IESO_ON & _FCMEN_ON & _LVP_OFF
 __CONFIG _CONFIG2, _BOR4V_BOR21V & _WRT_OFF
 
; --- Constantes de Hardware ---
#define I2C_ADDR_WRITE  0x4E
#define LCD_BACKLIGHT   0x08        
#define MAX_NIVEL       .10

; Servo (ancho de pulso en microsegundos, Timer1 a 1 MHz)
#define SERVO_ABAJO_H   0x03        ; 1000 us = 0x03E8 (bandera abajo)
#define SERVO_ABAJO_L   0xE8
#define SERVO_ARRIBA_H  0x07        ; 2000 us = 0x07D0 (bandera arriba)
#define SERVO_ARRIBA_L  0xD0

; PWM de LEDs: periodo = (PR2+1) * 4us = 250 us (4 kHz). Duty = CCPR2L / 250
#define DUTY_MIN        .50         ; 20 %
#define DUTY_MAX        .200        ; 80 %
#define DUTY_FULL       .250        ; 100 % (modo juego)

; Tono de error (Game Over)
#define TONE_ERR_DELAY  .250        ; ~200 Hz
#define TONE_ERR_CNT_H  0x00        ; 200 ciclos = 1.0 s
#define TONE_ERR_CNT_L  0xC8

W_TEMP          EQU 0x70
STATUS_TEMP     EQU 0x71
PCLATH_TEMP     EQU 0x72
ESTADO          EQU 0x20
NIVEL           EQU 0x21
PASO_ACTUAL     EQU 0x22
TECLA_PRESS     EQU 0x23
FLAG_TECLA      EQU 0x24
BTN_LOCK        EQU 0x25
I2C_BYTE        EQU 0x26
LCD_AUX         EQU 0x27
TABLA_IDX       EQU 0x28
SERVO_HI        EQU 0x29
SERVO_LO        EQU 0x2A
SERVO_STATE     EQU 0x2B
SEED            EQU 0x2C
TEMP_NUM        EQU 0x2D
DECENAS         EQU 0x2E
TONO_DELAY      EQU 0x2F
TONO_CNT_H      EQU 0x30
TONO_CNT_L      EQU 0x31
DEL1            EQU 0x32
DEL2            EQU 0x33
DEL3            EQU 0x34
DEL4            EQU 0x35
DEL5            EQU 0x36
BREATH_DUTY     EQU 0x37
BREATH_DIR      EQU 0x38            ; bit0: 0 = subiendo, 1 = bajando
VEL_IDX         EQU 0x39
VEL_PAUSA       EQU 0x3A            ; Pausa entre pasos (x10 ms)
VEL_SHIFT       EQU 0x3B            ; Acorta duración del tono (desplazamientos)
CONT_BANDERA    EQU 0x3C
SECUENCIA       EQU 0x40

    ORG     0x00
    GOTO    INICIO
    
    ORG     0x04
    GOTO    ISR
    
    ORG     0x10
TABLA_TEXTOS:
    ADDWF   PCL, F
IDX_TITULO      EQU ($ - TABLA_TEXTOS - 1)
    DT      "  SIMON DICE  ", 0
IDX_START       EQU ($ - TABLA_TEXTOS - 1)
    DT      "PULSA UN BOTON", 0
IDX_JUGANDO     EQU ($ - TABLA_TEXTOS - 1)
    DT      "REPLICA PASOS!", 0
IDX_NIVEL       EQU ($ - TABLA_TEXTOS - 1)
    DT      "NIVEL: ", 0
IDX_GAMEOVER    EQU ($ - TABLA_TEXTOS - 1)
    DT      "  GAME OVER!  ", 0
IDX_GANASTE     EQU ($ - TABLA_TEXTOS - 1)
    DT      " GANASTE! (32)", 0

; 4 bytes por color: LED_MASK, TONE_DELAY, TONE_CNT_H, TONE_CNT_L
TABLA_PASOS:
    ADDWF   PCL, F
    DT   0x01, .152, 0x00, 0xA4     ; 0: Verde    (329 Hz, 0.5 s)
    DT   0x02, .114, 0x00, 0xDB     ; 1: Rojo     (439 Hz, 0.5 s)
    DT   0x04, .90,  0x01, 0x16     ; 2: Azul     (555 Hz, 0.5 s)
    DT   0x08, .76,  0x01, 0x49     ; 3: Amarillo (658 Hz, 0.5 s)

; 2 bytes por nivel de velocidad (según el potenciómetro):
;   PAUSA (x10 ms entre pasos), SHIFT (tono dividido por 2^SHIFT)
TABLA_VEL:
    ADDWF   PCL, F
    DT   .50, .0                    ; 0: lento    (pot. al mínimo)
    DT   .30, .1                    ; 1
    DT   .15, .1                    ; 2
    DT   .6,  .2                    ; 3: rápido   (pot. al máximo)

;==============================================================================
; RUTINA DE INTERRUPCIÓN (PWM 50 HZ SERVO + PULSADORES IOCB)
;==============================================================================
ISR:
    MOVWF   W_TEMP
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP
    MOVF    PCLATH, W
    MOVWF   PCLATH_TEMP
    CLRF    PCLATH

    ; --- CCP1 Compare: PWM 20 ms en RC2 ---
    BANKSEL PIR1
    BTFSS   PIR1, CCP1IF
    GOTO    CHECK_RBIF
    BCF     PIR1, CCP1IF

    BANKSEL SERVO_STATE
    BTFSC   SERVO_STATE, 0
    GOTO    SERVO_FIN_BAJO

    BANKSEL CCPR1L                  ; Fin pulso alto -> programar bajada
    MOVF    SERVO_LO, W
    ADDWF   CCPR1L, F
    BTFSC   STATUS, C
    INCF    CCPR1H, F
    MOVF    SERVO_HI, W
    ADDWF   CCPR1H, F
    MOVLW   B'00001001'
    MOVWF   CCP1CON
    BANKSEL SERVO_STATE
    BSF     SERVO_STATE, 0
    GOTO    CHECK_RBIF

SERVO_FIN_BAJO:                     ; Fin pulso bajo -> completar 20000 us (0x4E20)
    BANKSEL CCPR1L
    MOVLW   0x20
    ADDWF   CCPR1L, F
    BTFSC   STATUS, C
    INCF    CCPR1H, F
    MOVLW   0x4E
    ADDWF   CCPR1H, F
    BANKSEL SERVO_LO
    MOVF    SERVO_LO, W
    BANKSEL CCPR1L
    SUBWF   CCPR1L, F
    BTFSS   STATUS, C
    DECF    CCPR1H, F
    BANKSEL SERVO_HI
    MOVF    SERVO_HI, W
    BANKSEL CCPR1H
    SUBWF   CCPR1H, F
    MOVLW   B'00001000'
    MOVWF   CCP1CON
    BANKSEL SERVO_STATE
    BCF     SERVO_STATE, 0

CHECK_RBIF:
    BANKSEL INTCON
    BTFSS   INTCON, RBIF
    GOTO    FIN_ISR

    BANKSEL PORTB
    MOVF    PORTB, W
    XORLW   0x0F
    ANDLW   0x0F
    BTFSS   STATUS, Z
    GOTO    BOTON_PRESIONADO
    CLRF    BTN_LOCK
    GOTO    CLEAR_RBIF

BOTON_PRESIONADO:
    BTFSC   BTN_LOCK, 0
    GOTO    CLEAR_RBIF
    BSF     BTN_LOCK, 0
    BTFSS   PORTB, 0
    MOVLW   .0
    BTFSS   PORTB, 1
    MOVLW   .1
    BTFSS   PORTB, 2
    MOVLW   .2
    BTFSS   PORTB, 3
    MOVLW   .3
    MOVWF   TECLA_PRESS
    MOVLW   .1
    MOVWF   FLAG_TECLA

CLEAR_RBIF:
    BANKSEL INTCON
    BCF     INTCON, RBIF

FIN_ISR:
    MOVF    PCLATH_TEMP, W
    MOVWF   PCLATH
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W
    RETFIE

;==============================================================================
; INICIALIZACIÓN
;==============================================================================
INICIO:
    BANKSEL ANSEL
    MOVLW   B'00000001'             ; Solo AN0 (RA0) analógico: potenciómetro
    MOVWF   ANSEL
    CLRF    ANSELH
    BANKSEL CM1CON0
    CLRF    CM1CON0
    CLRF    CM2CON0

    BANKSEL TRISB
    MOVLW   B'00001111'             ; RB0..RB3 entradas
    MOVWF   TRISB
    CLRF    TRISD                   ; RD0..RD3 LEDs, RD4 Sounder
    BSF     TRISA, 0                ; RA0 potenciómetro
    BCF     TRISC, 1                ; RC1 PWM -> MOSFET de los LEDs
    BCF     TRISC, 2                ; RC2 PWM Servo
    BSF     TRISC, 3                ; RC3 SCL
    BSF     TRISC, 4                ; RC4 SDA
    BCF     TRISC, 6                ; RC6 TX
    BSF     TRISC, 7                ; RC7 RX

    BANKSEL OPTION_REG
    MOVLW   B'00000111'             ; Pull-ups activos, TMR0 interno 1:256
    MOVWF   OPTION_REG
    BANKSEL WPUB
    MOVLW   B'00001111'
    MOVWF   WPUB
    BANKSEL IOCB
    MOVLW   B'00001111'
    MOVWF   IOCB

    BANKSEL PORTD
    CLRF    PORTD
    BCF     PORTC, 2
    CLRF    ESTADO
    CLRF    FLAG_TECLA
    CLRF    BTN_LOCK
    MOVLW   0xA5
    MOVWF   SEED

    CALL    ADC_INICIAL
    CALL    PWM_INICIAL
    CALL    I2C_INICIAL
    CALL    UART_INICIAL
    CALL    SERVO_INICIAL
    CALL    LCD_INICIAL

    BANKSEL PORTB
    MOVF    PORTB, W
    BANKSEL INTCON
    BCF     INTCON, RBIF
    BSF     INTCON, RBIE
    BSF     INTCON, PEIE
    BSF     INTCON, GIE

    CALL    PANTALLA_BIENVENIDA
    CALL    INACT_INICIAL
    
BUCLE_PRINCIPAL:
    BANKSEL ESTADO
    MOVF    ESTADO, W
    XORLW   .0
    BTFSC   STATUS, Z
    GOTO    ESTADO_INACTIVO
    MOVF    ESTADO, W
    XORLW   .1
    BTFSC   STATUS, Z
    GOTO    ESTADO_MUESTRA
    MOVF    ESTADO, W
    XORLW   .2
    BTFSC   STATUS, Z
    GOTO    ESTADO_JUGADOR
    MOVF    ESTADO, W
    XORLW   .3
    BTFSC   STATUS, Z
    GOTO    ESTADO_GAMEOVER
    GOTO    ESTADO_GANASTE

; --- Espera de botón: LEDs "respirando" (20 % <-> 80 %) ---
ESTADO_INACTIVO:
    BANKSEL TMR0
    MOVF    TMR0, W
    XORWF   SEED, F
    INCF    SEED, F
    BTFSC   FLAG_TECLA, 0
    GOTO    INICIAR_IN
    CALL    RESPIRACION             ; Un paso de respiración (10 ms)
    GOTO    BUCLE_PRINCIPAL

INICIAR_IN:
    CALL    RETARDO_20MS
    CLRF    FLAG_TECLA
    CALL    LEDS_MODO_JUEGO         ; MOSFET al 100 %, LEDs apagados
    MOVLW   .1
    MOVWF   NIVEL
    CALL    GENERAR_ALEATORIO
    MOVWF   SECUENCIA

    CALL    LCD_CLEAR
    MOVLW   IDX_JUGANDO
    CALL    PRINT_L1_UART
    MOVLW   .1
    MOVWF   ESTADO
    GOTO    BUCLE_PRINCIPAL

ESTADO_MUESTRA:
    CALL    MOSTRAR_NIVEL_LCD_UART
    CALL    RETARDO_500MS
    CLRF    PASO_ACTUAL

LOOP_MUESTRA_PASO:
    MOVLW   SECUENCIA
    ADDWF   PASO_ACTUAL, W
    MOVWF   FSR
    MOVF    INDF, W
    ANDLW   0x03
    MOVWF   LCD_AUX
    CALL    EJECUTAR_PASO_VISUAL    ; Lee el potenciómetro y reproduce el paso
    CALL    RETARDO_PASO            ; Pausa según velocidad

    INCF    PASO_ACTUAL, F
    MOVF    PASO_ACTUAL, W
    SUBWF   NIVEL, W
    BTFSS   STATUS, Z
    GOTO    LOOP_MUESTRA_PASO

    CLRF    PASO_ACTUAL
    CLRF    FLAG_TECLA
    MOVLW   .2
    MOVWF   ESTADO
    GOTO    BUCLE_PRINCIPAL

ESTADO_JUGADOR:
    BTFSS   FLAG_TECLA, 0
    GOTO    BUCLE_PRINCIPAL

    CALL    RETARDO_20MS
    CLRF    FLAG_TECLA
    MOVLW   SECUENCIA
    ADDWF   PASO_ACTUAL, W
    MOVWF   FSR
    MOVF    INDF, W
    ANDLW   0x03
    SUBWF   TECLA_PRESS, W
    BTFSS   STATUS, Z
    GOTO    PASO_INCORRECTO

    MOVF    TECLA_PRESS, W
    MOVWF   LCD_AUX
    CALL    EJECUTAR_PASO_VISUAL

    INCF    PASO_ACTUAL, F
    MOVF    PASO_ACTUAL, W
    SUBWF   NIVEL, W
    BTFSS   STATUS, Z
    GOTO    BUCLE_PRINCIPAL

    MOVF    NIVEL, W
    XORLW   MAX_NIVEL
    BTFSC   STATUS, Z
    GOTO    IR_A_GANASTE

    CALL    GENERAR_ALEATORIO
    MOVWF   LCD_AUX
    MOVLW   SECUENCIA
    ADDWF   NIVEL, W
    MOVWF   FSR
    MOVF    LCD_AUX, W
    MOVWF   INDF

    INCF    NIVEL, F
    CALL    RETARDO_500MS
    MOVLW   .1
    MOVWF   ESTADO
    GOTO    BUCLE_PRINCIPAL

PASO_INCORRECTO:
    MOVLW   .3
    MOVWF   ESTADO
    GOTO    BUCLE_PRINCIPAL

IR_A_GANASTE:
    MOVLW   .4
    MOVWF   ESTADO
    GOTO    BUCLE_PRINCIPAL

ESTADO_GAMEOVER:
    CALL    LCD_CLEAR
    MOVLW   IDX_GAMEOVER
    CALL    PRINT_L1_UART
    CALL    MOSTRAR_NIVEL_LCD_UART

    BANKSEL PORTD
    MOVLW   0x0F
    MOVWF   PORTD
    MOVLW   TONE_ERR_DELAY
    MOVWF   TONO_DELAY
    MOVLW   TONE_ERR_CNT_H
    MOVWF   TONO_CNT_H
    MOVLW   TONE_ERR_CNT_L
    MOVWF   TONO_CNT_L
    CALL    GENERAR_TONO
    CLRF    PORTD
    CALL    RETARDO_500MS

    CALL    PANTALLA_BIENVENIDA
    CLRF    FLAG_TECLA
    CLRF    ESTADO
    CALL    INACT_INICIAL
    GOTO    BUCLE_PRINCIPAL

; --- Victoria: sube la bandera con el servo, celebra y la baja ---
ESTADO_GANASTE:
    CALL    LCD_CLEAR
    MOVLW   IDX_GANASTE
    CALL    PRINT_L1_UART
    CALL    SERVO_SUBIR             ; Bandera arriba

    CLRF    LCD_AUX
LOOP_CELEBRACION:
    CALL    EJECUTAR_PASO_VISUAL
    INCF    LCD_AUX, F
    BTFSS   LCD_AUX, 2              ; Repetir para colores 0..3
    GOTO    LOOP_CELEBRACION

    MOVLW   .10                     ; Mantener la bandera 10 x 0.5 s = 5 s
    MOVWF   CONT_BANDERA
ESPERA_BANDERA:
    CALL    RETARDO_500MS
    DECFSZ  CONT_BANDERA, F
    GOTO    ESPERA_BANDERA

    CALL    SERVO_BAJAR             ; Bandera abajo
    CALL    RETARDO_500MS           ; Tiempo para que el servo llegue

    CALL    PANTALLA_BIENVENIDA
    CLRF    FLAG_TECLA
    CLRF    ESTADO
    CALL    INACT_INICIAL
    GOTO    BUCLE_PRINCIPAL
    
    
    I2C_INICIAL:
    BANKSEL SSPADD
    MOVLW   .9                      ; 100 kHz a 4 MHz
    MOVWF   SSPADD
    BANKSEL SSPSTAT
    BSF     SSPSTAT, SMP
    BANKSEL SSPCON
    MOVLW   B'00101000'
    MOVWF   SSPCON
    BANKSEL ESTADO
    RETURN

MI_I2C_START:
    BANKSEL SSPCON2
    BSF     SSPCON2, SEN
I2C_WAIT:
    BANKSEL PIR1
    BTFSS   PIR1, SSPIF
    GOTO    I2C_WAIT
    BCF     PIR1, SSPIF
    BANKSEL ESTADO
    RETURN

MI_I2C_STOP:
    BANKSEL SSPCON2
    BSF     SSPCON2, PEN
    GOTO    I2C_WAIT

I2C_WRITE:
    BANKSEL SSPBUF
    MOVWF   SSPBUF
    GOTO    I2C_WAIT

LCD_INICIAL:
    CALL    RETARDO_50MS
    MOVLW   0x30
    CALL    LCD_SEND_NIBBLE
    CALL    RETARDO_5MS
    MOVLW   0x30
    CALL    LCD_SEND_NIBBLE
    CALL    RETARDO_5MS
    MOVLW   0x30
    CALL    LCD_SEND_NIBBLE
    CALL    RETARDO_5MS
    MOVLW   0x20
    CALL    LCD_SEND_NIBBLE
    CALL    RETARDO_5MS
    MOVLW   0x28
    CALL    LCD_CMD
    MOVLW   0x0C
    CALL    LCD_CMD
    MOVLW   0x06
    CALL    LCD_CMD

LCD_CLEAR:
    MOVLW   0x01
    CALL    LCD_CMD
    GOTO    RETARDO_5MS

LCD_CMD:
    MOVWF   LCD_AUX
    ANDLW   0xF0
    IORLW   LCD_BACKLIGHT
    CALL    LCD_WRITE_4BITS
    SWAPF   LCD_AUX, W
    ANDLW   0xF0
    IORLW   LCD_BACKLIGHT
    GOTO    LCD_WRITE_4BITS

LCD_DATA:
    MOVWF   LCD_AUX
    ANDLW   0xF0
    IORLW   (LCD_BACKLIGHT | 0x01)
    CALL    LCD_WRITE_4BITS
    SWAPF   LCD_AUX, W
    ANDLW   0xF0
    IORLW   (LCD_BACKLIGHT | 0x01)

LCD_WRITE_4BITS:
    MOVWF   I2C_BYTE
    CALL    MI_I2C_START
    MOVLW   I2C_ADDR_WRITE
    CALL    I2C_WRITE
    MOVF    I2C_BYTE, W
    CALL    I2C_WRITE
    MOVF    I2C_BYTE, W
    IORLW   0x04
    CALL    I2C_WRITE
    MOVF    I2C_BYTE, W
    CALL    I2C_WRITE
    GOTO    MI_I2C_STOP

LCD_SEND_NIBBLE:
    IORLW   LCD_BACKLIGHT
    GOTO    LCD_WRITE_4BITS

PRINT_L1_UART:
    MOVWF   DECENAS                 ; Guardar índice de texto
    CALL    LCD_PRINT_LINE1
    MOVF    DECENAS, W
    CALL    UART_PRINT_STRING
    GOTO    UART_CRLF

LCD_PRINT_LINE1:
    MOVWF   TABLA_IDX
    MOVLW   0x80
    CALL    LCD_CMD
    GOTO    LCD_PRINT_STRING

LCD_PRINT_LINE2:
    MOVWF   TABLA_IDX
    MOVLW   0xC0
    CALL    LCD_CMD

LCD_PRINT_STRING:
    MOVF    TABLA_IDX, W
    CLRF    PCLATH
    CALL    TABLA_TEXTOS
    IORLW   0x00
    BTFSC   STATUS, Z
    RETURN
    CALL    LCD_DATA
    INCF    TABLA_IDX, F
    GOTO    LCD_PRINT_STRING

PANTALLA_BIENVENIDA:
    CALL    LCD_CLEAR
    MOVLW   IDX_TITULO
    CALL    PRINT_L1_UART
    MOVLW   IDX_START
    CALL    LCD_PRINT_LINE2
    MOVLW   IDX_START
    CALL    UART_PRINT_STRING
    GOTO    UART_CRLF

MOSTRAR_NIVEL_LCD_UART:
    MOVLW   IDX_NIVEL
    CALL    LCD_PRINT_LINE2
    MOVLW   IDX_NIVEL
    CALL    UART_PRINT_STRING

    MOVF    NIVEL, W
    MOVWF   TEMP_NUM
    CLRF    DECENAS
DIV_10_LOOP:
    MOVLW   .10
    SUBWF   TEMP_NUM, W
    BTFSS   STATUS, C
    GOTO    FIN_DIV_10
    MOVWF   TEMP_NUM
    INCF    DECENAS, F
    GOTO    DIV_10_LOOP
FIN_DIV_10:
    MOVF    DECENAS, W
    ADDLW   '0'
    CALL    LCD_DATA
    MOVF    DECENAS, W
    ADDLW   '0'
    CALL    UART_SEND_BYTE
    MOVF    TEMP_NUM, W
    ADDLW   '0'
    CALL    LCD_DATA
    MOVF    TEMP_NUM, W
    ADDLW   '0'
    CALL    UART_SEND_BYTE
    GOTO    UART_CRLF

EJECUTAR_PASO_VISUAL:
    CALL    LEER_VELOCIDAD

    BCF     STATUS, C
    RLF     LCD_AUX, W              ; W = color * 2
    MOVWF   TEMP_NUM
    BCF     STATUS, C
    RLF     TEMP_NUM, F             ; TEMP_NUM = color * 4

    CLRF    PCLATH
    MOVF    TEMP_NUM, W
    CALL    TABLA_PASOS             ; Byte 0: Máscara LED
    BANKSEL PORTD
    MOVWF   PORTD

    INCF    TEMP_NUM, F
    MOVF    TEMP_NUM, W
    CALL    TABLA_PASOS             ; Byte 1: TONE_DELAY
    MOVWF   TONO_DELAY

    INCF    TEMP_NUM, F
    MOVF    TEMP_NUM, W
    CALL    TABLA_PASOS             ; Byte 2: TONE_CNT_H
    MOVWF   TONO_CNT_H

    INCF    TEMP_NUM, F
    MOVF    TEMP_NUM, W
    CALL    TABLA_PASOS             ; Byte 3: TONE_CNT_L
    MOVWF   TONO_CNT_L

    MOVF    VEL_SHIFT, F            ; Dividir la duración por 2^VEL_SHIFT
    BTFSC   STATUS, Z
    GOTO    EPV_TONO
EPV_SHIFT:
    BCF     STATUS, C
    RRF     TONO_CNT_H, F
    RRF     TONO_CNT_L, F
    DECFSZ  VEL_SHIFT, F
    GOTO    EPV_SHIFT
EPV_TONO:
    CALL    GENERAR_TONO
    BANKSEL PORTD
    MOVLW   0xF0
    ANDWF   PORTD, F
    RETURN

GENERAR_TONO:
    BANKSEL PORTD
TONO_LOOP:
    BSF     PORTD, 4
    CALL    TONO_SEMI_WAIT
    BCF     PORTD, 4
    CALL    TONO_SEMI_WAIT

    MOVF    TONO_CNT_L, F
    BTFSC   STATUS, Z
    GOTO    TONO_DEC_H
    DECF    TONO_CNT_L, F
    GOTO    TONO_LOOP
TONO_DEC_H:
    MOVF    TONO_CNT_H, F
    BTFSC   STATUS, Z
    RETURN
    DECF    TONO_CNT_H, F
    DECF    TONO_CNT_L, F
    GOTO    TONO_LOOP

; Cada vuelta del lazo = 10 ciclos (7 NOP + DECFSZ + GOTO) = 10 us a 4 MHz
TONO_SEMI_WAIT:
    MOVF    TONO_DELAY, W
    MOVWF   DEL1
TSW_LOOP:
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    DECFSZ  DEL1, F
    GOTO    TSW_LOOP
    RETURN

RETARDO_5MS:
    MOVLW   .5
    MOVWF   DEL1
R5_L1:
    MOVLW   .249
    MOVWF   DEL2
    NOP
    DECFSZ  DEL2, F
    GOTO    $-2
    DECFSZ  DEL1, F
    GOTO    R5_L1
    RETURN

RETARDO_10MS:
    CALL    RETARDO_5MS
    GOTO    RETARDO_5MS

RETARDO_20MS:
    CALL    RETARDO_5MS
    CALL    RETARDO_5MS
    CALL    RETARDO_5MS
    GOTO    RETARDO_5MS

RETARDO_50MS:
    MOVLW   .10
    MOVWF   DEL3
    CALL    RETARDO_5MS
    DECFSZ  DEL3, F
    GOTO    $-2
    RETURN

RETARDO_250MS:
    MOVLW   .5
    MOVWF   DEL4
    CALL    RETARDO_50MS
    DECFSZ  DEL4, F
    GOTO    $-2
    RETURN

RETARDO_500MS:
    CALL    RETARDO_250MS
    GOTO    RETARDO_250MS

    END
