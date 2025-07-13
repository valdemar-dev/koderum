// 1. Includes and Defines
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#define PI 3.14159
#define SQUARE(x) ((x)*(x))
_Static_assert(sizeof(int) == 4, "int must be 4 bytes");

// 2. Types & Typedefs
typedef unsigned int uint;
typedef struct Person Person;
typedef enum Color Color;

// 3. Enums & Structs
enum Color { RED, GREEN = 5, BLUE };
struct Person {
    const char *name;
    uint age;
};

// Anonymous structs/unions (C11+)
union Data {
    int i;
    float f;
};

// 4. Global Variables & Literals
const char *greeting = "Hello";
const int binary = 0b1010;
const int hex = 0xFF;
const int oct = 0755;
const float fnum = 1.23e2f;
const char ch = 'A';
const char *multi_line =
    "line 1\n"
    "line 2";

// 5. Function Declarations
int add(int a, int b);
void log_person(const Person *p);
_Noreturn void fatal(const char *msg); // C11

// 6. Function Definitions
int add(int a, int b) {
    return a + b;
}
void log_person(const Person *p) {
    printf("Name: %s, Age: %u\n", p->name, p->age);
}
_Noreturn void fatal(const char *msg) {
    fprintf(stderr, "Fatal: %s\n", msg);
    exit(1);
}

// 7. Pointers & Memory
void *mem = NULL;
int *arr = NULL;
arr = malloc(10 * sizeof(int));
if (arr) memset(arr, 0, 10 * sizeof(int));
free(arr);

// 8. Arrays & Strings
char buffer[128] = "init";
int nums[] = {1, 2, 3};
size_t len = sizeof(nums)/sizeof(nums[0]);
strcpy(buffer, "Updated");

// 9. Control Flow
for (int i = 0; i < 10; i++) continue;
while (0) break;
do { printf("run once\n"); } while (0);
if (len > 0) {}
else if (len == 0) {}
else {}

switch (nums[0]) {
    case 1: break;
    default: break;
}

// 10. Compound Literals & Designators
int *dyn = (int[]) {1, 2, 3};
struct Person p = {.name = "Alice", .age = 30};

// 11. Function Pointers
int (*op)(int, int) = add;
printf("%d\n", op(2, 3));

// 12. Variadic Functions
#include <stdarg.h>
void print_all(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    while (*fmt)
        if (*fmt++ == 'd') printf("%d ", va_arg(args, int));
    va_end(args);
}

// 13. Inline & Static
inline int mul(int x, int y) { return x * y; }
static int static_helper(void) { return 42; }

// 14. Macros & _Generic (C11)
#define max(a,b) ((a) > (b) ? (a) : (b))
#define type_of(x) _Generic((x), int: "int", float: "float", default: "unknown")

// 15. Thread & Atomics (C11+)
#include <threads.h>
#include <stdatomic.h>
atomic_int counter = 0;
int thread_func(void *arg) {
    atomic_fetch_add(&counter, 1);
    return 0;
}

// 16. Inline Assembly (GCC/Clang)
#ifdef __GNUC__
__asm__("nop");
#endif

// 17. File I/O
FILE *f = fopen("file.txt", "r");
if (f) {
    char line[128];
    fgets(line, sizeof line, f);
    fclose(f);
}

// 18. Error Handling
errno = 0;
strtol("abc", NULL, 10);
if (errno) perror("strtol");

// 19. Preprocessor Tricks
#if defined(_WIN32)
    #define PLATFORM "Windows"
#elif defined(__linux__)
    #define PLATFORM "Linux"
#else
    #define PLATFORM "Other"
#endif

// 20. Main Function
int main(void) {
    Person p = {"Bob", 25};
    log_person(&p);
    printf("Max: %d\n", max(3, 4));
    print_all("ddd", 1, 2, 3);
    return 0;
}
