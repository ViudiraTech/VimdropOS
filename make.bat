echo off
cd App
nasm -O0 -f bin -o FileMan.bin FileMan.asm
nasm -O0 -f bin -o FisherGame.bin FisherGame.asm
nasm -O0 -f bin -o HexEdit.bin HexEdit.asm
nasm -O0 -f bin -o Piano.bin Piano.asm
nasm -O0 -f bin -o PongGame.bin PongGame.asm
nasm -O0 -f bin -o TextEdit.bin TextEdit.asm
nasm -O0 -f bin -o Viewer.bin Viewer.asm
move *.bin ../makeout/
cd..
cd kernel
nasm -O0 -f bin -o kernel.bin kernel.asm
move kernel.bin ../makeout/
copy VimdropOS.img ..\
cd..
cd pcxFile
copy *.pcx ..\makeout\
cd..
cd txtFile
copy *.txt ..\makeout\
echo �������!���ֶ�ʹ��winimage.exe��makeout�����ļ���ӵ�VimdropOS.img
pause