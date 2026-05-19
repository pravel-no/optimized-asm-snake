# Makefile for compiling the optimized 16-bit ASM Snake
ASM=nasm
FLAGS=-f bin
SRC=src/snake.asm
OUT=snake.com

all: $(OUT)

$(OUT): $(SRC)
	$(ASM) $(FLAGS) $(SRC) -o $(OUT)

clean:
	rm -f $(OUT)
