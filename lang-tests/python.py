# Python syntax showcase

import math
from collections import defaultdict

class Example:
    class_var = 42

    def __init__(self, value: int):
        self.value = value
        self.data = [i for i in range(5)]
        self.dict_data = {k: v for k, v in zip('abc', range(3))}

    def method(self, x: float) -> float:
        try:
            result = math.sqrt(x)
        except ValueError as e:
            result = float('nan')
        finally:
            self.log(result)
        return result

    @staticmethod
    def static_method(x: int) -> int:
        return x ** 2

    @classmethod
    def class_method(cls, x: int) -> int:
        return cls.class_var + x

def generator(n: int):
    yield from (i * i for i in range(n))

async def async_function():
    await some_coroutine()

match (x := 3):
    case 1 | 2:
        result = "one or two"
    case 3:
        result = "three"
    case _:
        result = "other"

lambda_func = lambda x: x + 1

with open("file.txt", "w") as f:
    f.write("test")

# End of showcase
