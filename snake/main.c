#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "draw.h"
#include "input.h"

#define MAX_APPLES 10
#define MAX_SNAKE 10000

int map_X;
int map_Y;
char dir = 'w';
int applesX[MAX_APPLES];
int applesY[MAX_APPLES];
int snakeX[MAX_SNAKE] = {10};
int snakeY[MAX_SNAKE] = {10};
int tailX, tailY;
int length = 1;
int numApples = 0;

void move_snake(){
	//save tail
	tailX = snakeX[length-1];
	tailY = snakeY[length-1];
	//move body back to front
	for (int i = length -1; i> 0; i--){
		snakeX[i] = snakeX[i-1];
		snakeY[i] = snakeY[i-1];
	}

	//move head
	switch(dir){
		case'w': snakeX[0]--; break;
		case's': snakeX[0]++; break;
		case'a': snakeY[0]--; break;
		case'd': snakeY[0]++; break;
		case'q': exit(0);
	}
}


void check_apple(){
	for(int i = 0; i < MAX_APPLES; i++){
		if (snakeX[0] == applesX[i] && snakeY[0] == applesY[i]) { //remove apple
			length++;
			applesX[i] = -1;
			applesY[i] = -1;
			numApples--;
			break; //only can eat one apple per loop
		}
	}
}

void draw_snake(){

	//wall collision
	if(snakeX[0] <= 1 || snakeX[0] >= map_X || snakeY[0] <= 1 || snakeY[0] >= map_Y){ //game lost
		clearScreen();
		printf("GAME OVER");
		exit(0);
	}

	//collide with self
	for (int i = 1; i < length; i++){
		if(snakeX[0] == snakeX[i] && snakeY[0] == snakeY[i]) {
			clearScreen();
			printf("GAME OVER");
			exit(0);
		}
	}
	//remove tail and draw head
	rmPixel(tailX, tailY*2);
	drawSnake(snakeX[0], snakeY[0]*2);
}
	

void spawn_apple() {
	if(numApples >= MAX_APPLES) {
		return;
	}

	for(int i = 0; i < MAX_APPLES; i++) {
		if(applesX[i] == -1 && applesY[i] == -1) {
			int x, y;
			int valid;
			int attempts = 0;
			do {
				valid = 1;
				x = rand() % (map_X-2) + 2;
				y = rand() % (map_Y-2) + 2;

				//check that apple does not collide with snake
				for(int j = 0; j < length; j++) {
					if(snakeX[j] == x && snakeY[j] == y) {
						valid = 0;
						break;
					}
				}
				//check collisions with other apples
				for(int j = 0; j < MAX_APPLES; j++) {
					if(applesX[j] == x && applesY[j] == y) {
						valid = 0;
						break;
					}
				}
				attempts++;
				if(attempts > 1000) return;
			} while(!valid);

			applesX[i] = x;
			applesY[i] = y;
			drawApple(applesX[i], applesY[i]*2);
			numApples++;
			break;
		}
	}
}

int main(int argc, char* argv[]){
	if(argc!=3) return printf("Expected map x y dimensions\n");
	map_X = atoi(argv[1]);
	map_Y = atoi(argv[2]);
	if(map_X < 10 || map_X > 100 || map_Y < 10 || map_Y > 100) return printf("Map dimensions must be between 10 and 100\n");
	
	for(int i = 0; i< MAX_APPLES; i++){
		applesX[i] = applesY[i] = -1;
	}

	set_conio_terminal_mode();
	drawMap(map_Y, map_X);

	while(1){
		if(kbhit()){
			dir = getchar();
		}

		spawn_apple();
		move_snake();
		check_apple();
		draw_snake();


		usleep(300000);
	}
}
