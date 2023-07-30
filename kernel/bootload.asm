; ==================================================================
; Vimdrop操作系统引导加载程序
; Copyright (C) 2020-2024 VimdropOS 开发人员--参阅 txtFile/LICENSE.TXT
;
; 基于 E Dehling 的自由引导加载程序,读取FAT12
; 加载软盘中的Kernel.bin（VimdropOS内核）并执行它
; 引导代码大小不超过 512 字节（一个扇区）
; 最后两个字节是引导签名（AA55h）请注意
; 集群与扇区相同：512 字节
; ==================================================================


	BITS 16

	jmp short bootloader_start	; 跳转到磁盘描述部分
	nop				            ; 在磁盘描述之前填充


; ------------------------------------------------------------------
; 磁盘描述表，使其成为有效的软盘
; 注意：其中一些值在源代码中是硬编码的！
; 值是 IBM 用于 1.44 MB、3.5 英寸软盘的值

OEMLabel		db "VIMDBOOT"	; 磁盘标签
BytesPerSector		dw 512		; 每个扇区的字节数
SectorsPerCluster	db 1		; 每个集群的扇区数
ReservedForBoot		dw 1		; 引导记录的保留扇区
NumberOfFats		db 2		; FAT的副本数
RootDirEntries		dw 224		; 根目录中的条目数
					            ; (224 * 32 = 7168 = 14 要读取的扇区)
LogicalSectors		dw 2880		; 逻辑扇区数
MediumByte		db 0F0h		    ; 中等描述符字节
SectorsPerFat		dw 9		; 每 FAT 的部门数
SectorsPerTrack		dw 18		; 每轨道扇区数（36/缸）
Sides			dw 2		    ; 边数/头数
HiddenSectors		dd 0		; 隐藏扇区数量
LargeSectors		dd 0		; LBA 扇区数量
DriveNo			dw 0		    ; 驱动器号：0
Signature		db 41		    ; 驱动器签名：41 表示软盘
VolumeID		dd 00000000h	; 卷 ID：任意数字
VolumeLabel		db "VIMDROPOS  "; 卷标：任意 11 个字符
FileSystem		db "FAT12   "	; 文件系统类型：不要更改！


; ------------------------------------------------------------------
; 主引导加载程序代码

bootloader_start:
	mov ax, 07C0h	; 在缓冲区上方设置 4K 的堆栈空间
	add ax, 544		; 8k 缓冲区 = 512 段 + 32 段（加载器）
	cli				; 更改堆栈时禁用中断
	mov ss, ax
	mov sp, 4096
	sti				; 恢复中断

	mov ax, 07C0h	; 将07C0H设置为我们的加载位置
	mov ds, ax

	; 注：据报告，一些早期 BIOS 未正确设置 DL

	cmp dl, 0
	je no_change
	mov [bootdev], dl	; 保存启动设备编号
	mov ah, 8			; 获取驱动器参数
	int 13h
	jc fatal_disk_error
	and cx, 3Fh			; 最大扇区数
	mov [SectorsPerTrack], cx	; 扇区编号从 1 开始
	movzx dx, dh			    ; 最大头数
	add dx, 1			        ; 头数从 0 开始 - 加 1 表示总数
	mov [Sides], dx

no_change:
	mov eax, 0		; 某些较旧的 BIOS 需要


; 首先，我们需要从磁盘加载根目录。细节：
; 根的开始 = 保留引导 + 脂肪数量 * 扇区每脂肪 = 逻辑 19
; 根目录数 = 根目录条目 * 32 字节/条目 / 512 字节/扇区 = 14
; 用户数据开始 =（根开始）+（根数）= 逻辑 33

floppy_ok:				; 准备读取第一个数据块
	mov ax, 19			; 根目录从逻辑扇区 19 开始
	call l2hts

	mov si, buffer			; 将 ES：BX 设置为指向我们的缓冲区（请参阅代码末尾）
	mov bx, ds
	mov es, bx
	mov bx, si

	mov ah, 2			; int 13h 的参数：读取软盘扇区
	mov al, 14			; 并阅读其中的 14 个

	pusha				; 准备进入循环


