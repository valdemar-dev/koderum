#version 330 core

uniform sampler2D firstTexture;       // Glyph coverage map (alpha mask)
uniform sampler2D backgroundTexture;  // Rendered background color (sRGB)

in  vec2  TexCoord;
in  vec4  Color;       // Vertex color in sRGB
out vec4 FragColor;

const float GAMMA = 2.2;

// Convert sRGB to linear RGB
vec3 toLinear(vec3 c) {
    return pow(c, vec3(GAMMA));
}

// Convert linear RGB to sRGB
vec3 toSRGB(vec3 c) {
    return pow(c, vec3(1.0 / GAMMA));
}

void main() {
    // Fallback: draw non-text geometry when TexCoord.x < 0
    if (TexCoord.x < 0.0) {
        FragColor = Color;
        return;
    }

    // Sample glyph mask alpha (0–1)
    float alpha = texture(firstTexture, TexCoord).r;
    if (alpha == 0.0)
        discard;

    // Decode sRGB inputs to linear space
    vec3 textLin = toLinear(Color.rgb);  
    vec3 bgLin   = toLinear(texture(backgroundTexture, TexCoord).rgb);

    // Linear "over" composite: C = α·Cs + (1−α)·Cd
    vec3 outLin  = alpha * textLin + (1.0 - alpha) * bgLin;  // Porter‑Duff over :contentReference[oaicite:2]{index=2}

    // Encode back to sRGB
    vec3 outSRGB = toSRGB(outLin);

    FragColor = vec4(outSRGB, 1.0);
}

