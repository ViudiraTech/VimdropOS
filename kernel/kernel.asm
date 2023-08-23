; ==================================================================
; VimdropOS -- Vimdrop操作系统内核
; Copyright (C) 2020-2024 VimdropOS 开发人员--参阅 txtFile/LICENSE.TXT
;
; 这是通过 BOOTLOAD 从驱动器加载的内核文件
; 首先，我们有系统调用向量，它从一个静态点开始
; 供程序使用。下面是主内核代码和
; 然后包括其他系统调用代码。
; ==================================================================


	BITS 16
	CPU 386				; 偏移取决于 386 或更高
					; FS 和 GS 需要 386 或更高

	%DEFINE MIKEOS_VER '0.1.0b'	; 操作系统版本号
	%DEFINE MIKEOS_API_VER 01	; 供程序检查的 API 版本


	; 这是 RAM 中用于内核磁盘操作的位置，24K
	; 在内核加载点之后;它的大小是8K，
	; 因为外部程序在 32K 点之后加载：

	disk_buffer	equ	24576


; ------------------------------------------------------------------
; 操作系统调用向量 -- 系统调用向量的静态位置
; 注意：这些不能移动，否则会中断调用！

; 注释显示了本节中说明的确切位置，
; 并在程序/mikedev.inc中使用，以便外部程序可以
; 使用 VimdropOS 系统调用，而不必知道其确切位置
; 在内核源代码中...

os_call_vectors:
	jmp os_main			; 0000h -- 从引导加载程序调用
	jmp os_print_string		; 0003h
	jmp os_move_cursor		; 0006h
	jmp os_clear_screen		; 0009h
	jmp os_print_horiz_line		; 000Ch
	jmp os_print_newline		; 000Fh
	jmp os_wait_for_key		; 0012h
	jmp os_check_for_key		; 0015h
	jmp os_int_to_string		; 0018h
	jmp os_speaker_tone		; 001Bh
	jmp os_speaker_off		; 001Eh
	jmp os_load_file		; 0021h
	jmp os_pause			; 0024h
	jmp os_fatal_error		; 0027h
	jmp os_draw_background		; 002Ah
	jmp os_string_length		; 002Dh
	jmp os_string_uppercase		; 0030h
	jmp os_string_lowercase		; 0033h
	jmp os_input_string		; 0036h
	jmp os_string_copy		; 0039h
	jmp os_dialog_box		; 003Ch
	jmp os_string_join		; 003Fh
	jmp os_get_file_list		; 0042h
	jmp os_string_compare		; 0045h
	jmp os_string_chomp		; 0048h
	jmp os_string_strip		; 004Bh
	jmp os_string_truncate		; 004Eh
	jmp os_bcd_to_int		; 0051h
	jmp os_get_time_string		; 0054h
	jmp os_get_api_version		; 0057h
	jmp os_file_selector		; 005Ah
	jmp os_get_date_string		; 005Dh
	jmp os_send_via_serial		; 0060h
	jmp os_get_via_serial		; 0063h
	jmp os_find_char_in_string	; 0066h
	jmp os_get_cursor_pos		; 0069h
	jmp os_print_space		; 006Ch
	jmp os_dump_string		; 006Fh
	jmp os_print_digit		; 0072h
	jmp os_print_1hex		; 0075h
	jmp os_print_2hex		; 0078h
	jmp os_print_4hex		; 007Bh
	jmp os_long_int_to_string	; 007Eh
	jmp os_long_int_negate		; 0081h
	jmp os_set_time_fmt		; 0084h
	jmp os_set_date_fmt		; 0087h
	jmp os_show_cursor		; 008Ah
	jmp os_hide_cursor		; 008Dh
	jmp os_dump_registers		; 0090h
	jmp os_string_strincmp		; 0093h
	jmp os_write_file		; 0096h
	jmp os_file_exists		; 0099h
	jmp os_create_file		; 009Ch
	jmp os_remove_file		; 009Fh
	jmp os_rename_file		; 00A2h
	jmp os_get_file_size		; 00A5h
	jmp os_input_dialog		; 00A8h
	jmp os_list_dialog		; 00ABh
	jmp os_string_reverse		; 00AEh
	jmp os_string_to_int		; 00B1h
	jmp os_draw_block		; 00B4h
	jmp os_get_random		; 00B7h
	jmp os_string_charchange	; 00BAh
	jmp os_serial_port_enable	; 00BDh
	jmp os_sint_to_string		; 00C0h
	jmp os_string_parse		; 00C3h
	jmp os_run_basic		; 00C6h
	jmp os_port_byte_out		; 00C9h
	jmp os_port_byte_in		; 00CCh
	jmp os_string_tokenize		; 00CFh
	jmp os_string_to_long_int	; 00D2h


