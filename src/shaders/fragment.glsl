#version 330 core

uniform sampler2D firstTexture;
uniform sampler2D backgroundTexture;

in vec2 TexCoord;
in vec4 Color;
out vec4 FragColor;
 
void main() {
    if (TexCoord.x < 0.0) {
        FragColor = Color;
        return;
    }  

    float alpha = texture(firstTexture, TexCoord).r;

    if (alpha <= 0.1) {
        discard;
    }

    FragColor = vec4(Color.rgb, alpha * Color.a);
}

