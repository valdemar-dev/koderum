#version 330 core

uniform sampler2D firstTexture;
uniform sampler2D backgroundTexture;
uniform bool doSampleRGB;

in vec2 TexCoord;
in vec4 Color;
out vec4 FragColor;

void main() {
    if (TexCoord.x < 0.0) {
        FragColor = Color;
        return;
    }


    if (doSampleRGB) {
        vec4 texColor = texture(firstTexture, TexCoord);
        float alpha = texColor.a;
    
        if (alpha <= 0.1) {
            discard;
        }

        FragColor = vec4(texColor.rgb, texColor.a * Color.a);
    } else {
        float alpha = texture(firstTexture, TexCoord).r; 
        
        if (alpha <= 0.1) { 
            discard; 
        }
        
        FragColor = vec4(Color.rgb, alpha * Color.a);
    }
}

