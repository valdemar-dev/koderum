#version 330 core

uniform sampler2D firstTexture;

out vec4 FragColor;
in vec2 TexCoord;
in vec4 Color;

void main() {
    if (TexCoord.x < 0) {
        FragColor = Color;
    } else {
        vec4 Texture = texture(firstTexture, TexCoord);

        float grayscale = texture(firstTexture, TexCoord).r;

        vec4 FinalTexture = vec4(vec3(grayscale), 1.0);
        // vec4 FinalTexture = vec4(Color.x, Color.y, Color.z, Texture.r);

        FragColor = FinalTexture;
    }

    if (FragColor.a == 0.0)
        discard;
}

