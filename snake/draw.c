#include "draw.h"
#include <stdio.h>

void drawPixel(char c, int x, int y){
	printf("\x1b[%d;%dH", x, y*2); //move cursor to x,y
	printf("%c%c",c , c); //print char in set pos
	printf("\x1b[H"); // return curor to 0,0
	fflush(stdout); //force to empty buffer
}

void drawApple(int x, int y){
	printf("\x1b[%d;%dH", x, y);
	printf("\033[48;5;196m  \033[0m"); // fondo rojo (bloque)
	printf("\x1b[H");
	fflush(stdout);
}

void drawSnake(int x, int y){
	printf("\x1b[%d;%dH", x, y); //move cursor to x,y
	printf("\033[42m  \033[0m");
	printf("\x1b[H"); // return curor to 0,0
	fflush(stdout); //force to empty buffer
}

void rmPixel(int x, int y){
	printf("\x1b[%d;%dH", x, y); //move cursor to x,y
	printf("  ");
	printf("\x1b[H"); // return curor to 0,0
	fflush(stdout); //force to empty buffer
}

void drawLine(char c, int x1, int y1, int x2, int y2){
	//ONLY WORKS IF LINES GO FROM LEFT TO RIGHT

	int dx = x2 - x1;
	int dy = y2 - y1;
	int D = 2*dy - dx;
	int y = y1;

	if(dx==0){
		for(; y<y2; y++){
			drawPixel(c, x1, y);
		}
		return;
	}

	for(int x = x1; x<x2; x++){ //bresenham's algorithm wikipedia example
		drawPixel(c, x, y);
		if(D>0){
			y++;
			D-=2*dx;
		}
		D+=2*dy;
	}
}

void clearScreen(){
	printf("\x1b[2J"); //clear screen
	printf("\x1b[H"); //set cursor pos to 0,0
	fflush(stdout); //force to empty buffer
}

void drawMap(int width, int height){
    clearScreen();

    // Borde superior e inferior
    for(int y = 1; y <= width; y++){
        // Borde superior
        printf("\x1b[%d;%dH", 1, y*2);
        printf("\033[48;5;12m  \033[0m");
        // Borde inferior
        printf("\x1b[%d;%dH", height, y*2);
        printf("\033[48;5;12m  \033[0m");
    }

    // Borde izquierdo y derecho
    for(int x = 2; x < height; x++){
        // Borde izquierdo
        printf("\x1b[%d;%dH", x, 1*2);
        printf("\033[48;5;12m  \033[0m");
        // Borde derecho
        printf("\x1b[%d;%dH", x, width*2);
        printf("\033[48;5;12m  \033[0m");
    }

    printf("\x1b[H"); // volver cursor a 0,0
    fflush(stdout);
}
