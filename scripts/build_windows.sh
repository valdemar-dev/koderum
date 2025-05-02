# Compile source files to object files
odin build src \
  -file \
  -build-mode:object \
  -target=windows_amd64 \
  -print-linker-flags


x86_64-w64-mingw32-gcc -c scripts/fix.c -o a.obj \
  -I/home/v/mingw-windows-libs/include


zig cc -target x86_64-windows-gnu \
  src-*.obj \
  -L/home/v/mingw-windows-libs/lib \
  -I/home/v/mingw-windows-libs/include \
  -lfreetype \
  -lglfw3 \
  -lgdi32 \
  -lole32 \
  -lkernel32 \
  -luser32 \
  -lopengl32 \
  -lmingwex \
  -static \
  -o text_editor.exe
