#version 120
uniform sampler2D iChannel0;

uniform vec2 bufferSize;
uniform float pixelSize;

void main()
{
	vec2 xy = floor(gl_FragCoord.xy/pixelSize)*pixelSize/bufferSize;
	vec4 c = texture2D(iChannel0, xy);

	// Debug
	/*bool darken = (mod(gl_FragCoord.x/pixelSize,2.0) < 1.0);
	
	if (mod(gl_FragCoord.y/pixelSize,2.0) < 1.0)
	{
		darken = !darken;
	}
	if (darken)
	{
		c.rgb *= 0.25;
	}*/
	
	gl_FragColor = c*gl_Color;
}