read_root_dir:
	popa				; 如果寄存器被 int 13h 更改
	pusha

	stc				    ; 一些 BIOS 在出错时未正确设置
	int 13h				; 使用 BIOS 读取扇区

	jnc search_dir		; 如果阅读正常，请跳过
	call reset_floppy	; 否则，请重置软盘控制器，然后重试
	jnc read_root_dir	; 软盘复位确定吗？

	jmp reboot			; 如果没有，致命的双重错误


search_dir:
	popa

	mov ax, ds			; 根目录现在位于 [缓冲区] 中
	mov es, ax			; 将 DI 设置为此信息
	mov di, buffer

	mov cx, word [RootDirEntries]  ; 搜索所有 （224） 条目
	mov ax, 0			           ; 在偏移量 0 处搜索


next_root_entry:
	xchg cx, dx			    ; 我们在内部循环中使用CX...

	mov si, kern_filename	; 开始搜索内核文件名
	mov cx, 11
	rep cmpsb
	je found_file_to_load	; 指针 DI 将位于偏移量 11 处

	add ax, 32			    ; 将搜索的条目凸起 1（每个条目 32 字节）

	mov di, buffer			; 指向下一个条目
	add di, ax

	xchg dx, cx			        ; 找回原始客户体验
	loop next_root_entry

	mov si, file_not_found		; 如果找不到内核，则跳出
	call print_string
	jmp reboot


found_file_to_load:			    ; 获取集群并将 FAT 加载到 RAM 中
	mov ax, word [es:di+0Fh]	; 偏移量 11 + 15 = 26，包含第一个聚类
	mov word [cluster], ax

	mov ax, 1			; 扇区 1 = 第一个 FAT 的第一个扇区
	call l2hts

	mov di, buffer		; ES：BX 指向我们的缓冲区
	mov bx, di

	mov ah, 2			; int 13h 参数：读取 （FAT） 扇区
	mov al, 9			; 第一FAT的所有9个部门

	pusha				; 准备进入循环


read_fat:
	popa				; 如果寄存器被 int 13h 更改
	pusha

	stc
	int 13h				; 使用 BIOS 读取扇区

	jnc read_fat_ok			; 如果读取正常，请跳过
	call reset_floppy		; 否则，请重置软盘控制器，然后重试
	jnc read_fat			; 软盘复位确定吗？

; ******************************************************************
fatal_disk_error:
; ******************************************************************
	mov si, disk_error		; 如果没有，请打印错误消息并重新启动
	call print_string
	jmp reboot			    ; 致命双重错误


read_fat_ok:
	popa

	mov ax, 2000h		; 我们将在其中加载内核的段
	mov es, ax
	mov bx, 0

	mov ah, 2			; int 13h 软盘读取参数
	mov al, 1

	push ax				; 保存以防我们（或 int 调用）丢失它


; 现在我们必须从磁盘加载 FAT。以下是我们如何找出它的开始：
; FAT 群集 0 = 媒体描述符 = 0F0h
; FAT 簇 1 = 填充簇 = 0FFh
; 群集启动 =（（群集编号） - 2） * 每个群集的扇区数 + （用户启动）
;               =（簇号）+ 31

load_file_sector:
	mov ax, word [cluster]		; 将扇区转换为逻辑
	add ax, 31

	call l2hts			; 为 int 13h 制作适当的参数

	mov ax, 2000h		; 将缓冲区设置为我们已经读取的内容
	mov es, ax
	mov bx, word [pointer]

	pop ax				; 保存以防我们（或 int 调用）丢失它
	push ax

	stc
	int 13h

	jnc calculate_next_cluster	; 如果没有错误...

	call reset_floppy		    ; 否则，重置软盘并重试
	jmp load_file_sector


	; I在 FAT 中，集群值以 12 位存储，因此我们必须
	; 做一些数学运算来确定我们是否正在处理一个字节
	; 和下一个字节的 4 位 - 或一个字节的最后 4 位
	; 然后是随后的字节！

