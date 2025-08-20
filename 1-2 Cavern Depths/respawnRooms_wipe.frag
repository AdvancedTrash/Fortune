#version 120
uniform sampler2D iChannel0;

uniform sampler2D wipeTexture;
uniform float cutoff;

#include "shaders/logic.glsl"

void main()
{
    vec2 xy = gl_TexCoord[0].xy;

    vec4 w = texture2D(wipeTexture, xy);
	vec4 c = texture2D(iChannel0, xy);

    c.r *= gt(w.r,cutoff);
    c.g *= gt(w.g,cutoff);
    c.b *= gt(w.b,cutoff);
	
	gl_FragColor = c*gl_Color;
}