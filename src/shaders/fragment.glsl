#version 330 core

uniform sampler2D firstTexture;
uniform sampler2D backgroundTexture;

in vec2  TexCoord;
in vec4  Color;
out vec4 FragColor;

const float GAMMA = 2.2;

void main() {
    if (TexCoord.x < 0.0) {
        FragColor = Color;
        return;
    }

    float coverage = texture(firstTexture, TexCoord).r;
    if (coverage <= 0.0) {
        discard;
    }

    vec3 textPM = Color.rgb * coverage;

    vec3 textLin = pow(textPM, vec3(GAMMA));
    vec3 bgLin   = pow(texture(backgroundTexture, TexCoord).rgb, vec3(GAMMA));

    vec3 blendedLin = mix(bgLin, textLin, coverage);

    vec3 blendedSRGB = pow(blendedLin, vec3(1.0 / GAMMA));

    FragColor = vec4(blendedSRGB, coverage);
}

