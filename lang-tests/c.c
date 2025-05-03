// C syntax showcase

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define SQUARE(x) ((x) * (x))
typedef struct {
    int a;
    float b;
} Example;

enum Status { OK, ERROR };

void print_array(const int *arr, size_t len) {
    for (size_t i = 0; i < len; ++i) {
        printf("%d\n", arr[i]);
    }
}

int compute(int x) {
    if (x < 0) return -1;
    switch (x) {
        case 0: return 0;
        case 1: return 1;
        default: return x * 2;
    }
}

int main(void) {
    int a = 5, b = 10;
    
    float c = (float)a / b;
    
    int arr[] = {1, 2, 3, 4, 5};
    
    int *dyn_arr = malloc(5 * sizeof(int));
    
    if (!dyn_arr) return EXIT_FAILURE;
    
    for (int i = 0; i < 5; ++i) dyn_arr[i] = i * i;
    
    print_array(dyn_arr, 5);
    free(dyn_arr);

    Example ex = { .a = 1, .b = 2.5f };
    
    enum Status s = OK;
    
    printf("SQUARE(3): %d\n", SQUARE(3));
    
    return 0;
}
