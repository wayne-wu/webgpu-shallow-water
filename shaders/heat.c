uniform float time;
uniform vec2 resolution;
uniform sampler2D sampler;

vec4 sample(vec2 uv)
{
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
    {
        return vec4(0.0);
    }
    return texture2D(sampler, uv);
}

void main()
{
    vec2 EPS = vec2(0.01, 0);
    vec2 uv = gl_FragCoord.xy / resolution.xy;
    vec4 U = sample(uv);

    vec4 Uxf = sample(uv + EPS.xy);
    vec4 Uxb = sample(uv - EPS.xy);
    vec4 Uxx = (Uxf - 2.0 * U + Uxb) / (EPS.x * EPS.x);

    vec4 Uyf = sample(uv + EPS.yx);
    vec4 Uyb = sample(uv - EPS.yx);
    vec4 Uyy = (Uyf - 2.0 * U + Uyb) / (EPS.x * EPS.x);

    float dt = EPS.x * EPS.x * 0.2;

    gl_FragColor = U + dt * (Uyy + Uxx);
}