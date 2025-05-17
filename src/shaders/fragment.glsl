/*
#version 330 core                                                                                       
                                                                                                        
uniform sampler2D firstTexture;                                                                         
uniform sampler2D backgroundTexture;                                                                    
                                                                                                        
in vec2 TexCoord;                                                                                       
in vec4 Color;                                                                                          
out vec4 FragColor;                                                                                     
                                                                                                        const float GAMMA = 2.2;                                                                                
                                                                                                        
vec3 toLinear(vec3 c) {                                                                                 
    return pow(c, vec3(GAMMA));                                                                         }                                                                                                       
                                                                                                        
vec3 toSRGB(vec3 c) {                                                                                   
    return pow(c, vec3(1.0 / GAMMA));                                                                   
}                                                                                                       
                                                                                                        
void main() {                                                                                           
    if (TexCoord.x < 0.0) {                                                                             
        FragColor = Color;                                                                              
        return;                                                                                         
    }                                                                                                   
                                                                                                        
    float alpha = texture(firstTexture, TexCoord).r;
    if (alpha == 0.0)
        discard;                                        
                     
    vec3 textLin = toLinear(Color.rgb);   
    vec3 bgLin   = toLinear(texture(backgroundTexture, TexCoord).rgb);
                                                                   
    vec3 outLin  = mix(bgLin, textLin, alpha);                
                                
    vec3 outSRGB = toSRGB(outLin);          
     
    FragColor = vec4(outSRGB, 1.0);
}                
*/
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

    if(alpha <= 0.1) discard;

    FragColor = vec4(Color.rgb, alpha);
}