calculate_next_cluster:
	mov ax, [cluster]
	mov dx, 0
	mov bx, 3
	mul bx
	mov bx, 2
	div bx			; DX = [集群] mod 2
	mov si, buffer
	add si, ax		; AX = 12 位条目的 FAT 字
	mov ax, word [ds:si]

	or dx, dx		; 如果 DX = 0 [集群] 为偶数;如果DX = 1，那么它是奇数

	jz even			; 如果 [cluster] 是偶数，则删除最后 4 位单词
					; 与下一个集群;如果奇数，则删除前 4 位

odd:
	shr ax, 4		; 移出前 4 位（它们属于另一个条目）
	jmp short next_cluster_cont


even:
	and ax, 0FFFh			; 屏蔽最后 4 位


next_cluster_cont:
	mov word [cluster], ax	; 存储群集

	cmp ax, 0FF8h			; FF8h = FAT12 中文件标记的结尾
	jae end

	add word [pointer], 512	; 增加缓冲区指针 1 扇区长度
	jmp load_file_sector


end:					; 我们有要加载的文件！
	pop ax				; 清理堆栈（AX 之前已推送）
	mov dl, byte [bootdev]		; 为内核提供引导设备信息

	jmp 2000h:0000h			    ; 跳转到加载内核的入口点！


; ------------------------------------------------------------------
; 引导加载程序子例程

reboot:
	mov ax, 0
	int 16h				; 等待输入
	mov ax, 0
	int 19h				; 重新启动系统


print_string:			; 以 SI 格式输出字符串到屏幕
	pusha

	mov ah, 0Eh			; INT 10H电传打字功能

.repeat:
	lodsb				; 从字符串中获取字符
	cmp al, 0
	je .done			; 如果 char 为零，则字符串结尾
	int 10h				; 否则，请打印它
	jmp short .repeat

.done:
	popa
	ret


reset_floppy:	; 输入： [引导开发] = 引导设备;OUT：错误时进行进位设置
	push ax
	push dx
	mov ax, 0
	mov dl, byte [bootdev]
	stc
	int 13h
	pop dx
	pop ax
	ret


l2hts:		    ; 计算 int 13h 的扬程、轨道和扇区设置
			    ; 输入：AX 中的逻辑扇区，输出：int 13h 的正确寄存器
	push bx
	push ax

	mov bx, ax			    ; 保存逻辑扇区

	mov dx, 0			    ; 首先是扇区
	div word [SectorsPerTrack]
	add dl, 01h			    ; 物理扇区从 1 开始
	mov cl, dl			    ; 扇区属于 CL 为 int 13h
	mov ax, bx

	mov dx, 0			    ; 现在计算头部
	div word [SectorsPerTrack]
	mov dx, 0
	div word [Sides]
	mov dh, dl			    ; 头部/侧面
	mov ch, al			    ; 跟踪

	pop ax
	pop bx

	mov dl, byte [bootdev]	; 设置正确的设备

	ret


; ------------------------------------------------------------------
; 字符串和变量

	kern_filename	db "KERNEL  BIN"	; VimdropOS内核文件名

	disk_error	db "Floppy error! Press any key...", 0
	file_not_found	db "KERNEL.BIN not found!", 0

	bootdev		db 0 	; 启动设备编号
	cluster		dw 0 	; 我们要加载的文件的群集
	pointer		dw 0 	; 指针进入缓冲区，用于加载内核


; ------------------------------------------------------------------
; 引导扇区结束和缓冲区启动

	times 510-($-$$) db 0	; 引导扇区的余数用零填充
	dw 0AA55h		        ; 引导签名（不要更改！）


buffer:				        ; 磁盘缓冲区开始（在此之后 8k，堆栈启动）


; ==================================================================