; ------------------------------------------------------------------
; 主内核代码的开始

os_main:
	cli				; 清除中断
	mov ax, 0
	mov ss, ax		; 设置堆栈段和指针
	mov sp, 0FFFFh
	sti				; 恢复中断

	cld				; 字符串操作的默认方向
					; 将“向上” - 递增 RAM 中的地址

	mov ax, 2000h		; 设置所有段以匹配内核的加载位置
	mov ds, ax			; 在此之后，我们不需要打扰
	mov es, ax			; 再一次细分，作为VimdropOS及其程序
	mov fs, ax			; 完全以 64K 保留
	mov gs, ax

	cmp dl, 0
	je no_change
	mov [bootdev], dl	; 保存启动设备编号
	push es
	mov ah, 8			; 获取驱动器参数
	int 13h
	pop es
	and cx, 3Fh			; 最大扇区数
	mov [SecsPerTrack], cx		; 扇区编号从 1 开始
	movzx dx, dh			    ; 最大头数
	add dx, 1			; 头数从 0 开始 - 加 1 表示总数
	mov [Sides], dx

no_change:
	mov ax, 1003h		; 使用某些属性设置文本输出
	mov bx, 0			; 明亮，不闪烁
	int 10h

	call os_seed_random	; 种子随机数生成器


	; 让我们看看是否有一个名为 AUTORUN 的文件.BIN 并执行
	; 如果是这样，在转到程序启动器菜单之前

	mov ax, autorun_bin_file_name
	call os_file_exists
	jc no_autorun_bin		; 如果自动运行，请跳过接下来的三行.BIN 不存在

	mov cx, 32768			; 否则将程序加载到RAM中...
	call os_load_file
	jmp execute_bin_program		; 并转到执行部分


	; 或者也许有一个自动运行.BAS文件？

no_autorun_bin:
	mov ax, autorun_bas_file_name
	call os_file_exists
	jc option_screen		; 如果自动运行，请跳过下一部分.BAS 不存在

	mov cx, 32768			; 否则将程序加载到 RAM 中
	call os_load_file
	call os_clear_screen
	mov ax, 32768
	call os_run_basic		; 运行内核的 BASIC 解释器

	jmp app_selector		; 并在BASIC结束时转到应用程序选择器菜单


	; 现在我们显示一个对话框，为用户提供选择
	; 菜单驱动的程序选择器或命令行界面

option_screen:
	mov ax, os_init_msg		; 设置欢迎屏幕
	mov bx, os_version_msg
	mov cx, 10011111b		; 颜色：浅蓝色白色文字
	call os_draw_background

	mov ax, dialog_string_1	; 询问用户是否需要应用选择器或命令行
	mov bx, dialog_string_2
	mov cx, dialog_string_3
	mov dx, 1			; 我们需要一个双选项对话框（“确定”或“取消”）
	call os_dialog_box

	cmp ax, 1			; 如果选择“确定”（选项 0），则启动应用选择器
	jne near app_selector

	call os_clear_screen	; 否则清理屏幕并启动 CLI
	call os_command_line

	jmp option_screen		; 退出 CLI 后的选件菜单/CLI 选项


	; 上述代码的数据...

	os_init_msg		db 'Vimdrop Operating System', 0
	os_version_msg		db 'Version ', MIKEOS_VER, 0
	
	dialog_string_1		db 'VimdropOS Copyright 2020-2024', 0
	dialog_string_2		db 'Select "OK" to enter the system', 0
	dialog_string_3		db 'Select "Cancel" to enter DOS', 0



app_selector:
	mov ax, os_init_msg		; 绘制主屏幕布局
	mov bx, os_version_msg
	mov cx, 10011111b		; 颜色：浅蓝色白色文字
	call os_draw_background

	call os_file_selector	; 让用户选择一个文件，并存储
					; 生成的字符串位置在 AX 中
					; （其他登记册未定）

	jc option_screen		; 如果按下 Esc 键，则返回 CLI/菜单选择屏幕

	mov si, ax			    ; 用户是否尝试运行“Kernel.bin”？
	mov di, kern_file_name
	call os_string_compare
	jc no_kernel_execute	; 如果是这样，则显示错误消息


	; 接下来，我们需要检查我们尝试运行的程序是否为
	; 有效 - 换句话说，它有一个 .BIN 扩展名

	push si				; 临时保存文件名

	mov bx, si
	mov ax, si
	call os_string_length

	mov si, bx
	add si, ax			; SI 现在指向文件名的末尾...

	dec si
	dec si
	dec si				; 现在开始扩展！

	mov di, bin_ext
	mov cx, 3
	rep cmpsb			; 最后 3 个字符是“BIN”吗？
	jne not_bin_extension		; 如果不是，则可能是“.BAS'

	pop si				; 恢复文件名


	mov ax, si
	mov cx, 32768			; 在何处加载程序文件
	call os_load_file		; 加载 AX 指向的文件名


