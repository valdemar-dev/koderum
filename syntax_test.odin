my_string : string = "hi"
my_rune : rune = 'r'

float_16 : f16 = 0
int_32 : i32 = 0
integer : int = 0
boolean : bool = false
some_map : map[rune]int = {
    'x' = 5,
}

person :: struct {
    name: string,
}

sean = person{
    name = "sean",
}

my_proc :: proc (param: string) -> bool {
    if param == "secretPassword123" {
        return true
    }
    
    return false
} 