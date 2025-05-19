# Koderum
vim-style text editor written in Odin.

## Libraries Used
- OpenGL
- GLFW
- FreeType2 (wrote bindings myself)

## Docs
(D)&(F) -> Left-Right Movement.
(Ctrl + K) -> Prev Hit
(Ctrl + J) -> Next Hit
(Enter) -> Get Results
(ANY CHAR) -> Type Search Term
(G) -> Enable Search Mode

(Ctrl + G) -> Create file using current Search Term, (if a file with search term is not already found.)
(Ctrl + F) -> Rename Selected File.
(Ctrl + D) -> Delete Selected File.
(Ctrl + S) -> Store File Explorer CWD.
(O) -> Open File Explorer.

(Q) -> Toggle File Info View

(Ctrl + S) -> Save active buffer.

(A) -> Move buffer cursor to the end of the current line, and go into Text Insert Mode.
(I) -> Go into Text Insert mode.

(U) -> Move forwards in the current bufferline until a word-break character is detected. (and then move past it)
(R) -> Move backwards in the current bufferline until a word-break character is detected.

(J)&(K) -> Up-Down Movement.