execute_bin_program:
	call os_clear_screen	; 运行前清除屏幕

	mov ax, 0		; 清除所有寄存器
	mov bx, 0
	mov cx, 0
	mov dx, 0
	mov si, 0
	mov di, 0

	call 32768		; 调用外部程序代码
					; 在段的第二个 32K 加载
					; （程序必须以“ret”结尾）

	mov si, program_finished_msg	; 给程序一个展示的机会
	call os_print_string	; 清除屏幕之前的任何输出
	call os_wait_for_key

	call os_clear_screen	; 完成后，清除屏幕
	jmp app_selector		; 并返回程序列表


no_kernel_execute:			; 警告不要尝试执行内核！
	mov ax, kerndlg_string_1
	mov bx, kerndlg_string_2
	mov cx, kerndlg_string_3
	mov dx, 0			; 一个按钮对话框
	call os_dialog_box

	jmp app_selector	; 重新开始...


not_bin_extension:
	pop si				; 我们在 .BIN 扩展名检查

	push si				; 再次保存以备不时之需...

	mov bx, si
	mov ax, si
	call os_string_length

	mov si, bx
	add si, ax			; SI 现在指向文件名的末尾...

	dec si
	dec si
	dec si				; 现在开始扩展！

	mov di, bas_ext
	mov cx, 3
	rep cmpsb			; 最后 3 个字符是“BAS”吗？
	jne not_bas_extension	; 如果没有，则错误输出


	pop si

	mov ax, si
	mov cx, 32768			; 在何处加载程序文件
	call os_load_file		; 加载 AX 指向的文件名

	call os_clear_screen    ; 运行前清除屏幕

	mov ax, 32768
	mov si, 0			; 没有要传递的参数
	call os_run_basic	; 并在代码上运行我们的 BASIC 解释器！

	mov si, program_finished_msg
	call os_print_string
	call os_wait_for_key

	call os_clear_screen
	jmp app_selector	; 并返回程序列表


not_bas_extension:
	pop si

	mov ax, ext_string_1
	mov bx, ext_string_2
	mov cx, 0
	mov dx, 0			; 一个按钮对话框
	call os_dialog_box

	jmp app_selector	; 重新开始...


	; 现在上面代码的数据...

	kern_file_name		db 'KERNEL.BIN', 0

	autorun_bin_file_name	db 'AUTORUN.BIN', 0
	autorun_bas_file_name	db 'AUTORUN.BAS', 0

	bin_ext			db 'BIN'
	bas_ext			db 'BAS'

	kerndlg_string_1	db 'Cannot load and execute VimdropOS kernel!', 0
	kerndlg_string_2	db 'KERNEL.BIN is the core of VimdropOS, and', 0
	kerndlg_string_3	db 'is not a normal program.', 0

	ext_string_1		db 'Invalid filename extension! You can', 0
	ext_string_2		db 'only execute .BIN or .BAS programs.', 0

	program_finished_msg	db '>>> Program finished -- press a key to continue...', 0


; ------------------------------------------------------------------
; 系统变量 -- 程序和系统调用的设置


	; 时间和日期格式

	fmt_12_24	db 0		; 非零 = 24 小时格式

	fmt_date	db 0, '/'	; 0, 1, 2 = M/D/Y, D/M/Y 或 Y/M/D
					        ; 位 7 = 使用名称数月
					        ; If bit 7 = 0, 第二个字节 = 分隔符


; ------------------------------------------------------------------
; 功能 -- 要载入内核的代码


	%INCLUDE "features/cli.asm"
 	%INCLUDE "features/disk.asm"
	%INCLUDE "features/keyboard.asm"
	%INCLUDE "features/math.asm"
	%INCLUDE "features/misc.asm"
	%INCLUDE "features/ports.asm"
	%INCLUDE "features/screen.asm"
	%INCLUDE "features/sound.asm"
	%INCLUDE "features/string.asm"
	%INCLUDE "features/basic.asm"


; ==================================================================
; 内核结束
; ==================================================================

