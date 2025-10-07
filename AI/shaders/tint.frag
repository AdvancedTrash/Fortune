#version 120
uniform sampler2D iChannel0;
uniform vec4 tintColor;
uniform float tintAlpha;

void main()
{
	vec4 c = texture2D( iChannel0, gl_TexCoord[0].xy);
	gl_FragColor = c*gl_Color;
	
	gl_FragColor.rgba = mix(gl_FragColor, tintColor, tintAlpha) * gl_FragColor.a;
	
}